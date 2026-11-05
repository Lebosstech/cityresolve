// Metrics: grouping F1, Q, reviews (verifiable computations).
import 'policy.dart';

class Prf {
  final int tp, fp, fn;
  const Prf(this.tp, this.fp, this.fn);
  double get precision =>
      tp + fp == 0 ? 1.0 : tp / (tp + fp).toDouble();
  double get recall => tp + fn == 0 ? 1.0 : tp / (tp + fn).toDouble();
  double get f1 {
    final p = precision, r = recall;
    return p + r == 0 ? 0.0 : 2 * p * r / (p + r);
  }

  Map<String, dynamic> toJson() => {
        'tp': tp,
        'fp': fp,
        'fn': fn,
        'precision': precision,
        'recall': recall,
        'f1': f1,
      };
}

/// Pairwise F1. truth: true groups (id lists). pred: predicted groups.
/// abstained: abstaining reports scored as singletons.
Prf pairwiseF1(
  List<Set<String>> truth,
  List<List<String>> pred, {
  Set<String> abstained = const {},
}) {
  final trueOf = <String, int>{};
  for (var i = 0; i < truth.length; i++) {
    for (final id in truth[i]) {
      trueOf[id] = i;
    }
  }
  final predOf = <String, int>{};
  var singletonSeq = 0;
  for (var i = 0; i < pred.length; i++) {
    for (final id in pred[i]) {
      if (abstained.contains(id)) {
        singletonSeq++;
        predOf[id] = 1000000 + singletonSeq; // deterministic singleton
      } else {
        predOf[id] = i;
      }
    }
  }
  final ids = {...trueOf.keys, ...predOf.keys}.toList()..sort();
  var tp = 0, fp = 0, fn = 0;
  for (var i = 0; i < ids.length; i++) {
    for (var j = i + 1; j < ids.length; j++) {
      final a = ids[i], b = ids[j];
      final t = trueOf[a] != null &&
          trueOf[b] != null &&
          trueOf[a] == trueOf[b];
      final p = predOf[a] != null &&
          predOf[b] != null &&
          predOf[a] == predOf[b];
      if (t && p) {
        tp++;
      } else if (!t && p) {
        fp++;
      } else if (t && !p) {
        fn++;
      }
    }
  }
  return Prf(tp, fp, fn);
}

Prf microF1(List<Prf> parts) {
  var tp = 0, fp = 0, fn = 0;
  for (final p in parts) {
    tp += p.tp;
    fp += p.fp;
    fn += p.fn;
  }
  return Prf(tp, fp, fn);
}

double macroF1(List<Prf> parts) {
  if (parts.isEmpty) return 1.0;
  var s = 0.0;
  for (final p in parts) {
    s += p.f1;
  }
  return s / parts.length;
}

/// B-cubed F1 (balanced per report).
double bCubedF1(
    Map<String, int> trueOf, Map<String, int> predOf) {
  if (trueOf.isEmpty) return 1.0;
  final trueGroups = <int, Set<String>>{};
  final predGroups = <int, Set<String>>{};
  trueOf.forEach((id, g) =>
      trueGroups.putIfAbsent(g, () => <String>{}).add(id));
  predOf.forEach((id, g) =>
      predGroups.putIfAbsent(g, () => <String>{}).add(id));
  var sp = 0.0, sr = 0.0;
  trueOf.forEach((id, g) {
    final t = trueGroups[g]!;
    final p = predGroups[predOf[id]] ?? {id};
    final inter = t.intersection(p).length.toDouble();
    sp += inter / p.length.toDouble();
    sr += inter / t.length.toDouble();
  });
  final mp = sp / trueOf.length;
  final mr = sr / trueOf.length;
  return mp + mr == 0 ? 0.0 : 2 * mp * mr / (mp + mr);
}

/// Q score: 100 * Σ(completed w) / Σ(S1..S4 w). null if no S1..S4.
double? qScore(Map<String, double> weights, Set<String> completed) {
  var num = 0.0, den = 0.0;
  weights.forEach((id, w) {
    den += w;
    if (completed.contains(id)) num += w;
  });
  if (den == 0) return null;
  return 100.0 * num / den;
}

class RevisionCounts {
  int tp = 0, fp = 0, fn = 0, tn = 0;
  double get recallNecessary =>
      tp + fn == 0 ? 1.0 : tp / (tp + fn).toDouble();
  double get fpRate => fp + tn == 0 ? 0.0 : fp / (fp + tn).toDouble();
  Map<String, dynamic> toJson() => {
        'tp': tp,
        'fp': fp,
        'fn': fn,
        'tn': tn,
        'recallNecessary': recallNecessary,
        'fpRate': fpRate,
      };
}

/// Envelope: every review is measured on the TRUE visible DEV groups.
String metricNote() =>
    'Metrics computed on visible fictitious DEV scenarios. '
    'No scientific proof. Q policy ${qWeightSeverity}/${qWeightExposure} (provisional).';
