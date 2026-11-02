// Connecteur Meta Llama API (serveur uniquement, clé jamais exposée).
//
// Documentation officielle (llama.developer.meta.com) : base
// https://api.llama.com/v1, authentification "Authorization: Bearer
// LLAMA_API_KEY", GET /models, POST /chat/completions (réponse native :
// completion_message.content.text ; response_format json_schema supporté).
//
// Trois états explicites : non configuré / vérifié / erreur d'accès.
// Aucun résultat n'est simulé : sans accès vérifié, tout appel est refusé.
// Chaque appel réel (ou tentative) produit un MetaCallRecord horodaté
// avec modèle, entrées, sortie brute analysée, erreur, latence et usage
// si l'API le fournit. La clé n'apparaît dans aucun enregistrement.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'grouping.dart';
import 'types.dart';

enum MetaState { unconfigured, verified, accessError }

class MetaCallRecord {
  final String id;
  final String kind; // verify-models | extraction | rapprochement
  final String? model;
  final String status; // ok | erreur | refuse
  final String? error;
  final int latencyMs;
  final Map<String, dynamic>? usage;
  final String at;
  final Map<String, dynamic> input; // ids + textes envoyés (jamais la clé)
  final Map<String, dynamic>? output;

  const MetaCallRecord({
    required this.id,
    required this.kind,
    required this.model,
    required this.status,
    required this.error,
    required this.latencyMs,
    required this.usage,
    required this.at,
    required this.input,
    required this.output,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'model': model,
        'status': status,
        'error': error,
        'latencyMs': latencyMs,
        'usage': usage,
        'at': at,
        'input': input,
        'output': output,
      };

  static MetaCallRecord fromJson(Map<String, dynamic> j) => MetaCallRecord(
        id: j['id'] as String,
        kind: j['kind'] as String,
        model: j['model'] as String?,
        status: j['status'] as String,
        error: j['error'] as String?,
        latencyMs: (j['latencyMs'] as num).toInt(),
        usage: j['usage'] as Map<String, dynamic>?,
        at: j['at'] as String,
        input: (j['input'] as Map? ?? {}).cast<String, dynamic>(),
        output: j['output'] as Map<String, dynamic>?,
      );
}

class MetaException implements Exception {
  final String message;
  final MetaCallRecord record;
  const MetaException(this.message, this.record);
  @override
  String toString() => message;
}

/// Base officielle Meta Model API (developer.meta.ai/docs/api-reference).
const String metaOfficialBaseUrl = 'https://api.meta.ai/v1';

/// Libellé explicite par statut HTTP (distinction exigée des erreurs).
String metaHttpErrorLabel(int status, {String? errorType, String? errorCode}) {
  final detail = [errorType, errorCode].whereType<String>().join('/');
  final suffix = detail.isEmpty ? '' : ' ($detail)';
  return switch (status) {
    401 => 'HTTP 401 authentification refusée$suffix',
    402 => 'HTTP 402 paiement/facturation requis$suffix',
    403 => 'HTTP 403 autorisation insuffisante$suffix',
    404 => 'HTTP 404 ressource ou modèle introuvable$suffix',
    429 => 'HTTP 429 limite de débit dépassée$suffix',
    >= 500 => 'HTTP $status erreur temporaire du service$suffix',
    _ => 'HTTP $status$suffix',
  };
}

class MetaConnector {
  final MetaState state;
  final List<String> models;
  final String message;
  final String? _apiKey; // serveur uniquement, jamais sérialisée
  final String baseUrl;
  final String? preferredModel;
  final String? keySource; // NOM de la variable d'environnement, jamais la clé

  MetaConnector._(this.state, this.models, this.message,
      {String? apiKey,
      this.baseUrl = metaOfficialBaseUrl,
      this.preferredModel,
      this.keySource})
      : _apiKey = apiKey;

