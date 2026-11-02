// Regroupement classique déterministe (DEV exploratoire).
//
// Règle : arête entre deux signalements ssi distance <= distMax ET
// écart temporel <= deltaTMax ET similarité Jaccard >= simMin.
// Groupes = composantes connexes (union-find), ordre déterministe.
// Confiance d'un groupe = similarité minimale de ses arêtes (0 si singleton).
import 'types.dart';

final RegExp _splitter = RegExp(r'[^a-zàâäéèêëîïôöùûüç0-9]+');

Set<String> tokens(String text) => text
    .toLowerCase()
    .split(_splitter)
    .where((w) => w.length > 2)
    .toSet();

double jaccard(String a, String b) {
  final ta = tokens(a);
  final tb = tokens(b);
  // Deux textes sans jeton : aucune évidence de similarité (pas 1,0).
  if (ta.isEmpty && tb.isEmpty) return 0.0;
  if (ta.isEmpty || tb.isEmpty) return 0.0;
  final inter = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  return inter / union;
}

double distKm(Report a, Report b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return dx * dx + dy * dy > 0 ? _sqrt(dx * dx + dy * dy) : 0.0;
}

// Racine carrée de Newton (évite dart:math pour un module pur).
double _sqrt(double v) {
  if (v <= 0) return 0.0;
  var g = v / 2.0;
  for (var i = 0; i < 30; i++) {
    g = (g + v / g) / 2.0;
  }
  return g;
}

int dtMin(Report a, Report b) => (a.t - b.t).abs();

class _UnionFind {
  final List<int> parent;
  _UnionFind(int n) : parent = List<int>.generate(n, (i) => i);
  int find(int i) {
    var r = i;
    while (parent[r] != r) {
      r = parent[r];
    }
    while (parent[i] != r) {
      final nxt = parent[i];
      parent[i] = r;
      i = nxt;
    }
    return r;
  }

  void union(int a, int b) {
    parent[find(a)] = find(b);
  }
}

/// Regroupe les signalements. Paramètres en unités SI du prototype :
/// distMaxM (mètres), deltaTMaxH (heures), simMin (Jaccard 0..1).
List<Group> groupReports(
  List<Report> reports, {
  required double distMaxM,
  required double deltaTMaxH,
  required double simMin,
}) {
  final n = reports.length;
  final uf = _UnionFind(n);
  final edgeSim = <String, double>{};
  final distMaxKm = distMaxM / 1000.0;
  final deltaTMaxMin = (deltaTMaxH * 60).round();
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final a = reports[i];
      final b = reports[j];
      if (distKm(a, b) <= distMaxKm && dtMin(a, b) <= deltaTMaxMin) {
        final s = jaccard(a.text, b.text);
        if (s >= simMin) {
          uf.union(i, j);
          edgeSim['$i|$j'] = s;
        }
      }
    }
  }
  final comps = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    comps.putIfAbsent(uf.find(i), () => []).add(i);
  }
  // Ordre déterministe : tri par plus petit id de signalement.
  final ordered = comps.values.toList()
    ..sort((a, b) => reports[a.first].id.compareTo(reports[b.first].id));
  final groups = <Group>[];
  var gi = 0;
  for (final comp in ordered) {
    comp.sort((a, b) => reports[a].id.compareTo(reports[b].id));
    double conf = 0.0;
    if (comp.length > 1) {
      conf = 1.0;
      for (var x = 0; x < comp.length; x++) {
        for (var y = x + 1; y < comp.length; y++) {
          final key = comp[x] < comp[y]
              ? '${comp[x]}|${comp[y]}'
              : '${comp[y]}|${comp[x]}';
          final s = edgeSim[key];
          if (s != null && s < conf) conf = s;
        }
      }
    }
    // Incertitude du regroupement : signalée, jamais masquée.
    final reasons = <String>[];
    if (comp.length > 1) {
      if (conf <= simMin + 0.10) {
        reasons.add(
            'similarité minimale ${conf.toStringAsFixed(2)} proche du seuil $simMin');
      }
      // Chaînage transitif : paire interne sans arête directe.
      for (var x = 0; x < comp.length && reasons.length < 4; x++) {
        for (var y = x + 1; y < comp.length; y++) {
          final key = comp[x] < comp[y]
              ? '${comp[x]}|${comp[y]}'
              : '${comp[y]}|${comp[x]}';
          if (!edgeSim.containsKey(key)) {
            reasons.add(
                'chaînage transitif : ${reports[comp[x]].id}-${reports[comp[y]].id} sans arête directe');
            break;
          }
        }
      }
      final sevHints =
          comp.map((i) => reports[i].severityHint).whereType<int>().toList();
      if (sevHints.isNotEmpty &&
          sevHints.reduce((a, b) => a > b ? a : b) -
                  sevHints.reduce((a, b) => a < b ? a : b) >=
              2) {
        reasons.add('gravités déclarées contradictoires dans le groupe');
      }
    }
    gi++;
    groups.add(Group(
      id: 'G$gi',
      reportIds: comp.map((i) => reports[i].id).toList(),
      confidence: comp.length > 1 ? conf : 0.0,
      singleton: comp.length == 1,
      uncertain: reasons.isNotEmpty,
      uncertaintyReasons: reasons,
    ));
  }
  return groups;
}

