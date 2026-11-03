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

/// Vue publique d'un signalement : aucun indice, aucune vérité terrain.
Map<String, dynamic> publicReportJson(Report r, {required String status}) => {
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