  /// Variable principale : MODEL_API_KEY (documentation Meta Model API).
  /// Alias historiques acceptés uniquement en repli explicite (anciens
  /// déploiements Llama API), jamais mélangés : la source est conservée.
  /// La clé est utilisée EXACTEMENT telle que fournie, sans transformation.
  static String? keySourceFromEnv(Map<String, String> env) {
    for (final name in ['MODEL_API_KEY', 'LLAMA_API_KEY', 'CITYRESOLVE_META_API_KEY']) {
      final v = env[name];
      if (v != null && v.isNotEmpty) return name;
    }
    return null;
  }

  static String? keyFromEnv(Map<String, String> env) {
    final source = keySourceFromEnv(env);
    return source == null ? null : env[source];
  }

  /// État depuis l'environnement, sans aucun appel réseau.
  factory MetaConnector.fromEnvironment(Map<String, String> env) {
    final source = keySourceFromEnv(env);
    final key = source == null ? null : env[source];
    final base = env['CITYRESOLVE_META_BASE_URL'] ?? metaOfficialBaseUrl;
    if (key == null) {
      return MetaConnector._(MetaState.unconfigured, [],
          'Non configuré : MODEL_API_KEY absente. Moteur classique actif.',
          baseUrl: base, preferredModel: env['CITYRESOLVE_META_MODEL']);
    }
    return MetaConnector._(MetaState.accessError, [],
        'Clé présente via $source mais accès non vérifié (POST /api/meta/verify requis).',
        apiKey: key,
        baseUrl: base,
        preferredModel: env['CITYRESOLVE_META_MODEL'],
        keySource: source);
  }

  factory MetaConnector.error(String message) =>
      MetaConnector._(MetaState.accessError, [], message);

  MetaConnector verified(List<String> authorizedModels) => MetaConnector._(
      MetaState.verified, authorizedModels,
      'Connecté et vérifié : ${authorizedModels.length} modèle(s) autorisé(s).',
      apiKey: _apiKey,
      baseUrl: baseUrl,
      preferredModel: preferredModel,
      keySource: keySource);

  String? get model =>
      preferredModel ?? (models.isEmpty ? null : models.first);

  static const List<String> capabilities = [
    'analyse-texte',
    'analyse-image (non branchée)',
    'extraction-structuree',
    'rapprochement-signalements',
  ];

  Map<String, dynamic> toJson() => {
        'state': state.name,
        'models': models,
        'model': model,
        'message': message,
        'capabilities': capabilities,
        'baseUrl': baseUrl,
        'keySource': keySource,
        'integration':
            'connecteur serveur réel Meta Model API (api.meta.ai), aucun résultat simulé',
      };

  int _seq = 0;
  MetaCallRecord _record(String kind, String? mdl, String status,
          String? error, Stopwatch sw, Map<String, dynamic> input,
          Map<String, dynamic>? output, Map<String, dynamic>? usage) =>
      MetaCallRecord(
        id: 'META-${++_seq}-${DateTime.now().millisecondsSinceEpoch}',
        kind: kind,
        model: mdl,
        status: status,
        error: error,
        latencyMs: sw.elapsedMilliseconds,
        usage: usage,
        at: DateTime.now().toUtc().toIso8601String(),
        input: input,
        output: output,
      );

  Future<HttpClientResponse> _request(
      String method, String path, Map<String, dynamic>? body, Duration timeout) async {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    try {
      final uri = Uri.parse('$baseUrl$path');
      final req = method == 'GET'
          ? await client.getUrl(uri).timeout(timeout)
          : await client.postUrl(uri).timeout(timeout);
      req.headers.set('Authorization', 'Bearer $_apiKey');
      req.headers.contentType = ContentType.json;
      if (body != null) req.write(jsonEncode(body));
      return await req.close().timeout(timeout);
    } finally {
      client.close(force: false);
    }
  }

