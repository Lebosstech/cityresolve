// Sécurité de l'exposition publique CityResolve (P1, §6).
//
// - RateLimiter : seaux par clé (IP), fenêtre glissante, testable.
// - MunicipalAuth : espace municipal protégé par jeton (variable
//   d'environnement CITYRESOLVE_MUNICIPAL_TOKEN). Si la variable est
//   absente, mode ouvert documenté (développement local uniquement).
// - Validation des entrées publiques : texte borné, catégorie fermée.
// - DTO publics : aucun indice interne, aucune vérité terrain, aucun
//   secret. Statuts de suivi dérivés de données réelles uniquement.
import 'dart:math';

import 'types.dart';

/// Limites publiques (documentées, serveur).
const int maxPublicTextLen = 500;
const int maxReportsTotal = 500;
const Set<String> publicCategories = {
  'nid-de-poule',
  'chaussée',
  'eclairage',
  'fuite-eau',
  'coupure-electrique',
  'arbre',
  'autre',
};

/// Limiteur de débit : au plus [max] événements par [window] et par clé.
/// Horloge injectable pour les tests.
class RateLimiter {
  final Map<String, List<DateTime>> _hits = {};
  final DateTime Function() _now;
  RateLimiter({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// true si l'événement est accepté (et compté), false si rejeté (429).
  bool allow(String key, {required int max, required Duration window}) {
    final now = _now();
    final cutoff = now.subtract(window);
    final list = (_hits[key] ?? []).where((t) => t.isAfter(cutoff)).toList();
    if (list.length >= max) {
      _hits[key] = list;
      return false;
    }
    list.add(now);
    _hits[key] = list;
    if (_hits.length > 10000) {
      _hits.remove(_hits.keys.first);
    }
    return true;
  }

  int count(String key) => _hits[key]?.length ?? 0;
}

/// Comparaison à temps quasi-constant (anti timing basique).
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Authentification de l'espace municipal. Sessions en mémoire serveur
/// (invalidées au redémarrage — assumé et documenté).
class MunicipalAuth {
  final String? expectedToken;
  final Set<String> _sessions = {};
  MunicipalAuth({this.expectedToken});

  factory MunicipalAuth.fromEnvironment(Map<String, String> env) {
    final t = env['CITYRESOLVE_MUNICIPAL_TOKEN'];
    return MunicipalAuth(
        expectedToken: (t == null || t.isEmpty) ? null : t);
  }

  /// Protection active seulement si un jeton est configuré.
  bool get enforced => expectedToken != null;

  bool checkToken(String candidate) =>
      expectedToken != null && constantTimeEquals(candidate, expectedToken!);

  String createSession() {
    final rng = Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < 32; i++) {
      sb.write(rng.nextInt(16).toRadixString(16));
    }
    final id = sb.toString();
    _sessions.add(id);
    return id;
  }

  bool checkSession(String? id) => id != null && _sessions.contains(id);

  void revoke(String? id) {
    _sessions.remove(id);
  }

  /// Autorisé si : non protégé, ou session valide, ou jeton porteur valide.
  bool isAuthorized({String? sessionId, String? bearerToken}) {
    if (!enforced) return true;
    if (checkSession(sessionId)) return true;
    if (bearerToken != null && bearerToken.isNotEmpty) {
      return checkToken(bearerToken);
    }
    return false;
  }
}

/// Erreur de validation du texte public, null si valide.
String? publicTextError(String? text) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return 'description requise';
  if (t.length > maxPublicTextLen) {
    return 'description trop longue (${t.length}/$maxPublicTextLen)';
  }
  return null;
}

bool isPublicCategory(String c) => publicCategories.contains(c);

/// Erreur de validation GPS, null si valide ou absent (saisie manuelle).
/// Les trois champs doivent être présents ensemble et dans leurs bornes.
String? publicGpsError(double? lat, double? lon, double? accuracy) {
  if (lat == null && lon == null && accuracy == null) return null;
  if (lat == null || lon == null) {
    return 'position GPS incomplète (latitude et longitude requises)';
  }
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
    return 'coordonnées GPS hors bornes';
  }
  if (accuracy != null && (accuracy.isNaN || accuracy < 0)) {
    return 'précision GPS invalide';
  }
  return null;
}

/// Statut de suivi honnête, dérivé de l'état réel uniquement :
/// enregistré (reçu, pas encore regroupé), regroupé (groupe de 2+),
/// planifié (incident dans le plan courant), escalade-s5.
/// Aucun délai ni promesse d'intervention.
String trackingStatus(
    Report r, List<Group> groups, List<Incident> incidents, Plan? plan) {
  Group? g;
  for (final gg in groups) {
    if (gg.reportIds.contains(r.id)) g = gg;
  }
  Incident? inc;
  if (g != null) {
    for (final ii in incidents) {
      if (ii.reportIds.toSet().intersection(g.reportIds.toSet()).isNotEmpty) {
        inc = ii;
        break;
      }
    }
  }
  if (inc != null && inc.severity != null && inc.severity! >= 5) {
    return 'escalade-s5';
  }
  if (plan != null &&
      inc != null &&
      plan.tasks.any((t) => t.incidentId == inc!.id)) {
    return 'planifie';
  }
  if (g != null && g.reportIds.length >= 2) return 'regroupe';
  return 'enregistre';
}

