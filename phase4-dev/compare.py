#!/usr/bin/env python3
"""Comparateur Phase 4 DEV : CLASSIQUE (miroir Dart) contre META (JSON).

Regles classiques, copie fidele de lib/grouping.dart :
- jetons : minuscules, decoupe sur [^a-z a accentues 0-9]+, longueur > 2
- Jaccard, textes sans jeton = 0.0
- arete si distance <= 250 m ET ecart <= 6 h ET Jaccard >= 0.75
- groupes = composantes connexes, ordre par plus petit id de signalement
- confiance = similarite minimale des aretes du groupe, 0 si singleton
- incertain si confiance <= 0.85, chainage transitif, ou ecart gravite >= 2
- paires ambigues, y compris le signal patch : texte similaire,
  temps proche, distance > 2 x 250 m = doublon distant a verifier, NON fusionne

F1 par paires, copie fidele de lib/metrics.dart pairwiseF1.
Aucune donnee DEV n'est modifiee pour reussir. Aucune cle n'est lue ici.
"""
import json
import math
import re
import sys
from pathlib import Path

BASE = Path(__file__).parent
DIST_MAX_M = 250.0
DELTA_T_MAX_H = 6.0
SIM_MIN = 0.75

SPLITTER = re.compile(r"[^a-zàâäéèêëîïôöùûüç0-9]+")


def tokens(text):
    return {
        w
        for w in SPLITTER.split(text.lower())
        if len(w) > 2
    }


def jaccard(a, b):
    ta, tb = tokens(a), tokens(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def dist_km(a, b):
    return math.hypot(a["x"] - b["x"], a["y"] - b["y"])


def classic_groups(reports):
    n = len(reports)
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(a, b):
        parent[find(a)] = find(b)

    edge_sim = {}
    dist_max_km = DIST_MAX_M / 1000.0
    delta_t_max_min = round(DELTA_T_MAX_H * 60)
    for i in range(n):
        for j in range(i + 1, n):
            a, b = reports[i], reports[j]
            if dist_km(a, b) <= dist_max_km and abs(a["t"] - b["t"]) <= delta_t_max_min:
                s = jaccard(a["text"], b["text"])
                if s >= SIM_MIN:
                    union(i, j)
                    edge_sim[f"{i}|{j}"] = s
    comps = {}
    for i in range(n):
        comps.setdefault(find(i), []).append(i)
    ordered = sorted(comps.values(), key=lambda c: reports[c[0]]["id"])
    groups = []
    for gi, comp in enumerate(ordered, start=1):
        comp = sorted(comp, key=lambda i: reports[i]["id"])
        conf = 0.0
        if len(comp) > 1:
            conf = 1.0
            for x in range(len(comp)):
                for y in range(x + 1, len(comp)):
                    key = f"{min(comp[x], comp[y])}|{max(comp[x], comp[y])}"
                    if key in edge_sim and edge_sim[key] < conf:
                        conf = edge_sim[key]
        reasons = []
        if len(comp) > 1:
            if conf <= SIM_MIN + 0.10:
                reasons.append(
                    f"similarité minimale {conf:.2f} proche du seuil {SIM_MIN}"
                )
            for x in range(len(comp)):
                for y in range(x + 1, len(comp)):
                    key = f"{min(comp[x], comp[y])}|{max(comp[x], comp[y])}"
                    if key not in edge_sim:
                        reasons.append(
                            f"chaînage transitif : "
                            f"{reports[comp[x]]['id']}-{reports[comp[y]]['id']} "
                            "sans arête directe"
                        )
                        break
                if reasons and "chaînage" in reasons[-1]:
                    break
            hints = [reports[i]["severityHint"] for i in comp
                     if reports[i].get("severityHint") is not None]
            if hints and max(hints) - min(hints) >= 2:
                reasons.append("gravités déclarées contradictoires dans le groupe")
        groups.append({
            "id": f"G{gi}",
            "reportIds": [reports[i]["id"] for i in comp],
            "confidence": conf,
            "singleton": len(comp) == 1,
            "method": "classique",
            "uncertain": bool(reasons),
            "uncertaintyReasons": reasons,
            "justification": None,
        })
    return groups


def ambiguous_pairs(reports, groups):
    group_of = {}
    for g in groups:
        for rid in g["reportIds"]:
            group_of[rid] = g["id"]
    out = []
    dist_max_km = DIST_MAX_M / 1000.0
    delta_t_max_min = round(DELTA_T_MAX_H * 60)
    for i in range(len(reports)):
        for j in range(i + 1, len(reports)):
            a, b = reports[i], reports[j]
            if group_of[a["id"]] == group_of[b["id"]]:
                continue
            d_km = dist_km(a, b)
            dt = abs(a["t"] - b["t"])
            s = jaccard(a["text"], b["text"])
            reason = None
            if d_km <= dist_max_km and dt <= delta_t_max_min and s < SIM_MIN:
                reason = (
                    f"proximité spatio-temporelle mais vocabulaire insuffisant "
                    f"(Jaccard {s:.2f} < {SIM_MIN}) : séparation incertaine"
                )
            elif s >= SIM_MIN and dist_max_km < d_km <= dist_max_km * 2:
                reason = (
                    f"texte similaire mais distance {round(d_km * 1000)} m "
                    f"au-delà du seuil {round(DIST_MAX_M)} m : séparation incertaine"
                )
            elif s >= SIM_MIN and dt <= delta_t_max_min and d_km > dist_max_km * 2:
                reason = (
                    f"texte similaire (Jaccard {s:.2f}) mais distance "
                    f"{round(d_km * 1000)} m, bien au-delà du seuil "
                    f"{round(DIST_MAX_M)} m : séparation incertaine, "
                    "doublon distant à vérifier, non fusionné"
                )
            if reason:
                out.append({"a": a["id"], "b": b["id"], "sim": s,
                            "distM": round(d_km * 1000), "dtMin": dt,
                            "reason": reason})
    return out


def pairwise_f1(truth_groups, pred_groups):
    if truth_groups is None:
        return None
    true_of = {}
    for i, g in enumerate(truth_groups):
        for rid in g:
            true_of[rid] = i
    pred_of = {}
    for i, g in enumerate(pred_groups):
        for rid in g:
            pred_of[rid] = i
    ids = sorted(set(true_of) | set(pred_of))
    tp = fp = fn = 0
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            a, b = ids[i], ids[j]
            t = true_of.get(a) is not None and true_of.get(a) == true_of.get(b)
            p = pred_of.get(a) is not None and pred_of.get(a) == pred_of[b]
            if t and p:
                tp += 1
            elif not t and p:
                fp += 1
            elif t and not p:
                fn += 1
    precision = 1.0 if tp + fp == 0 else tp / (tp + fp)
    recall = 1.0 if tp + fn == 0 else tp / (tp + fn)
    f1 = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)
    return {"tp": tp, "fp": fp, "fn": fn,
            "precision": precision, "recall": recall, "f1": f1}