  /// Vérification réelle : GET /models. Ne fabrique aucun modèle.
  Future<(MetaConnector, MetaCallRecord)> verify(
      {Duration timeout = const Duration(seconds: 15)}) async {
    final sw = Stopwatch()..start();
    const input = {'endpoint': 'GET /models'};
    if (_apiKey == null) {
      final r = _record('verify-models', null, 'refuse',
          'MODEL_API_KEY absente', sw, input, null, null);
      return (MetaConnector.fromEnvironment(Platform.environment), r);
    }
    try {
      final resp = await _request('GET', '/models', null, timeout);
      final text = await utf8.decoder.bind(resp).join();
      sw.stop();
      if (resp.statusCode != 200) {
        final envErr = _errorEnvelope(text);
        final label = metaHttpErrorLabel(resp.statusCode,
            errorType: envErr?['type']?.toString(),
            errorCode: envErr?['code']?.toString());
        final r = _record('verify-models', null, 'erreur',
            '$label sur /models', sw, input,
            {'httpStatus': resp.statusCode, 'error': envErr}, null);
        return (
          MetaConnector._(MetaState.accessError, [],
              'Accès Meta Model API refusé : $label. Vérifier la clé dans le tableau de bord Meta Model API.',
              apiKey: _apiKey, baseUrl: baseUrl, preferredModel: preferredModel, keySource: keySource),
          r
        );
      }
      final parsed = jsonDecode(text) as Map<String, dynamic>;
      final models = ((parsed['data'] as List?) ?? [])
          .map((e) => (e as Map)['id']?.toString())
          .whereType<String>()
          .toList();
      final r = _record(
          'verify-models', null, 'ok', null, sw, input, {'models': models}, null);
      if (models.isEmpty) {
        // Cas réel observé : clé acceptée (HTTP 200) mais le compte
        // n'a accès à aucun modèle. Ne jamais inventer de modèle.
        return (
          MetaConnector._(MetaState.accessError, [],
              'Clé acceptée par Meta (HTTP 200) mais aucun modèle autorisé retourné par /models pour ce compte : IA indisponible.',
              apiKey: _apiKey, baseUrl: baseUrl, preferredModel: preferredModel, keySource: keySource),
          r
        );
      }
      return (verified(models), r);
    } catch (e) {
      sw.stop();
      final r = _record('verify-models', null, 'erreur',
          'échec réseau/délai : $e', sw, input, null, null);
      return (
        MetaConnector._(MetaState.accessError, [],
            'Vérification impossible : $e',
            apiKey: _apiKey, baseUrl: baseUrl, preferredModel: preferredModel, keySource: keySource),
        r
      );
    }
  }

  /// Appel chat réel exigeant une sortie JSON. Lève MetaException sinon.
  Future<Map<String, dynamic>> chatJson({
    required String kind,
    required String system,
    required String user,
    required Map<String, dynamic> inputLog,
    Duration timeout = const Duration(seconds: 30),
    void Function(MetaCallRecord)? onRecord,
  }) async {
    final sw = Stopwatch()..start();
    if (state != MetaState.verified || _apiKey == null) {
      final r = _record(kind, model, 'refuse',
          'Connecteur Meta ${state.name} : appel refusé, aucune réponse simulée.',
          sw, inputLog, null, null);
      onRecord?.call(r);
      throw MetaException(r.error!, r);
    }
    final mdl = model;
    if (mdl == null) {
      final r = _record(kind, null, 'erreur',
          'Aucun modèle autorisé déterminé.', sw, inputLog, null, null);
      onRecord?.call(r);
      throw MetaException(r.error!, r);
    }
    try {
      final resp = await _request('POST', '/chat/completions', {
        'model': mdl,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
        'response_format': {'type': 'json_object'},
        'stream': false,
      }, timeout);
      final text = await utf8.decoder.bind(resp).join();
      sw.stop();
      if (resp.statusCode != 200) {
        final envErr = _errorEnvelope(text);
        final label = metaHttpErrorLabel(resp.statusCode,
            errorType: envErr?['type']?.toString(),
            errorCode: envErr?['code']?.toString());
        final r = _record(kind, mdl, 'erreur',
            '$label sur /chat/completions', sw, inputLog,
            {'httpStatus': resp.statusCode, 'error': envErr}, null);
        onRecord?.call(r);
        throw MetaException(r.error!, r);
      }
      final parsed = jsonDecode(text) as Map<String, dynamic>;
      final content = _contentText(parsed);
      if (content == null) {
        final r = _record(kind, mdl, 'erreur',
            'Réponse Meta sans contenu texte exploitable.', sw, inputLog,
            parsed, _usage(parsed));
        onRecord?.call(r);
        throw MetaException(r.error!, r);
      }
      final jsonText = _extractJson(content);
      final out = jsonDecode(jsonText) as Map<String, dynamic>;
      final r =
          _record(kind, mdl, 'ok', null, sw, inputLog, out, _usage(parsed));
      onRecord?.call(r);
      return out;
    } on MetaException {
      rethrow;
    } catch (e) {
      sw.stop();
      final r = _record(kind, mdl, 'erreur', 'échec appel : $e', sw, inputLog,
          null, null);
      onRecord?.call(r);
      throw MetaException(r.error!, r);
    }
  }

