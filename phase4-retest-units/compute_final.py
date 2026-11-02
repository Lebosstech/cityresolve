#!/usr/bin/env python3
"""Calcul final phase4-retest-units : F1 par etage, sans nouvel appel Meta.

Etages Meta (nouveau listing) :
- meta_raw : sortie modele brute (nouveau listing, sans post-filtre)
- meta_gate : meta_raw + porte temps post-modele (decoupages comptes)
- meta_flag : meta_raw + statuts (contradictoire / multi-probleme), groupes inchanges
- meta_full : meta_raw + porte temps + statuts
Ancien listing (phase4-misleading, relu, non modifie) : F1 par scenario
repris de data/final_f1.json d'origine, pour le tableau avant/apres.
Aussi : effet des statuts sur les groupes de verite (ce que les statuts
auraient signale si la fusion de verite avait eu lieu) et sur les
groupes classiques/synonymes (statuts appliques apres coup).
F1 par paires NON ordonnees. Aucune cle lue ici.
"""
import json
import sys
from pathlib import Path

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from mechanisms import apply_statuses, apply_time_gate  # noqa: E402
from compare_retest import f1  # noqa: E402

OLD = Path.home() / "workspace" / "cityresolve" / "phase4-misleading" / "data" / "final_f1.json"


def clean_vs_flagged(groups):
    merged = [g for g in groups if len(g["reportIds"]) > 1]
    flagged = [g for g in merged if g.get("contradictoire") or g.get("multiProbleme")]
    return {"merged_total": len(merged), "merged_clean": len(merged) - len(flagged),
            "merged_flagged": len(flagged)}


def main():
    scenarios = {s["id"]: s for s in json.loads((BASE / "data" / "scenarios.json").read_text())["scenarios"]}
    truth = json.loads((BASE / "data" / "truth.json").read_text())["scenarios"]
    old = json.loads(OLD.read_text())
    old_meta = {e["scenario"]: e["meta"]["f1"]["f1"] for e in old["per_scenario"]}
    old_meta_groups = {e["scenario"]: e["meta"]["groups"] for e in old["per_scenario"]}
    meta_raw = json.loads((BASE / "data" / "meta_groups.json").read_text())
    classic = json.loads((BASE / "data" / "classic_groups.json").read_text())
    synonym = json.loads((BASE / "data" / "synonym_groups.json").read_text())
    out = {"per_scenario": [], "stages": {}, "status_on_truth": {},
           "status_on_classic_synonym": {}}
    for sid, sc in scenarios.items():
        tg = truth[sid]["truth_groups"]
        raw = meta_raw[sid]
        gated, n_split, gate_details = apply_time_gate(sc["reports"], raw)
        flagged, n_contra, n_multi = apply_statuses(sc["reports"], raw)
        full, n_split_full, _ = apply_time_gate(sc["reports"], raw)
        full, n_contra_full, n_multi_full = apply_statuses(sc["reports"], full)
        entry = {
            "scenario": sid,
            "truth_groups": tg,
            "meta_old_f1": old_meta[sid],
            "meta_old_groups": old_meta_groups[sid],
            "meta_raw": {"groups": [g["reportIds"] for g in raw],
                         "f1": f1(raw, tg),
                         "clean_flagged": clean_vs_flagged(flagged)},
            "meta_gate": {"groups": [g["reportIds"] for g in gated],
                          "f1": f1(gated, tg),
                          "splits": n_split, "gate_details": gate_details},
            "meta_flag": {"groups": [g["reportIds"] for g in flagged],
                          "f1": f1(flagged, tg),
                          "n_contradictoire": n_contra, "n_multi": n_multi,
                          "clean_flagged": clean_vs_flagged(flagged)},
            "meta_full": {"groups": [g["reportIds"] for g in full],
                          "f1": f1(full, tg),
                          "splits": n_split_full,
                          "n_contradictoire": n_contra_full,
                          "n_multi": n_multi_full,
                          "clean_flagged": clean_vs_flagged(full)},
        }
        out["per_scenario"].append(entry)
        # Statuts appliques aux groupes de verite eux-memes.
        truth_groups = [{"id": f"G{i + 1}", "reportIds": g, "singleton": len(g) == 1,
                         "method": "verite", "uncertain": False, "uncertaintyReasons": []}
                        for i, g in enumerate(tg)]
        tg_flagged, tc, tm = apply_statuses(sc["reports"], truth_groups)
        out["status_on_truth"][sid] = {
            "groups": [g["reportIds"] for g in tg_flagged],
            "n_contradictoire": tc, "n_multi": tm,
            "reasons": [g["uncertaintyReasons"] for g in tg_flagged]}
        # Statuts appliques aux groupes classiques / synonymes.
        for name, src in (("classique", classic), ("synonymes", synonym)):
            fg, c, m = apply_statuses(sc["reports"], src[sid])
            out["status_on_classic_synonym"].setdefault(sid, {})[name] = {
                "groups": [g["reportIds"] for g in fg],
                "n_contradictoire": c, "n_multi": m}
        print(sid, "old", old_meta[sid], "raw", entry["meta_raw"]["f1"]["f1"],
              "gate", entry["meta_gate"]["f1"]["f1"],
              "flag", entry["meta_flag"]["f1"]["f1"],
              "full", entry["meta_full"]["f1"]["f1"],
              "| raw groups", entry["meta_raw"]["groups"],
              "| gate splits", n_split,
              "| contra", n_contra, "multi", n_multi)
    for stage in ("meta_old_f1", "meta_raw", "meta_gate", "meta_flag", "meta_full"):
        if stage == "meta_old_f1":
            vals = [e["meta_old_f1"] for e in out["per_scenario"]]
        else:
            vals = [e[stage]["f1"]["f1"] for e in out["per_scenario"]]
        out["stages"][stage] = {"mean_per_scenario": sum(vals) / len(vals), "values": vals}
    (BASE / "data" / "final_f1.json").write_text(
        json.dumps(out, indent=2, ensure_ascii=False))
    (BASE / "data" / "meta_groups_gated.json").write_text(
        json.dumps({e["scenario"]: e["meta_gate"]["groups"] for e in out["per_scenario"]},
                   indent=2, ensure_ascii=False))
    (BASE / "data" / "meta_groups_full.json").write_text(
        json.dumps({e["scenario"]: e["meta_full"]["groups"] for e in out["per_scenario"]},
                   indent=2, ensure_ascii=False))
    print("MEANS:", {k: round(v["mean_per_scenario"], 4) for k, v in out["stages"].items()})


if __name__ == "__main__":
    main()
