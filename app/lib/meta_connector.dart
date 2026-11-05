// Meta Model API connector (server only, key never exposed).
//
// Official documentation (developer.meta.ai): base https://api.meta.ai/v1,
// authentication "Authorization: Bearer MODEL_API_KEY", GET /models,
// POST /chat/completions (OpenAI-compatible; images via `image_url`
// content parts in base64 only in `user` messages).
//
// Three explicit states: unconfigured / verified / access error.
// No result is simulated: without verified access, every call is refused.
// Each real call (or attempt) produces a timestamped MetaCallRecord
// with model, inputs, parsed raw output, error, latency and usage
// if the API provides it. The key appears in no record.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'grouping.dart';
import 'media.dart';
import 'types.dart';

enum MetaState { unconfigured, verified, accessError }

class MetaCallRecord {
  final String id;
  final String kind; // verify-models | extraction | rapprochement
  final String? model;
  final String status; // ok | error | refused
  final String? error;
  final int latencyMs;
  final Map<String, dynamic>? usage;
  final String at;
  final Map<String, dynamic> input; // ids + texts sent (never the key)
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

/// Official Meta Model API base (developer.meta.ai/docs/api-reference).
const String metaOfficialBaseUrl = 'https://api.meta.ai/v1';

/// Explicit label per HTTP status (error distinction required).
String metaHttpErrorLabel(int status, {String? errorType, String? errorCode}) {
  final detail = [errorType, errorCode].whereType<String>().join('/');
  final suffix = detail.isEmpty ? '' : ' ($detail)';
  return switch (status) {
    401 => 'HTTP 401 authentication refused$suffix',
    402 => 'HTTP 402 payment/billing required$suffix',
    403 => 'HTTP 403 insufficient authorization$suffix',
    404 => 'HTTP 404 resource or model not found$suffix',
    429 => 'HTTP 429 rate limit exceeded$suffix',
    >= 500 => 'HTTP $status temporary service error$suffix',
    _ => 'HTTP $status$suffix',
  };
}

class MetaConnector {
  final MetaState state;
  final List<String> models;
  final String message;
  final String? _apiKey; // server only, never serialized
  final String baseUrl;
  final String? preferredModel;
  final String? keySource; // NAME of the environment variable, never the key

  MetaConnector._(this.state, this.models, this.message,
      {String? apiKey,
      this.baseUrl = metaOfficialBaseUrl,
      this.preferredModel,
      this.keySource})
      : _apiKey = apiKey;

  /// Main variable: MODEL_API_KEY (Meta Model API documentation).
  /// Historical aliases accepted only as an explicit fallback (old
  /// Llama API deployments), never mixed: the source is kept.
  /// The key is used EXACTLY as provided, without transformation.
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

  /// State from the environment, without any network call.
  factory MetaConnector.fromEnvironment(Map<String, String> env) {
    final source = keySourceFromEnv(env);
    final key = source == null ? null : env[source];
    final base = env['CITYRESOLVE_META_BASE_URL'] ?? metaOfficialBaseUrl;
    if (key == null) {
      return MetaConnector._(MetaState.unconfigured, [],
          'Not configured: MODEL_API_KEY missing. Classic engine active.',
          baseUrl: base, preferredModel: env['CITYRESOLVE_META_MODEL']);
    }
    return MetaConnector._(MetaState.accessError, [],
        'Key present via $source but access not verified (POST /api/meta/verify required).',
        apiKey: key,
        baseUrl: base,
        preferredModel: env['CITYRESOLVE_META_MODEL'],
        keySource: source);
  }

  factory MetaConnector.error(String message) =>
      MetaConnector._(MetaState.accessError, [], message);

  MetaConnector verified(List<String> authorizedModels) => MetaConnector._(
      MetaState.verified, authorizedModels,
      'Connected and verified: ${authorizedModels.length} authorized model(s).',
      apiKey: _apiKey,
      baseUrl: baseUrl,
      preferredModel: preferredModel,
      keySource: keySource);

  String? get model =>
      preferredModel ?? (models.isEmpty ? null : models.first);

  static const List<String> capabilities = [
    'text-analysis',
    'image-analysis (vision via chat completions, base64, user messages)',
    'structured-extraction',
    'report-matching',
  ];

