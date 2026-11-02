#!/usr/bin/env python3
"""Comparateur phase4-retest-units : CLASSIQUE + SYNONYMES (miroir phase4-misleading).

Regles identiques a phase4-misleading/compare_misleading.py (sans le modifier) :
jetons minuscules, decoupe [^a-z accentues 0-9]+, longueur > 2, Jaccard,
arete si distance <= 250 m ET ecart <= 6 h ET Jaccard >= 0,75,
groupes = composantes connexes. Dictionnaire synonymes identique.
Aucune cle lue ici. Aucun appel Meta ici. F1 par paires NON ordonnees.
Ecrit data/classic_groups.json, data/synonym_groups.json et
data/classic_synonym_results.json (groupes + F1, pour comparaison).
"""
import json
import math
import re
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


def groups_for(reports, synonym, method):
    n = len(reports)
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(a, b):
        parent[find(a)] = find(b)

    for i in range(n):
        for j in range(i + 1, n):
            a, b = reports[i], reports[j]
            d = math.hypot(a["x"] - b["x"], a["y"] - b["y"])
            if d <= DIST_MAX_KM and abs(a["t"] - b["t"]) <= DELTA_T_MAX_MIN:
                if jaccard(a["text"], b["text"], synonym) >= SIM_MIN:
                    union(i, j)
    comps = {}
    for i in range(n):
        comps.setdefault(find(i), []).append(i)
    groups = []
    for comp in sorted(comps.values(), key=lambda c: reports[c[0]]["id"]):
        comp = sorted(comp, key=lambda i: reports[i]["id"])
        groups.append({"id": f"G{len(groups) + 1}",
                       "reportIds": [reports[i]["id"] for i in comp],
                       "singleton": len(comp) == 1, "method": method,
                       "uncertain": False, "uncertaintyReasons": []})
    return groups


def pairs(groups):
    out = set()
    for g in groups:
        ids = sorted(g["reportIds"])
        for i in range(len(ids)):
            for j in range(i + 1, len(ids)):
                out.add((ids[i], ids[j]))
    return out


def f1(pred_groups, truth_groups):
    pred = pairs(pred_groups)
    truth = pairs([{"reportIds": g} for g in truth_groups])
    tp = len(pred & truth)
    fp = len(pred - truth)
    fn = len(truth - pred)
    prec = tp / (tp + fp) if tp + fp else 1.0
    rec = tp / (tp + fn) if tp + fn else 1.0
    f = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
    return {"tp": tp, "fp": fp, "fn": fn, "precision": prec,
            "recall": rec, "f1": f}


def main():
    data = json.loads((BASE / "data" / "scenarios.json").read_text())
    truth = json.loads((BASE / "data" / "truth.json").read_text())["scenarios"]
    classic, synonym = {}, {}
    results = {}
    for sc in data["scenarios"]:
        sid = sc["id"]
        cg = groups_for(sc["reports"], False, "classique")
        sg = groups_for(sc["reports"], True, "synonymes")
        classic[sid] = cg
        synonym[sid] = sg
        tg = truth[sid]["truth_groups"]
        results[sid] = {"classique": {"groups": [g["reportIds"] for g in cg],
                                      "f1": f1(cg, tg)},
                        "synonymes": {"groups": [g["reportIds"] for g in sg],
                                      "f1": f1(sg, tg)}}
        print(sid, "classique", results[sid]["classique"]["f1"]["f1"],
              [g["reportIds"] for g in cg], "| synonymes",
              results[sid]["synonymes"]["f1"]["f1"],
              [g["reportIds"] for g in sg])
    (BASE / "data" / "classic_groups.json").write_text(
        json.dumps(classic, indent=2, ensure_ascii=False))
    (BASE / "data" / "synonym_groups.json").write_text(
        json.dumps(synonym, indent=2, ensure_ascii=False))
    (BASE / "data" / "classic_synonym_results.json").write_text(
        json.dumps(results, indent=2, ensure_ascii=False))
    print("OK classique/synonymes ecrits.")


if __name__ == "__main__":
    main()
