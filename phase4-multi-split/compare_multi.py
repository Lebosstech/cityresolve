#!/usr/bin/env python3
"""Comparateur deterministe phase4-multi-split (aucun appel Meta ici).

Methodes :
- classique : miroir Dart (250 m, 6 h, Jaccard >= 0,75, composantes
  connexes), SANS decoupage : un signalement reste une unite.
- synonymes : memes portes, jetons normalises par le dictionnaire
  phase4-hard, SANS decoupage.
- classique-split / synonymes-split : decoupage deterministe AVANT
  regroupement. Chaque signalement est expanse en sous-signalements,
  un par famille DEV detectee par lexique explicite. Deux
  sous-signalements ne sont groupes que s'ils partagent la MEME
  famille ET passent les portes distance (<= 250 m) et temps
  (<= 360 min). AUCUN seuil Jaccard n'est applique ici : apres
  decoupage, la famille explicite est l'appariement semantique, et
  le lieu + le temps proches sont les portes. Limite documentee :
  cette regle est plus permissive que le classique ; elle ne vaut
  que parce que la famille est explicite, pas pour du texte libre.

Metriques (regle predefinie dans data/truth.json) :
- n_incidents : nombre de groupes/incidents produits.
- survie secondaire : vrai ssi un incident methode contient le
  sous-signalement secondaire ET aucun sous-signalement d'une autre
  famille venant d'un autre signalement (un singleton secondaire
  compte comme survie).
- couverture exacte : fraction des incidents vrais reproduits
  exactement (meme ensemble de sous-signalements).
- F1 adapte : paires de sous-signalements de MEME famille, dans le
  meme incident vrai contre dans le meme incident methode. Caveat :
  ce F1 ne penalise pas a lui seul la perte d'un secondaire
  singleton ; survie et nombre d'incidents sont principaux.
Pour une methode SANS decoupage, un incident methode = un groupe de
signalements, dont les sous-signalements sont tous ceux de ses
signalements (donc un groupe [E1,E2] contient E1:eclairage).
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


def gates(a, b):
    d = math.hypot(a["x"] - b["x"], a["y"] - b["y"])
    return d <= DIST_MAX_KM and abs(a["t"] - b["t"]) <= DELTA_T_MAX_MIN


def connected_groups(items, edge):
    parent = list(range(len(items)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            if edge(items[i], items[j]):
                parent[find(i)] = find(j)
    comps = {}
    for i in range(len(items)):
        comps.setdefault(find(i), []).append(items[i])
    return sorted([sorted(c) for c in comps.values()], key=lambda c: c[0])


def report_groups(reports, synonym):
    def edge(a, b):
        return gates(a, b) and jaccard(a["text"], b["text"], synonym) >= SIM_MIN
    idx = connected_groups(list(range(len(reports))),
                           lambda i, j: edge(reports[i], reports[j]))
    return [[reports[i]["id"] for i in comp] for comp in idx]


def expand(reports, families):
    """Sous-signalements : 'ID:famille', dans l'ordre des familles du lexique."""
    units = []
    for r in reports:
        toks = tokens(r["text"])
        fams = [name for name in families if toks & set(families[name])]
        if not fams:
            fams = ["inconnu"]
        for f in fams:
            units.append({"subunit": f"{r['id']}:{f}", "report": r, "family": f})
    return units


def split_groups(reports, families):
    units = expand(reports, families)

    def edge(a, b):
        return (a["family"] == b["family"] and a["family"] != "inconnu"
                and gates(a["report"], b["report"]))
    idx = connected_groups(list(range(len(units))),
                           lambda i, j: edge(units[i], units[j]))
    return [[units[i]["subunit"] for i in comp] for comp in idx]


def subunit_set_of_report_group(group, reports, families):
    by_id = {r["id"]: r for r in reports}
    out = set()
    for rid in group:
        r = by_id[rid]
        toks = tokens(r["text"])
        fams = [name for name in families if toks & set(families[name])] or ["inconnu"]
        for f in fams:
            out.add(f"{rid}:{f}")
    return out


def pairs(incidents):
    out = set()
    for inc in incidents:
        inc = sorted(inc)
        for i in range(len(inc)):
            for j in range(i + 1, len(inc)):
                # Paires de meme famille uniquement (regle predefinie).
                if inc[i].split(":", 1)[1] == inc[j].split(":", 1)[1]:
                    out.add((inc[i], inc[j]))
    return out


