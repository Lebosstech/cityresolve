// Security of the CityResolve public exposure (P1, §6).
//
// - RateLimiter: buckets per key (IP), sliding window, testable.
// - MunicipalAuth: municipal area protected by token
//   (CITYRESOLVE_MUNICIPAL_TOKEN environment variable). If the variable is
//   missing, documented open mode (local development only).
// - Public input validation: bounded text, closed category.
// - Public DTOs: no internal hint, no ground truth, no
//   secret. Tracking statuses derived from real data only.
import 'dart:math';

import 'types.dart';

/// Public limits (documented, server).
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

/// Rate limiter: at most [max] events per [window] and per key.
/// Injectable clock for tests.
class RateLimiter {
  final Map<String, List<DateTime>> _hits = {};
  final DateTime Function() _now;
  RateLimiter({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// true if the event is accepted (and counted), false if rejected (429).
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

/// Near-constant-time comparison (basic anti-timing).
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Municipal area authentication. Sessions in server memory
/// (invalidated on restart — assumed and documented).
class MunicipalAuth {
  final String? expectedToken;
  final Set<String> _sessions = {};
  MunicipalAuth({this.expectedToken});

  factory MunicipalAuth.fromEnvironment(Map<String, String> env) {
    final t = env['CITYRESOLVE_MUNICIPAL_TOKEN'];
    return MunicipalAuth(
        expectedToken: (t == null || t.isEmpty) ? null : t);
  }

  /// Protection active only if a token is configured.
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

  /// Authorized if: unprotected, or valid session, or valid bearer token.
  bool isAuthorized({String? sessionId, String? bearerToken}) {
    if (!enforced) return true;
    if (checkSession(sessionId)) return true;
    if (bearerToken != null && bearerToken.isNotEmpty) {
      return checkToken(bearerToken);
    }
    return false;
  }
}

/// Public text validation error, null if valid.
String? publicTextError(String? text) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return 'description required';
  if (t.length > maxPublicTextLen) {
    return 'description too long (${t.length}/$maxPublicTextLen)';
  }
  return null;
}

bool isPublicCategory(String c) => publicCategories.contains(c);

/// GPS validation error, null if valid or absent (manual entry).
/// All three fields must be present together and within their bounds.
String? publicGpsError(double? lat, double? lon, double? accuracy) {
  if (lat == null && lon == null && accuracy == null) return null;
  if (lat == null || lon == null) {
    return 'incomplete GPS position (latitude and longitude required)';
  }
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
    return 'GPS coordinates out of bounds';
  }
  if (accuracy != null && (accuracy.isNaN || accuracy < 0)) {
    return 'invalid GPS accuracy';
  }
  return null;
}

/// Honest tracking status, derived from the real state only:
/// enregistre (received, not yet grouped), regroupe (group of 2+),
/// planifie (incident in the current plan), escalade-s5.
/// No deadline or intervention promise.
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
  'enregistre': 'Registered',
  'regroupe': 'Grouped',
  'planifie': 'Planned',
  'escalade-s5': 'Human escalation (S5)',
};

/// Stable public sort: received first (most recent), decreasing
/// identifier as tie-break. Scenarios (without receivedAt) last.
/// The public page NEVER sorts except in memory on the working state
/// (bounded by maxReportsTotal), never via a Mongo scan.
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
  final String? nextCursor; // identifier of the last item, null if end
  const ReportPage(this.items, this.nextCursor);
}

/// Cursor pagination: the page starts AFTER the cursor (last
/// identifier seen). Unknown cursor -> empty page (no duplicate, no
/// silent skip). Limit strictly bounded by the caller.
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

/// Bbox filter on grid coordinates + strict limit (never a
/// full load for the map).
List<Incident> filterIncidentsBbox(List<Incident> incs, double minx,
    double miny, double maxx, double maxy, int limit) {
  return incs
      .where((i) =>
          i.x >= minx && i.x <= maxx && i.y >= miny && i.y <= maxy)
      .take(limit)
      .toList();
}

/// Public aggregates computed on the in-memory state (bounded): counters
/// only, no individual data, no Mongo scan.
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

/// Public view of a report: no hint, no ground truth.
/// Raw GPS coordinates (personal data provided by the user)
/// only appear on the tracking details ([includeGps]), never in lists.
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

/// Public view of an incident (map): centroid, family, declared
/// or unknown severity, verification status, headcount.
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
