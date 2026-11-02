#!/usr/bin/env python3
"""Calcule final_f1.json pour phase4-multi-split (aucun appel Meta).

Methodes : classique, synonymes (depuis split_evaluations.json),
classique_split / synonymes_split (idem), meta_nosplit et meta_split
(depuis meta_groups.json / meta_split_groups.json, groupes de
signalements convertis en sous-signalements par le lexique DEV, et
groupes de sous-signalements utilises tels quels).
Regle de comptage : voir data/truth.json (survie = incident de
famille pure contenant le secondaire).
"""
import json
import sys
from pathlib import Path

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from compare_multi import (evaluate, subunit_set_of_report_group)  # noqa: E402


def main():
    truth_doc = json.loads((BASE / "data" / "truth.json").read_text())
    families = truth_doc["families_lexicon"]
    scenarios = json.loads((BASE / "data" / "scenarios.json").read_text())["scenarios"]
    det = json.loads((BASE / "data" / "split_evaluations.json").read_text())
    meta_nosplit = json.loads((BASE / "data" / "meta_groups.json").read_text())
    meta_split = json.loads((BASE / "data" / "meta_split_groups.json").read_text())
    out = {}
    for sc in scenarios:
        sid = sc["id"]
        reports = sc["reports"]
        truth = truth_doc["scenarios"][sid]
        entry = {"truth_incidents": truth["truth_incidents"],
                 "secondary_subunit": truth.get("secondary_subunit")}
        for key in ("classique", "synonymes", "classique_split", "synonymes_split"):
            ev = det[sid][key]
            entry[key] = {k: ev[k] for k in
                          ("n_incidents", "secondary_survives",
                           "coverage_exact", "coverage_fraction", "f1_adapte")}
        # Meta sans decoupage : groupes de signalements -> sous-signalements.
        mn = meta_nosplit[sid]
        if "error" in mn:
            entry["meta_nosplit"] = {"error": mn["error"]}
        else:
            groups = [g["ids"] for g in mn["groups"]]
            subs = [sorted(subunit_set_of_report_group(g, reports, families))
                    for g in groups]
            entry["meta_nosplit"] = evaluate(truth, reports, families, subs)
            entry["meta_nosplit"]["groups"] = groups
            entry["meta_nosplit"]["incidents_subunits"] = subs
        # Meta avec decoupage : groupes de sous-signalements tels quels.
        ms = meta_split[sid]
        if "error" in ms:
            entry["meta_split"] = {"error": ms["error"]}
        else:
            subs = [sorted(g["ids"]) for g in ms["groups"]]
            entry["meta_split"] = evaluate(truth, reports, families, subs)
            entry["meta_split"]["groups"] = subs
        out[sid] = entry
    (BASE / "data" / "final_f1.json").write_text(
        json.dumps(out, indent=1, ensure_ascii=False))
    for sid, entry in out.items():
        row = {}
        for k in ("classique", "synonymes", "classique_split",
                  "meta_nosplit", "meta_split"):
            ev = entry[k]
            row[k] = (ev["n_incidents"], ev["secondary_survives"],
                      ev["coverage_fraction"], ev["f1_adapte"]["f1"]) \
                if "n_incidents" in ev else ev
        print(sid, row)


if __name__ == "__main__":
    main()