const Map<String, String> trackingLabels = {
  'enregistre': 'Enregistré',
  'regroupe': 'Regroupé',
  'planifie': 'Planifié',
  'escalade-s5': 'Escalade humaine (S5)',
};

/// Tri public stable : reçus d'abord (plus récent), identifiant
/// décroissant en départage. Scénarios (sans receivedAt) en dernier.
/// La page publique ne trie JAMAIS qu'en mémoire sur l'état de travail
/// (borné par maxReportsTotal), jamais par scan Mongo.
List<Report> sortPublicReports(List<Report> reports) {
  final out = List<Report>.from(reports);
  out.sort((a, b) {
    final ra = a.receivedAt ?? '', rb = b.receivedAt ?? '';
    if (ra.isEmpty && rb.isEmpty) return b.id.compareTo(a.id);
    if (ra.isEmpty) return 1;
    if (rb.isEmpty) return -1;
    final c = rb.compareTo(ra);
    return c != 0 ? c : b.id.compareTo(a.id);
  });
  return out;
}

class ReportPage {
  final List<Report> items;
  final String? nextCursor; // identifiant du dernier élément, null si fin
  const ReportPage(this.items, this.nextCursor);
}

/// Pagination par curseur : la page commence APRÈS le curseur (dernier
/// identifiant vu). Curseur inconnu -> page vide (pas de doublon, pas de
/// saut silencieux). Limite strictement bornée par l'appelant.
ReportPage paginatePublicReports(
    List<Report> sorted, int limit, String? cursor) {
  var start = 0;
  if (cursor != null && cursor.isNotEmpty) {
    final i = sorted.indexWhere((r) => r.id == cursor);
    if (i < 0) return const ReportPage([], null);
    start = i + 1;
  }
  if (start >= sorted.length) return const ReportPage([], null);
  final end = (start + limit).clamp(0, sorted.length);
  final items = sorted.sublist(start, end);
  return ReportPage(items, end < sorted.length ? items.last.id : null);
}

/// Filtre bbox sur coordonnées grille + limite stricte (jamais de
/// chargement complet pour la carte).
List<Incident> filterIncidentsBbox(List<Incident> incs, double minx,
    double miny, double maxx, double maxy, int limit) {
  return incs
      .where((i) =>
          i.x >= minx && i.x <= maxx && i.y >= miny && i.y <= maxy)
      .take(limit)
      .toList();
}

/// Agrégats publics calculés sur l'état en mémoire (borné) : compteurs
/// uniquement, aucune donnée individuelle, aucun scan Mongo.
Map<String, dynamic> publicStatsSummary(
    List<Report> reports, List<Group> groups, List<Incident> incidents) {
  final grouped = <String>{};
  for (final g in groups) {
    grouped.addAll(g.reportIds);
  }
  var withPhoto = 0;
  String? lastReceived;
  for (final r in reports) {
    if (r.photo != null && r.photo!.isNotEmpty) withPhoto++;
    if (r.receivedAt != null &&
        (lastReceived == null ||
            r.receivedAt!.compareTo(lastReceived) > 0)) {
      lastReceived = r.receivedAt;
    }
  }
  return {
    'reports': reports.length,
    'incidents': incidents.length,
    'groupedReports': grouped.length,
    'withPhoto': withPhoto,
    'lastReceivedAt': lastReceived,
    'fictive': true,
  };
}

/// Vue publique d'un signalement : aucun indice, aucune vérité terrain.
/// Les coordonnées GPS brutes (donnée personnelle fournie par l'usager)
/// ne sortent que sur la fiche de suivi ([includeGps]), jamais en liste.
Map<String, dynamic> publicReportJson(Report r,
        {required String status, bool includeGps = false}) =>
    {
      'id': r.id,
      'text': r.text,
      'category': r.category,
      'x': r.x,
      'y': r.y,
      't': r.t,
      'receivedAt': r.receivedAt,
      'photo': r.photo,
      'status': status,
      'statusLabel': trackingLabels[status] ?? status,
      'hasGps': r.gpsLat != null && r.gpsLon != null,
      if (includeGps && r.gpsLat != null && r.gpsLon != null)
        'gps': {
          'lat': r.gpsLat,
          'lon': r.gpsLon,
          'accuracy': r.gpsAccuracy,
        },
      'fictive': true,
    };

/// Vue publique d'un incident (carte) : centroïde, famille, gravité
/// déclarée ou inconnue, statut de vérification, effectif.
Map<String, dynamic> publicIncidentJson(Incident i) => {
      'id': i.id,
      'x': i.x,
      'y': i.y,
      'severity': i.severity,
      'severityStatus': i.severityStatus,
      'domain': i.domain,
      'reportCount': i.reportIds.length,
      'firstSeen': i.firstSeen,
      'fictive': true,
    };
