#!/usr/bin/env python3
"""Comparateur phase4-misleading : CLASSIQUE (miroir Dart) + BASELINE SYNONYMES.

Regles reprises exactement de phase4-hard/compare_hard.py (sans le modifier) :
- jetons minuscules, decoupe [^a-z accentues 0-9]+, longueur > 2
- Jaccard, texte sans jeton = 0.0
- arete si distance <= 250 m ET ecart <= 6 h ET Jaccard >= 0,75
- groupes = composantes connexes
- portes passantes si coordonnees/temps absents (aucun null ici, regle conservee pour fidelite)
Baseline synonymes : meme dictionnaire francais limite au vocabulaire urbain
de phase4-hard, sans pretention de couverture generale.
Aucune cle n'est lue ici. Aucun appel Meta ici.
F1 par paires NON ordonnees.
"""
import json, math, re
from pathlib import Path
BASE = Path(__file__).parent
DIST_MAX_KM = 0.25
DELTA_T_MAX_MIN = 360
SIM_MIN = 0.75
SPLITTER = re.compile(r"[^a-zàâäéèêëîïôöùûüç0-9]+")
SYNONYMS = {
    "panne": "panne", "coupure": "panne",
    "courant": "courant", "electricite": "courant", "electrique": "courant",
    "fuite": "fuite", "ecoulement": "fuite",
    "canalisation": "canalisation", "conduite": "canalisation",
    "inonde": "inonde", "mouille": "inonde",
    "nid": "niddepoule", "poule": "niddepoule", "trou": "niddepoule",
    "abimee": "degrade", "degradee": "degrade", "degrade": "degrade",
    "reverbere": "luminaire", "lampadaire": "luminaire", "eclairage": "luminaire",
    "eteint": "defaillant", "defaillant": "defaillant",
}
def tokens(text, synonym=False):
    toks = {w for w in SPLITTER.split(text.lower()) if len(w) > 2}
    if synonym:
        toks = {SYNONYMS.get(w, w) for w in toks}
    return toks
def jaccard(a, b, synonym=False):
    ta, tb = tokens(a, synonym), tokens(b, synonym)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)
def gates(a, b):
    reasons = []
    if a["x"] is None or b["x"] is None or a["y"] is None or b["y"] is None:
        dist_ok = True; reasons.append("coordonnees manquantes : porte distance passante, sans lieu invente")
    else:
        dist_ok = math.hypot(a["x"] - b["x"], a["y"] - b["y"]) <= DIST_MAX_KM
    if a["t"] is None or b["t"] is None:
        time_ok = True; reasons.append("temps manquant : porte temps passante, sans temps invente")
    else:
        time_ok = abs(a["t"] - b["t"]) <= DELTA_T_MAX_MIN
    return dist_ok, time_ok, reasons
def groups_for(reports, synonym, method):
    n = len(reports); parent = list(range(n))
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]; i = parent[i]
        return i
    def union(a, b): parent[find(a)] = find(b)
    edge_sim = {}; missing_reasons = {}
    for i in range(n):
        for j in range(i + 1, n):
            a, b = reports[i], reports[j]
            dist_ok, time_ok, reasons = gates(a, b)
            if reasons:
                missing_reasons.setdefault(i, []).extend(reasons); missing_reasons.setdefault(j, []).extend(reasons)
            if dist_ok and time_ok:
                s = jaccard(a["text"], b["text"], synonym)
                if s >= SIM_MIN:
                    union(i, j); edge_sim[f"{i}|{j}"] = s
    comps = {}
    for i in range(n): comps.setdefault(find(i), []).append(i)
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
                    if key in edge_sim and edge_sim[key] < conf: conf = edge_sim[key]
        reasons = []
        for i in comp:
            for r in missing_reasons.get(i, []):
                if r not in reasons: reasons.append(r)
        groups.append({"id": f"G{gi}", "reportIds": [reports[i]["id"] for i in comp],
                       "confidence": conf, "singleton": len(comp) == 1, "method": method,
                       "uncertain": bool(reasons), "uncertaintyReasons": reasons, "justification": None})
    return groups
def pairwise_f1(truth_groups, pred_groups):
    true_of = {}; pred_of = {}
    for i, g in enumerate(truth_groups):
        for rid in g: true_of[rid] = i
    for i, g in enumerate(pred_groups):
        for rid in g: pred_of[rid] = i
    ids = sorted(set(true_of) | set(pred_of)); tp = fp = fn = 0
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            a, b = ids[i], ids[j]
            t = true_of.get(a) is not None and true_of.get(a) == true_of.get(b)
            p = pred_of.get(a) is not None and pred_of.get(a) == pred_of[b]
            if t and p: tp += 1
            elif not t and p: fp += 1
            elif t and not p: fn += 1
    precision = 1.0 if tp + fp == 0 else tp / (tp + fp)
    recall = 1.0 if tp + fn == 0 else tp / (tp + fn)
    f1 = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)
    return {"tp": tp, "fp": fp, "fn": fn, "precision": precision, "recall": recall, "f1": f1}
def main():
    scenarios = json.loads((BASE / "data" / "scenarios.json").read_text())["scenarios"]
    classic, synonym, results = {}, {}, []
    for sc in scenarios:
        cg = groups_for(sc["reports"], False, "classique")
        sg = groups_for(sc["reports"], True, "synonymes")
        classic[sc["id"]] = cg; synonym[sc["id"]] = sg
        results.append({"scenario": sc["id"],
            "classique": {"groups": [g["reportIds"] for g in cg], "f1": pairwise_f1(sc["truth_groups"], [g["reportIds"] for g in cg]), "detail": cg},
            "synonymes": {"groups": [g["reportIds"] for g in sg], "f1": pairwise_f1(sc["truth_groups"], [g["reportIds"] for g in sg]), "detail": sg}})
        print(sc["id"], "classique=", results[-1]["classique"]["groups"], "F1=", round(results[-1]["classique"]["f1"]["f1"], 4),
              "| synonymes=", results[-1]["synonymes"]["groups"], "F1=", round(results[-1]["synonymes"]["f1"]["f1"], 4))
    (BASE / "data" / "classic_groups.json").write_text(json.dumps(classic, indent=2, ensure_ascii=False))
    (BASE / "data" / "synonym_groups.json").write_text(json.dumps(synonym, indent=2, ensure_ascii=False))
    (BASE / "data" / "classic_synonym_results.json").write_text(json.dumps(results, indent=2, ensure_ascii=False))
    return 0
if __name__ == "__main__":
    raise SystemExit(main())