def pair_disagreements(truth_groups, classic, meta):
    """Paires ou CLASSIQUE et META divergent, avec le statut vrai si connu.
    Les paires sont NON ordonnees (tuple trie) : l'ordre des groupes
    ne doit jamais creer de faux desaccords."""
    import itertools
    def pair_map(groups):
        m = {}
        ids = sorted(r for g in groups for r in g)
        for a, b in itertools.combinations(ids, 2):
            m[(a, b)] = any(a in g and b in g for g in groups)
        return m

    cm, mm = pair_map(classic), pair_map(meta)
    true_map = None
    if truth_groups is not None:
        true_map = pair_map(truth_groups)
    out = []
    for pair in sorted(set(cm) | set(mm)):
        if cm.get(pair) != mm.get(pair):
            out.append({
                "pair": list(pair),
                "classique_fusionne": bool(cm.get(pair)),
                "meta_fusionne": bool(mm.get(pair)),
                "vrai_fusionne": None if true_map is None else bool(true_map.get(pair)),
            })
    return out


def main():
    scenarios = json.loads((BASE / "data" / "scenarios.json").read_text())["scenarios"]
    classic = {}
    results = []
    for sc in scenarios:
        groups = classic_groups(sc["reports"])
        classic[sc["id"]] = groups
        results.append({
            "scenario": sc["id"],
            "method": "classique",
            "groups": [g["reportIds"] for g in groups],
            "groups_detail": groups,
            "ambiguous": ambiguous_pairs(sc["reports"], groups),
            "f1": pairwise_f1(sc["truth_groups"],
                               [g["reportIds"] for g in groups]),
        })
    (BASE / "data" / "classic_groups.json").write_text(
        json.dumps(classic, indent=2, ensure_ascii=False))
    (BASE / "data" / "classic_results.json").write_text(
        json.dumps(results, indent=2, ensure_ascii=False))
    for r in results:
        print(r["scenario"], "classique groups=", r["groups"],
              "F1=", None if r["f1"] is None else round(r["f1"]["f1"], 4),
              "ambiguous=", len(r["ambiguous"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