  /// Enveloppe d'erreur OpenAI-style de Meta Model API (sans secret).
  static Map<String, dynamic>? _errorEnvelope(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map && parsed['error'] is Map) {
        return (parsed['error'] as Map).cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }

  static Map<String, dynamic>? _usage(Map<String, dynamic> resp) =>
      resp['usage'] is Map ? (resp['usage'] as Map).cast<String, dynamic>() : null;

  static String? _contentText(Map<String, dynamic> resp) {
    // Format natif Llama API : completion_message.content.text
    final cm = resp['completion_message'];
    if (cm is Map && cm['content'] is Map) {
      final t = (cm['content'] as Map)['text'];
      if (t is String) return t;
    }
    if (cm is Map && cm['content'] is String) return cm['content'] as String;
    // Format compatible OpenAI : choices[0].message.content
    final choices = resp['choices'];
    if (choices is List && choices.isNotEmpty) {
      final msg = (choices.first as Map)['message'];
      if (msg is Map && msg['content'] is String) {
        return msg['content'] as String;
      }
    }
    return null;
  }

  static String _extractJson(String content) {
    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start < 0 || end <= start) return content;
    return content.substring(start, end + 1);
  }
}

/// Extraction structurée d'un signalement (aucune certitude inventée :
/// champ absent du texte -> null + incertitude listée).
Future<Map<String, dynamic>> extractStructuredWithMeta(
  MetaConnector c,
  Report report, {
  Duration timeout = const Duration(seconds: 30),
  void Function(MetaCallRecord)? onRecord,
}) {
  return c.chatJson(
    kind: 'extraction',
    system: 'Tu extrais des informations de signalements municipaux fictifs. '
        'Réponds UNIQUEMENT en JSON. Si une information est absente ou '
        'incertaine, mets null et décris-la dans "incertitudes". '
        'N\'invente jamais de gravité, de lieu ni de fait.',
    user: 'Signalement ${report.id} (catégorie déclarée: ${report.category}) : '
        '"${report.text}"\n'
        'JSON attendu: {"probleme": string, "description": string, '
        '"localisationMentionnee": string|null, '
        '"graviteExprimee": integer 1..5|null, '
        '"expositionMentionnee": string|null, '
        '"incertitudes": [string], "elementsNonVerifies": [string]}',
    inputLog: {'reportId': report.id, 'text': report.text},
    timeout: timeout,
    onRecord: onRecord,
  );
}