def f1_score(truth_incidents, method_incidents):
    tp = len(pairs(truth_incidents) & pairs(method_incidents))
    fp = len(pairs(method_incidents) - pairs(truth_incidents))
    fn = len(pairs(truth_incidents) - pairs(method_incidents))
    prec = 1.0 if tp + fp == 0 else tp / (tp + fp)
    rec = 1.0 if tp + fn == 0 else tp / (tp + fn)
    f1 = 0.0 if prec + rec == 0 else 2 * prec * rec / (prec + rec)
    return {"tp": tp, "fp": fp, "fn": fn, "precision": prec,
            "recall": rec, "f1": f1}


def survival(method_incidents_subunits, secondary, reports, families):
    """Survie du secondaire, definition resserree AVANT tout appel Meta
    (correction apres le premier calcul deterministe) : le secondaire
    survit ssi un incident methode le contient ET ne contient AUCUN
    sous-signalement d'une autre famille, quel que soit le signalement
    d'origine. Un faisceau [E1:eclairage, E1:voirie] ne compte donc PAS
    comme survie : l'optimiseur y verrait une seule tache bundlee, pas
    une tache eclairage separable. Un singleton secondaire compte."""
    if secondary is None:
        return None
    sec_family = secondary.split(":", 1)[1]
    for inc in method_incidents_subunits:
        if secondary in inc and all(
                u.split(":", 1)[1] == sec_family for u in inc):
            return True
    return False


def evaluate(truth, reports, families, method_incidents_subunits):
    truth_incidents = truth["truth_incidents"]
    sec = truth.get("secondary_subunit")
    covered = sum(1 for t in truth_incidents
                  if sorted(t) in [sorted(m) for m in method_incidents_subunits])
    return {
        "n_incidents": len(method_incidents_subunits),
        "n_truth_incidents": len(truth_incidents),
        "secondary_survives": survival(method_incidents_subunits, sec, reports, families),
        "coverage_exact": covered,
        "coverage_fraction": covered / len(truth_incidents) if truth_incidents else 1.0,
        "f1_adapte": f1_score(truth_incidents, method_incidents_subunits),
    }


def main():
    truth_doc = json.loads((BASE / "data" / "truth.json").read_text())
    families = truth_doc["families_lexicon"]
    scenarios = json.loads((BASE / "data" / "scenarios.json").read_text())["scenarios"]
    out = {"classic_groups": {}, "synonym_groups": {},
           "classic_split_groups": {}, "synonym_split_groups": {},
           "evaluations": {}}
    for sc in scenarios:
        sid = sc["id"]
        reports = sc["reports"]
        truth = truth_doc["scenarios"][sid]
        cg = report_groups(reports, False)
        sg = report_groups(reports, True)
        csg = split_groups(reports, families)
        ssg = csg  # le decoupage deterministe ne depend pas des synonymes
        out["classic_groups"][sid] = cg
        out["synonym_groups"][sid] = sg
        out["classic_split_groups"][sid] = csg
        out["synonym_split_groups"][sid] = ssg
        # Incidents en sous-signalements pour chaque methode.
        cg_sub = [sorted(subunit_set_of_report_group(g, reports, families)) for g in cg]
        sg_sub = [sorted(subunit_set_of_report_group(g, reports, families)) for g in sg]
        out["evaluations"][sid] = {
            "classique": evaluate(truth, reports, families, cg_sub),
            "synonymes": evaluate(truth, reports, families, sg_sub),
            "classique_split": evaluate(truth, reports, families, [sorted(g) for g in csg]),
            "synonymes_split": evaluate(truth, reports, families, [sorted(g) for g in ssg]),
            "classique_incidents_subunits": cg_sub,
            "synonymes_incidents_subunits": sg_sub,
        }
    (BASE / "data" / "classic_groups.json").write_text(
        json.dumps(out["classic_groups"], indent=1, ensure_ascii=False))
    (BASE / "data" / "synonym_groups.json").write_text(
        json.dumps(out["synonym_groups"], indent=1, ensure_ascii=False))
    (BASE / "data" / "classic_split_groups.json").write_text(
        json.dumps(out["classic_split_groups"], indent=1, ensure_ascii=False))
    (BASE / "data" / "split_evaluations.json").write_text(
        json.dumps(out["evaluations"], indent=1, ensure_ascii=False))
    print(json.dumps(out["evaluations"], indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