  /// Pure request body (testable without network): text alone or text +
  /// images. Images are placed ONLY in the `user` message
  /// (the API rejects images elsewhere with 400).
  static Map<String, dynamic> buildChatRequest({
    required String model,
    required String system,
    required String user,
    List<Map<String, String>> images = const [],
  }) {
    dynamic userContent = user;
    if (images.isNotEmpty) {
      final parts = <Map<String, dynamic>>[
        {'type': 'text', 'text': user},
      ];
      for (final img in images) {
        parts.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:${img['mime']};base64,${img['base64']}'
          },
        });
      }
      userContent = parts;
    }
    return {
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': userContent},
      ],
      'response_format': {'type': 'json_object'},
      'stream': false,
    };
  }

  Map<String, dynamic> toJson() => {
        'state': state.name,
        'models': models,
        'model': model,
        'message': message,
        'capabilities': capabilities,
        'baseUrl': baseUrl,
        'keySource': keySource,
        'integration':
            'real server connector Meta Model API (api.meta.ai), no simulated result',
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

  /// Real verification: GET /models. Fabricates no model.
  Future<(MetaConnector, MetaCallRecord)> verify(
      {Duration timeout = const Duration(seconds: 15)}) async {
    final sw = Stopwatch()..start();
    const input = {'endpoint': 'GET /models'};
    if (_apiKey == null) {
      final r = _record('verify-models', null, 'refuse',
          'MODEL_API_KEY missing', sw, input, null, null);
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
            '$label on /models', sw, input,
            {'httpStatus': resp.statusCode, 'error': envErr}, null);
        return (
          MetaConnector._(MetaState.accessError, [],
              'Meta Model API access refused: $label. Check the key in the Meta Model API dashboard.',
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
        // Real observed case: key accepted (HTTP 200) but the account
        // has access to no model. Never invent a model.
        return (
          MetaConnector._(MetaState.accessError, [],
              'Key accepted by Meta (HTTP 200) but no authorized model returned by /models for this account: AI unavailable.',
              apiKey: _apiKey, baseUrl: baseUrl, preferredModel: preferredModel, keySource: keySource),
          r
        );
      }
      return (verified(models), r);
    } catch (e) {
      sw.stop();
      final r = _record('verify-models', null, 'erreur',
          'network/timeout failure: $e', sw, input, null, null);
      return (
        MetaConnector._(MetaState.accessError, [],
            'Verification impossible: $e',
            apiKey: _apiKey, baseUrl: baseUrl, preferredModel: preferredModel, keySource: keySource),
        r
      );
    }
  }

  /// Real chat call requiring JSON output. Throws MetaException otherwise.
  Future<Map<String, dynamic>> chatJson({
    required String kind,
    required String system,
    required String user,
    required Map<String, dynamic> inputLog,
    List<Map<String, String>> images = const [],
    Duration timeout = const Duration(seconds: 60),
    void Function(MetaCallRecord)? onRecord,
  }) async {
    final sw = Stopwatch()..start();
    if (state != MetaState.verified || _apiKey == null) {
      final r = _record(kind, model, 'refuse',
          'Meta connector ${state.name}: call refused, no simulated response.',
          sw, inputLog, null, null);
      onRecord?.call(r);
      throw MetaException(r.error!, r);
    }
    final mdl = model;
    if (mdl == null) {
      final r = _record(kind, null, 'erreur',
          'No authorized model determined.', sw, inputLog, null, null);
      onRecord?.call(r);
      throw MetaException(r.error!, r);
    }
    try {
      final resp = await _request(
          'POST',
          '/chat/completions',
          buildChatRequest(
              model: mdl, system: system, user: user, images: images),
          timeout);
      final text = await utf8.decoder.bind(resp).join();
      sw.stop();
      if (resp.statusCode != 200) {
        final envErr = _errorEnvelope(text);
        final label = metaHttpErrorLabel(resp.statusCode,
            errorType: envErr?['type']?.toString(),
            errorCode: envErr?['code']?.toString());
        final r = _record(kind, mdl, 'erreur',
            '$label on /chat/completions', sw, inputLog,
            {'httpStatus': resp.statusCode, 'error': envErr}, null);
        onRecord?.call(r);
        throw MetaException(r.error!, r);
      }
      final parsed = jsonDecode(text) as Map<String, dynamic>;
      final content = _contentText(parsed);
      if (content == null) {
        final r = _record(kind, mdl, 'erreur',
            'Meta response without usable text content.', sw, inputLog,
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
      final r = _record(kind, mdl, 'erreur', 'call failed: $e', sw, inputLog,
          null, null);
      onRecord?.call(r);
      throw MetaException(r.error!, r);
    }
  }

  /// OpenAI-style error envelope of Meta Model API (no secret).
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
    // Native Llama API format: completion_message.content.text
    final cm = resp['completion_message'];
    if (cm is Map && cm['content'] is Map) {
      final t = (cm['content'] as Map)['text'];
      if (t is String) return t;
    }
    if (cm is Map && cm['content'] is String) return cm['content'] as String;
    // OpenAI-compatible format: choices[0].message.content
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

/// Structured extraction of a report (no invented certainty:
/// field absent from the text -> null + listed uncertainty).
Future<Map<String, dynamic>> extractStructuredWithMeta(
  MetaConnector c,
  Report report, {
  Duration timeout = const Duration(seconds: 30),
  void Function(MetaCallRecord)? onRecord,
}) {
  return c.chatJson(
    kind: 'extraction',
    system: 'You extract information from fictitious municipal reports. '
        'Answer ONLY in JSON. If information is missing or '
        'uncertain, set null and describe it in "incertitudes". '
        'Never invent severity, place or fact.',
    user: 'Report ${report.id} (declared category: ${report.category}): '
        '"${report.text}"\n'
        'Expected JSON: {"probleme": string, "description": string, '
        '"localisationMentionnee": string|null, '
        '"graviteExprimee": integer 1..5|null, '
        '"expositionMentionnee": string|null, '
        '"incertitudes": [string], "elementsNonVerifies": [string]}',
    inputLog: {'reportId': report.id, 'text': report.text},
    timeout: timeout,
    onRecord: onRecord,
  );
}

/// Real visual analysis of a report photo (P1, §7).
/// The model receives only the bytes + the declared context; the output
/// contract requires observations / hypotheses / uncertainties, never a
/// fabricated severity or a claimed GPS location. Any contract
/// deviation throws MetaException (no fake multimodal demo).
Future<Map<String, dynamic>> analyzeImageWithMeta(
  MetaConnector c,
  List<int> bytes, {
  required String mime,
  String? reportId,
  String? descriptionDeclaree,
  Duration timeout = const Duration(seconds: 90),
  void Function(MetaCallRecord)? onRecord,
}) async {
  final b64 = base64Encode(bytes);
  final out = await c.chatJson(
    kind: 'analyse-visuelle',
    system: 'You analyse a photo of a fictitious urban report. Describe '
        'ONLY what is visible in the image pixels, without '
        'using any outside information: you do not receive the '
        'user\'s description. You MUST distinguish: what '
        'is visible in the image, your hypotheses, and what remains '
        'to verify. Any element that is not visible goes into the uncertainties, '
        'never into the observations. Answer ONLY in JSON. '
        'Never invent severity, number of people exposed, '
        'GPS location or danger. A daytime photo never proves '
        'a night-time lighting failure.',
    user: 'Analyse this photo of a fictitious urban report.'
        '${reportId != null ? ' Report $reportId.' : ''}'
        '${descriptionDeclaree != null && descriptionDeclaree.isNotEmpty ? ' Description declared by the user (not to be confused with the visible): "$descriptionDeclaree".' : ''}\n'
        'Expected JSON: {"observationsVisibles": [string], '
        '"problemesPossibles": [{"famille": string, "hypothese": string, '
        '"confirmation": "a_verifier"}], '
        '"localisation": string|null, "gravite": integer 1..5|null, '
        '"exposition": integer 0..4|null, '
        '"incertitudes": [string]}',
    images: [
      {'mime': mime, 'base64': b64}
    ],
    inputLog: {
      'reportId': reportId,
      'mime': mime,
      'bytes': bytes.length,
      'imageInline': true,
    },
    timeout: timeout,
    onRecord: onRecord,
  );
  final flaw = validateVisualAnalysis(out);
  if (flaw != null) {
    throw MetaException(
        'Visual analysis contract not respected: $flaw.',
        MetaCallRecord(
          id: 'META-local-${DateTime.now().millisecondsSinceEpoch}',
          kind: 'analyse-visuelle',
          model: c.model,
          status: 'erreur',
          error: 'contract not respected: $flaw',
          latencyMs: 0,
          usage: null,
          at: DateTime.now().toUtc().toIso8601String(),
          input: {'reportId': reportId, 'mime': mime},
          output: out,
        ));
  }
  return out;
}

/// Meta listing with explicit units (units patch, local).
///
/// Fix for the phase4-misleading distinct-time failure, where the
/// model wrote that "the time unit was missing" and
/// merged two potholes 3 days apart: each line
/// gives t in minutes and x/y in kilometres, never a bare number, and
/// each pair shows its distance in km and its delay in minutes
/// with conversion (hours/days). The DEV retest with this listing
/// (phase4-retest-units) separates distinct-time: the model writes there
/// explicitly "delay 4320 min = 3.0 days, long delay not short".
String _fmt1(double v) => v.toStringAsFixed(1);
String _fmt2(double v) => v.toStringAsFixed(2);

String formatDelayMin(int dt) {
  if (dt >= 1440) return '$dt min = ${_fmt1(dt / 1440)} days';
  if (dt >= 60) return '$dt min = ${_fmt1(dt / 60)} hours';
  return '$dt min';
}

/// Complete listing: units header + lines + computed pairs.
String metaListingWithUnits(List<Report> reports) {
  final lines = <String>[
    'Units (given here, never assume them missing): '
        'x and y in kilometres (km) on a fictitious grid, '
        't in minutes (min) since the start of the scenario. '
        '60 min = 1 hour, 1440 min = 1 day.'
  ];
  for (final r in reports) {
    lines.add(
        '${r.id} | x=${_fmt1(r.x)} km, y=${_fmt1(r.y)} km, t=${r.t} min | category=${r.category} | "${r.text}"');
  }
  lines.add('Computed distances and delays:');
  for (var i = 0; i < reports.length; i++) {
    for (var j = i + 1; j < reports.length; j++) {
      final a = reports[i], b = reports[j];
      lines.add(
          'Pair ${a.id}-${b.id}: distance ${_fmt2(distKm(a, b))} km, delay ${formatDelayMin(dtMin(a, b))}.');
    }
  }
  return lines.join('\n');
}

/// Meta matching proposal: same Group objects as the classic
/// engine (method: meta), with the model's justification and uncertainty.
Future<List<Group>> proposeMatchingWithMeta(
  MetaConnector c,
  List<Report> reports, {
  Duration timeout = const Duration(seconds: 45),
  void Function(MetaCallRecord)? onRecord,
}) async {
  final listing = metaListingWithUnits(reports);
  final out = await c.chatJson(
    kind: 'rapprochement',
    system: 'You propose a grouping of fictitious municipal reports '
        'describing the same real incident. Answer ONLY in JSON. '
        'Each report in at most one group. If a match '
        'is doubtful, say so in "incertitude" (0=certain, 1=very doubtful) '
        'and justify it. Never invent a report. '
        'UNIT RULE, TO APPLY WITHOUT EXCEPTION: the units ARE '
        'given in the listing (x and y in kilometres, t in minutes). '
        'Never write that a unit is missing, unknown or not '
        'verifiable when the listing gives it. A delay of 4320 min is '
        '3 days, not a short delay. For a one-off incident '
        '(pothole, water leak), a delay of several days at the same '
        'place does not prove it is the same incident: two '
        'distinct incidents remain possible even with an almost '
        'identical text, and the persistence of damage does not prove '
        'identity.',
    user: 'Reports:\n$listing\n'
        'Expected JSON: {"groupes": [{"reportIds": [string], '
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
          inc >= 0.35 ? ['model uncertainty ${inc.toStringAsFixed(2)}'] : [],
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
          uncertaintyReasons: ['not classified by the model: forced singleton']));
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
  // Chain of deterministic post-model filters, in this order:
  // 1. Insufficient-content guardrail (pushed to main): even if the
  // model proposes a merge involving insufficient content —
  // exactly the phase4-hard empty-inc failure, where the model had
  // merged two empty texts with uncertainty 1.0 — the merge is
  // cancelled and each report involved becomes a singleton marked
  // 'insufficient-content-guardrail'. The cancellation is logged in
  // the returned groups themselves (reason + justification), which are
  // persisted by the server in metaGroups; the number of cancelled
  // merges is therefore verifiable group by group, without depending on
  // the model's uncertainty. A pre-filter (not sending these texts to the
  // model) was not chosen: it would hide the model's proposal
  // instead of correcting it visibly.
  // 2. Meta time gate (units patch, local): splits proposed
  // merges beyond the threshold (360 min local, 10080 min extended).
  // Each split is counted (splitGroups) and traced by a
  // 'meta-time-gate' reason. On the DEV retest, the gate had nothing
  // to split (the new listing had already fixed distinct-time),
  // but applied to the old outputs it fixes distinct-time
  // (1 split, F1 0.0 -> 1.0): it is a safety net, not the
  // cause of the new listing's gain.
  // 3. Statuses (units patch, local): flag conflicting
  // and multi-problem groups WITHOUT splitting them. A flagged merged
  // group is not a clean incident: the optimizer and
  // the human must see it as "to verify", not as a
  // validated merge. Statuses do not replace human verification,
  // especially for state contradiction (resolved vs
  // ongoing) and for the second problem of a multi-problem report.
  final filtered = applyContentGuardrail(reports, groups);
  final gated = applyMetaTimeGate(reports, filtered.groups);
  final statused = applyGroupStatuses(reports, gated.groups);
  return statused.groups;
}

/// Synchronous AI grouping kept for compatibility: always refused
/// (the real path is asynchronous, proposeMatchingWithMeta).
List<Group> groupWithMeta(MetaConnector c, List<Report> reports) {
  throw StateError(
      'Meta connector ${c.state.name}: use proposeMatchingWithMeta '
      '(asynchronous). No simulated response.');
}