/// Listing Meta avec unités explicites (patch unités, local).
///
/// Correctif de l'échec distinct-temps de phase4-misleading, où le
/// modèle écrivait que « l'unité temporelle était absente » et
/// fusionnait deux nids-de-poule à 3 jours d'intervalle : chaque ligne
/// donne t en minutes et x/y en kilomètres, jamais de nombre nu, et
/// chaque paire affiche sa distance en km et son délai en minutes
/// avec conversion (heures/jours). Le retest DEV avec ce listing
/// (phase4-retest-units) sépare distinct-temps : le modèle y écrit
/// explicitement « délai 4320 min = 3,0 jours, délai long pas court ».
String _fmt1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
String _fmt2(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

String formatDelayMin(int dt) {
  if (dt >= 1440) return '$dt min = ${_fmt1(dt / 1440)} jours';
  if (dt >= 60) return '$dt min = ${_fmt1(dt / 60)} heures';
  return '$dt min';
}

/// Listing complet : en-tête d'unités + lignes + paires calculées.
String metaListingWithUnits(List<Report> reports) {
  final lines = <String>[
    'Unités (données ici, ne jamais les supposer absentes) : '
        'x et y en kilomètres (km) sur une grille fictive, '
        't en minutes (min) depuis le début du scénario. '
        '60 min = 1 heure, 1440 min = 1 jour.'
  ];
  for (final r in reports) {
    lines.add(
        '${r.id} | x=${_fmt1(r.x)} km, y=${_fmt1(r.y)} km, t=${r.t} min | catégorie=${r.category} | "${r.text}"');
  }
  lines.add('Distances et délais calculés :');
  for (var i = 0; i < reports.length; i++) {
    for (var j = i + 1; j < reports.length; j++) {
      final a = reports[i], b = reports[j];
      lines.add(
          'Paire ${a.id}-${b.id} : distance ${_fmt2(distKm(a, b))} km, délai ${formatDelayMin(dtMin(a, b))}.');
    }
  }
  return lines.join('\n');
}

/// Proposition de rapprochement Meta : mêmes objets Group que le moteur
/// classique (method: meta), avec justification et incertitude du modèle.
Future<List<Group>> proposeMatchingWithMeta(
  MetaConnector c,
  List<Report> reports, {
  Duration timeout = const Duration(seconds: 45),
  void Function(MetaCallRecord)? onRecord,
}) async {
  final listing = metaListingWithUnits(reports);
  final out = await c.chatJson(
    kind: 'rapprochement',
    system: 'Tu proposes un regroupement de signalements municipaux fictifs '
        'décrivant le même incident réel. Réponds UNIQUEMENT en JSON. '
        'Chaque signalement dans au plus un groupe. Si un rapprochement '
        'est douteux, dis-le dans "incertitude" (0=certain, 1=très douteux) '
        'et justifie. N\'invente aucun signalement. '
        "RÈGLE D'UNITÉS, À APPLIQUER SANS EXCEPTION : les unités SONT "
        'données dans le listing (x et y en kilomètres, t en minutes). '
        'Ne jamais écrire qu\'une unité est absente, inconnue ou non '
        'vérifiable quand le listing la donne. Un délai de 4320 min vaut '
        '3 jours, pas un délai court. Pour un incident ponctuel '
        "(nid-de-poule, fuite d'eau), un délai de plusieurs jours au même "
        "lieu ne prouve pas qu'il s'agit du même incident : deux "
        'incidents distincts restent possibles même avec un texte quasi '
        "identique, et la persistance d'une dégradation ne prouve pas "
        "l'identité.",
    user: 'Signalements:\n$listing\n'
        'JSON attendu: {"groupes": [{"reportIds": [string], '
        '"justification": string, "incertitude": number 0..1}]}',
    inputLog: {'reportIds': reports.map((r) => r.id).toList()},
    timeout: timeout,
    onRecord: onRecord,
  );
  final known = reports.map((r) => r.id).toSet();
  final seen = <String>{};
  final groups = <Group>[];
  var gi = 0;
  for (final gj in (out['groupes'] as List? ?? [])) {
    final g = gj as Map<String, dynamic>;
    final ids = ((g['reportIds'] as List?) ?? [])
        .map((e) => '$e')
        .where((id) => known.contains(id) && seen.add(id))
        .toList()
      ..sort();
    if (ids.isEmpty) continue;
    gi++;
    final inc = (g['incertitude'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.5;
    groups.add(Group(
      id: 'G$gi',
      reportIds: ids,
      confidence: 1.0 - inc,
      singleton: ids.length == 1,
      method: 'meta',
      uncertain: inc >= 0.35,
      uncertaintyReasons:
          inc >= 0.35 ? ['incertitude modèle ${inc.toStringAsFixed(2)}'] : [],
      justification: g['justification']?.toString(),
    ));
  }
  for (final r in reports) {
    if (!seen.contains(r.id)) {
      gi++;
      groups.add(Group(
          id: 'G$gi',
          reportIds: [r.id],
          confidence: 0,
          singleton: true,
          method: 'meta',
          uncertain: true,
          uncertaintyReasons: ['non classé par le modèle : singleton forcé']));
    }
  }
  groups.sort((a, b) => a.reportIds.first.compareTo(b.reportIds.first));
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    groups[i] = Group(
        id: 'G${i + 1}',
        reportIds: g.reportIds,
        confidence: g.confidence,
        singleton: g.singleton,
        method: 'meta',
        uncertain: g.uncertain,
        uncertaintyReasons: g.uncertaintyReasons,
        justification: g.justification);
  }
  // Chaîne de filtres déterministes post-modèle, dans cet ordre :
  // 1. Garde-fou contenu insuffisant (poussé sur main) : même si le
  // modèle propose une fusion impliquant un contenu insuffisant —
  // c'est exactement l'échec inc-vide de phase4-hard, où le modèle avait
  // fusionné deux textes vides avec incertitude 1,0 — la fusion est
  // annulée et chaque signalement concerné redevient un singleton marqué
  // 'garde-fou-contenu-insuffisant'. L'annulation est journalisée dans
  // les groupes retournés eux-mêmes (raison + justification), qui sont
  // persistés par le serveur dans metaGroups ; le nombre de fusions
  // annulées est donc vérifiable groupe par groupe, sans dépendre de
  // l'incertitude du modèle. Un pré-filtre (ne pas envoyer ces textes au
  // modèle) n'a pas été choisi : il masquerait la proposition du modèle
  // au lieu de la corriger visiblement.
  // 2. Porte temps Meta (patch unités, local) : découpe les fusions
  // proposées au-delà du seuil (360 min local, 10080 min étendu).
  // Chaque découpe est comptée (splitGroups) et tracée par une raison
  // 'porte-temps-meta'. Sur le retest DEV, la porte n'a rien eu à
  // découper (le nouveau listing avait déjà corrigé distinct-temps),
  // mais appliquée aux anciennes sorties elle corrige distinct-temps
  // (1 découpe, F1 0,0 -> 1,0) : c'est un filet de sécurité, pas la
  // cause du gain du nouveau listing.
  // 3. Statuts (patch unités, local) : marquent les groupes
  // contradictoires et multi-problème, SANS les découper. Un groupe
  // fusionné signalé n'est pas un incident propre : l'optimiseur et
  // l'humain doivent le voir comme « à vérifier », pas comme une
  // fusion validée. Les statuts ne remplacent pas une vérification
  // humaine, surtout pour la contradiction d'état (résolu contre en
  // cours) et pour le second problème d'un signalement multi-problème.
  final filtered = applyContentGuardrail(reports, groups);
  final gated = applyMetaTimeGate(reports, filtered.groups);
  final statused = applyGroupStatuses(reports, gated.groups);
  return statused.groups;
}

/// Regroupement IA synchrone conservé pour compatibilité : toujours refusé
/// (le vrai chemin est asynchrone, proposeMatchingWithMeta).
List<Group> groupWithMeta(MetaConnector c, List<Report> reports) {
  throw StateError(
      'Connecteur Meta ${c.state.name} : utiliser proposeMatchingWithMeta '
      '(asynchrone). Aucune réponse simulée.');
}