/// Paires NON regroupées mais ambiguës (presque-fusions / séparations
/// douteuses). Permet de signaler une séparation incertaine au lieu de
/// l'imposer en silence (cas E2 : même lieu/instant, vocabulaire disjoint).
List<Map<String, dynamic>> ambiguousPairs(
  List<Report> reports,
  List<Group> groups, {
  required double distMaxM,
  required double deltaTMaxH,
  required double simMin,
}) {
  final groupOf = <String, String>{};
  for (final g in groups) {
    for (final id in g.reportIds) {
      groupOf[id] = g.id;
    }
  }
  final out = <Map<String, dynamic>>[];
  final distMaxKm = distMaxM / 1000.0;
  final deltaTMaxMin = (deltaTMaxH * 60).round();
  for (var i = 0; i < reports.length; i++) {
    for (var j = i + 1; j < reports.length; j++) {
      final a = reports[i], b = reports[j];
      if (groupOf[a.id] == groupOf[b.id]) continue;
      final dKm = distKm(a, b);
      final dt = dtMin(a, b);
      final s = jaccard(a.text, b.text);
      String? reason;
      if (dKm <= distMaxKm && dt <= deltaTMaxMin && s < simMin) {
        reason =
            'proximité spatio-temporelle mais vocabulaire insuffisant (Jaccard ${s.toStringAsFixed(2)} < $simMin) : séparation incertaine';
      } else if (s >= simMin && dKm > distMaxKm && dKm <= distMaxKm * 2) {
        reason =
            'texte similaire mais distance ${(dKm * 1000).round()} m au-delà du seuil ${distMaxM.round()} m : séparation incertaine';
      } else if (s >= simMin && dt <= deltaTMaxMin && dKm > distMaxKm * 2) {
        // E4 (patch local, non poussé) : même texte, très loin. Ne pas
        // fusionner de force (deux incidents réels peuvent partager un
        // texte), mais ne pas séparer en silence : signaler le doublon
        // distant à vérifier par un humain.
        reason =
            'texte similaire (Jaccard ${s.toStringAsFixed(2)}) mais distance ${(dKm * 1000).round()} m, bien au-delà du seuil ${distMaxM.round()} m : séparation incertaine, doublon distant à vérifier, non fusionné';
      }
      if (reason != null) {
        out.add({
          'a': a.id,
          'b': b.id,
          'sim': s,
          'distM': (dKm * 1000).round(),
          'dtMin': dt,
          'reason': reason,
        });
      }
    }
  }
  return out;
}
