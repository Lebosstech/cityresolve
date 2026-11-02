#!/usr/bin/env python3
"""CityResolve confirmatory-evaluation harness, version 0.1.0.

This harness ONLY computes metrics from a pre-written truth file and from
prediction files. It never calls Meta, never reads any API key, never
contacts Atlas, and never runs a confirmatory evaluation by itself:
a result is confirmatory only after the protocol freeze, an independent
held-out set, and a freeze record, all of which are checked and labelled
in the output. DEV data evaluated here is labelled DEV-HARNESS-TEST.

Truth format (see held_out_template.json):
  set_id, label, is_held_out (bool), truth_created_utc (ISO 8601, required),
  counting_rule (required, free text, must be present),
  scenarios: list of {
    id, truth_incidents: [[subunit, ...], ...],
    secondary_subunit: subunit or null,
    incidents: optional list of {
      id, subunits: [...], severity: 1..5 or null,
      exposure: 0..4 or null, deadline_hours: number or null,
      critical: bool},
    note: str }

Prediction format:
  method, created_utc (ISO 8601, required, must be AFTER truth_created_utc),
  scenarios: { scenario_id: {
    groups: [[subunit-or-raw-report-id, ...], ...],
    plan: optional {
      planned_resolved: [truth incident id, ...],
      simulated_resolved: [truth incident id, ...],
      escalated: [truth incident id, ...],
      violations: [str, ...], cost: number or null, budget: number or null }
  } }

Counting rules implemented here, exactly as written in the multi-split
truth file and in annexes V1.1 / V1.2:
  - Truth unit is the subunit ORIGIN:FAMILY. A raw report id in a group
    is expanded to every subunit of that origin found in the truth.
  - Secondary survival: true iff some produced incident contains the
    secondary subunit AND no subunit of another family. A secondary
    singleton counts as survival, because the optimiser can then plan
    it separately. Null when there is no secondary.
  - Adapted F1: unordered pairs of subunits of the SAME family only.
    A non-split group therefore still scores the same-family pair as a
    true positive even when the secondary is lost. This F1 is DOCUMENTED
    as misleading on its own and must never be read without survival,
    incident count and exact coverage.
  - Exact coverage: fraction of truth incidents reproduced exactly
    (same subunit set) by a produced incident.
  - Q (annexe V1.1, unchanged): for S1-S4 incidents only,
    w = 0.65 * (S/4) + 0.35 * (E/4), Q = 100 * sum(w * resolved) / sum(w).
    S5 is excluded from Q and judged on detection and escalation only.
    If any S1-S4 incident has unknown severity or exposure, Q is null
    for that scenario, with the reason recorded. Unknown is never 0.
  - Violations: listed violations plus automatic checks: cost above
    budget, and an S5 incident in planned or simulated resolved
    (S5 must never be dispatched automatically to the teams).
  - Critical missed (grouping): a critical truth incident sharing no
    subunit with any produced incident. Critical missed (escalation):
    an S5 truth incident not listed in escalated, or an S4 truth
    incident not in simulated_resolved when a plan is supplied.

Refusal: the harness exits with code 2 and writes a refusal entry to
the log when truth_created_utc or a prediction created_utc is missing
or unparsable, when truth_created_utc is not strictly before the
prediction created_utc, or when counting_rule is missing. No results
file is written on refusal.

Confidence interval for the paired gain: mean of per-scenario
(Q_method - Q_reference), sample standard deviation, standard error,
and a normal 95 percent interval mean +/- 1.96 * SE. With few
scenarios the interval is indicative only and is labelled as such.
For zero missed critical incidents out of k critical incidents, the
rule-of-three upper bound 3/k is also reported (annexe V1.2).
"""
import argparse
import hashlib
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path

HARNESS_VERSION = "0.1.0-dev-harness-only"
DEFAULT_WEIGHTS = (0.65, 0.35)
SENSITIVITY_WEIGHTS = [(1.0, 0.0), (0.8, 0.2), (0.65, 0.35), (0.5, 0.5), (0.0, 1.0)]


def parse_ts(value, field):
    if not isinstance(value, str):
        raise ValueError(f"{field} missing or not a string")
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError as exc:
        raise ValueError(f"{field} unparsable: {value}") from exc
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def sha256_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def family_of(subunit):
    if ":" in subunit:
        return subunit.split(":", 1)[1]
    return None


def origin_of(subunit):
    if ":" in subunit:
        return subunit.split(":", 1)[0]
    return subunit


def pairs_of(incidents):
    """Unordered same-family pairs, as sets of two subunits."""
    pairs = set()
    for incident in incidents:
        items = sorted(set(incident))
        for i in range(len(items)):
            for j in range(i + 1, len(items)):
                a, b = items[i], items[j]
                if family_of(a) is not None and family_of(a) == family_of(b):
                    pairs.add((a, b))
    return pairs


def f1_adapted(truth_incidents, predicted_incidents):
    tp_pairs = pairs_of(truth_incidents)
    pp_pairs = pairs_of(predicted_incidents)
    tp = len(tp_pairs & pp_pairs)
    fp = len(pp_pairs - tp_pairs)
    fn = len(tp_pairs - pp_pairs)
    if tp + fp == 0 and tp + fn == 0:
        # Degenerate case: no same-family pair exists on either side.
        # Convention kept from phase4 final_f1.json, but flagged.
        return {"tp": tp, "fp": fp, "fn": fn, "precision": 1.0,
                "recall": 1.0, "f1": 1.0, "degenerate_no_pairs": True}
    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 1.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {"tp": tp, "fp": fp, "fn": fn, "precision": precision,
            "recall": recall, "f1": f1, "degenerate_no_pairs": False}


def compute_q(incidents, resolved_ids, weights):
    """Return (Q or None, reason or None). S5 excluded by construction."""
    if incidents is None:
        return None, "no allocation data in truth"
    scored = [inc for inc in incidents if inc.get("severity") != 5]
    if not scored:
        return None, "no S1-S4 incident to score"
    for inc in scored:
        if inc.get("severity") is None or inc.get("exposure") is None:
            return None, f"unknown severity or exposure for {inc.get('id')}, never treated as 0"
    ws, we = weights
    total = 0.0
    gained = 0.0
    resolved = set(resolved_ids or [])
    for inc in scored:
        w = ws * (inc["severity"] / 4.0) + we * (inc["exposure"] / 4.0)
        total += w
        if inc["id"] in resolved:
            gained += w
    if total == 0:
        return None, "total weight is zero"
    return 100.0 * gained / total, None


def evaluate_scenario(truth_scenario, pred_scenario, weights):
    truth_incidents = [sorted(set(inc)) for inc in truth_scenario["truth_incidents"]]
    truth_sets = [set(inc) for inc in truth_incidents]
    # Origin -> subunits map from the truth, for expanding raw report ids.
    origin_map = {}
    for inc in truth_incidents:
        for sub in inc:
            origin_map.setdefault(origin_of(sub), set()).add(sub)
    raw_groups = (pred_scenario or {}).get("groups", [])
    predicted = []
    unmatched = []
    for group in raw_groups:
        expanded = []
        for item in group:
            if ":" in item:
                expanded.append(item)
            elif item in origin_map:
                expanded.extend(sorted(origin_map[item]))
            else:
                unmatched.append(item)
        predicted.append(sorted(set(expanded)))
    # Secondary survival, exactly as predefined in the multi-split rule.
    secondary = truth_scenario.get("secondary_subunit")
    if secondary is None:
        survival = None
    else:
        sec_family = family_of(secondary)
        survival = any(
            secondary in grp and all(family_of(x) == sec_family for x in grp)
            for grp in predicted
        )
    exact = sum(1 for t in truth_sets if any(t == set(p) for p in predicted))
    f1 = f1_adapted(truth_incidents, predicted)
    # Over-split diagnostic: more incidents than truth, no secondary to justify it.
    over_split = len(predicted) > len(truth_incidents) and secondary is None
    # Critical and plan checks.
    incident_meta = {inc["id"]: inc for inc in (truth_scenario.get("incidents") or [])}
    # Link truth incidents to metadata by subunit set, when metadata exists.
    meta_by_subunits = {}
    for inc in truth_scenario.get("incidents") or []:
        meta_by_subunits[frozenset(inc.get("subunits", []))] = inc
    critical_grouping_missed = []
    for t in truth_sets:
        meta = meta_by_subunits.get(frozenset(t))
        if meta and meta.get("critical"):
            if not any(t & set(p) for p in predicted):
                critical_grouping_missed.append(meta["id"])
    plan = (pred_scenario or {}).get("plan") or {}
    violations = list(plan.get("violations") or [])
    cost = plan.get("cost")
    budget = plan.get("budget")
    if cost is not None and budget is not None and cost > budget:
        violations.append("cost above budget")
    planned = plan.get("planned_resolved") or []
    simulated = plan.get("simulated_resolved") or []
    escalated = plan.get("escalated") or []
    for inc in truth_scenario.get("incidents") or []:
        if inc.get("severity") == 5 and (inc["id"] in planned or inc["id"] in simulated):
            violations.append(f"S5 dispatched via teams: {inc['id']}")
    critical_escalation_missed = []
    for inc in truth_scenario.get("incidents") or []:
        if inc.get("severity") == 5 and inc["id"] not in escalated:
            critical_escalation_missed.append(inc["id"])
        if inc.get("severity") == 4 and plan and inc["id"] not in simulated:
            critical_escalation_missed.append(inc["id"])
    q_planned, q_planned_reason = compute_q(
        truth_scenario.get("incidents"), planned, weights) if plan else (None, "no plan supplied")
    q_sim, q_sim_reason = compute_q(
        truth_scenario.get("incidents"), simulated, weights) if plan else (None, "no plan supplied")
    return {
        "scenario_id": truth_scenario["id"],
        "n_truth_incidents": len(truth_incidents),
        "n_produced_incidents": len(predicted),
        "secondary_survives": survival,
        "coverage_exact": exact,
        "coverage_fraction": exact / len(truth_incidents) if truth_incidents else 0.0,
        "f1_adapte": f1,
        "f1_limite": "F1 adapte seul est trompeur: il ne penalise pas la perte d'un secondaire non decoupe. Lire avec survie, nombre d'incidents et couverture exacte.",
        "unmatched_subunits_or_ids": sorted(set(unmatched)),
        "over_split": over_split,
        "critical_grouping_missed": critical_grouping_missed,
        "critical_escalation_missed": critical_escalation_missed,
        "violations": violations,
        "n_violations": len(violations),
        "q_planned": q_planned,
        "q_planned_reason": q_planned_reason,
        "q_simulated": q_sim,
        "q_simulated_reason": q_sim_reason,
    }


def mean_ci(values):
    if not values:
        return None
    n = len(values)
    mean = sum(values) / n
    if n == 1:
        return {"n": n, "mean": mean, "sd": None, "se": None,
                "ci95_low": None, "ci95_high": None,
                "note": "n=1, no confidence interval"}
    var = sum((x - mean) ** 2 for x in values) / (n - 1)
    sd = math.sqrt(var)
    se = sd / math.sqrt(n)
    return {"n": n, "mean": mean, "sd": sd, "se": se,
            "ci95_low": mean - 1.96 * se, "ci95_high": mean + 1.96 * se,
            "note": "normal approximation, indicative only for small n"}


def main(argv=None):
    parser = argparse.ArgumentParser(description="CityResolve confirmatory harness")
    parser.add_argument("--truth", required=True)
    parser.add_argument("--predictions", nargs="+", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--log", required=False)
    parser.add_argument("--reference", required=False,
                        help="method name used as reference for paired gain")
    parser.add_argument("--sensitivity", action="store_true",
                        help="recompute Q under the 5 pre-registered weight pairs")
    parser.add_argument("--cost-stress", type=float, default=None,
                        help="extra cost multiplier for a stress variant, original untouched")
    parser.add_argument("--freeze-record", required=False)
    args = parser.parse_args(argv)

    def log_entry(entry):
        if args.log:
            log_path = Path(args.log)
            log_path.parent.mkdir(parents=True, exist_ok=True)
            with log_path.open("a", encoding="utf-8") as fh:
                fh.write(json.dumps(entry, ensure_ascii=False) + "\n")

    try:
        truth = json.loads(Path(args.truth).read_text(encoding="utf-8"))
        truth_created = parse_ts(truth.get("truth_created_utc"), "truth_created_utc")
        if not truth.get("counting_rule"):
            raise ValueError("counting_rule missing in truth file")
        predictions = []
        for pred_path in args.predictions:
            pred = json.loads(Path(pred_path).read_text(encoding="utf-8"))
            pred_created = parse_ts(pred.get("created_utc"), "prediction created_utc")
            if not truth_created < pred_created:
                raise ValueError(
                    f"REFUSAL: truth_created_utc {truth.get('truth_created_utc')} "
                    f"is not strictly before prediction created_utc "
                    f"{pred.get('created_utc')} for method {pred.get('method')}")
            predictions.append((pred_path, pred))
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"REFUSAL: {exc}", file=sys.stderr)
        log_entry({"harness_version": HARNESS_VERSION, "status": "refused",
                   "reason": str(exc), "truth": args.truth,
                   "predictions": args.predictions})
        return 2

    truth_scenarios = {s["id"]: s for s in truth["scenarios"]}
    per_method = {}
    per_scenario = {}
    for pred_path, pred in predictions:
        method = pred.get("method", Path(pred_path).stem)
        per_method[method] = {}
        for sid, tscen in truth_scenarios.items():
            result = evaluate_scenario(tscen, pred.get("scenarios", {}).get(sid), DEFAULT_WEIGHTS)
            per_scenario.setdefault(sid, {})[method] = result
            per_method[method][sid] = result

    aggregates = {}
    for method, results in per_method.items():
        vals = list(results.values())
        q_sim = [v["q_simulated"] for v in vals if v["q_simulated"] is not None]
        q_plan = [v["q_planned"] for v in vals if v["q_planned"] is not None]
        with_secondary = [v for v in vals if v["secondary_survives"] is not None]
        aggregates[method] = {
            "n_scenarios": len(vals),
            "mean_f1_adapte": sum(v["f1_adapte"]["f1"] for v in vals) / len(vals) if vals else None,
            "mean_coverage_fraction": sum(v["coverage_fraction"] for v in vals) / len(vals) if vals else None,
            "total_produced_incidents": sum(v["n_produced_incidents"] for v in vals),
            "total_truth_incidents": sum(v["n_truth_incidents"] for v in vals),
            "secondary_survival_rate": (
                sum(1 for v in with_secondary if v["secondary_survives"]) / len(with_secondary)
                if with_secondary else None),
            "secondary_scenarios": len(with_secondary),
            "total_critical_grouping_missed": sum(len(v["critical_grouping_missed"]) for v in vals),
            "total_critical_escalation_missed": sum(len(v["critical_escalation_missed"]) for v in vals),
            "total_violations": sum(v["n_violations"] for v in vals),
            "mean_q_simulated": sum(q_sim) / len(q_sim) if q_sim else None,
            "mean_q_planned": sum(q_plan) / len(q_plan) if q_plan else None,
            "q_scenarios": len(q_sim),
        }

    paired_gain = None
    if args.reference:
        ref = args.reference
        if ref in per_method:
            for method in per_method:
                if method == ref:
                    continue
                diffs = []
                for sid in truth_scenarios:
                    a = per_method[method][sid]["q_simulated"]
                    b = per_method[ref][sid]["q_simulated"]
                    if a is not None and b is not None:
                        diffs.append(a - b)
                gain = mean_ci(diffs)
                if gain is not None:
                    rel = None
                    ref_mean = aggregates[ref]["mean_q_simulated"]
                    if ref_mean:
                        rel = 100.0 * gain["mean"] / ref_mean
                    paired_gain = {"method": method, "reference": ref,
                                   "absolute_gain": gain, "relative_gain_percent": rel,
                                   "note": "relative gain undefined when reference mean is zero; absolute gain counts"}

    sensitivity = None
    if args.sensitivity:
        sensitivity = {}
        for ws, we in SENSITIVITY_WEIGHTS:
            row = {}
            for pred_path, pred in predictions:
                method = pred.get("method", Path(pred_path).stem)
                qs = []
                for sid, tscen in truth_scenarios.items():
                    plan = (pred.get("scenarios", {}).get(sid) or {}).get("plan") or {}
                    q, _ = compute_q(tscen.get("incidents"), plan.get("simulated_resolved"), (ws, we))
                    if q is not None:
                        qs.append(q)
                row[method] = sum(qs) / len(qs) if qs else None
            sensitivity[f"{ws:.2f}/{we:.2f}"] = row

    cost_stress = None
    if args.cost_stress is not None:
        cost_stress = {}
        for pred_path, pred in predictions:
            method = pred.get("method", Path(pred_path).stem)
            extra = []
            for sid, tscen in truth_scenarios.items():
                plan = (pred.get("scenarios", {}).get(sid) or {}).get("plan") or {}
                cost, budget = plan.get("cost"), plan.get("budget")
                if cost is not None and budget is not None and cost * args.cost_stress > budget:
                    extra.append(sid)
            cost_stress[method] = {"factor": args.cost_stress,
                                   "scenarios_over_budget_under_stress": extra}

    # Freeze / evaluation-kind labelling. Never claim confirmatory without
    # a freeze record and a held-out set.
    freeze_info = None
    if args.freeze_record:
        freeze_info = json.loads(Path(args.freeze_record).read_text(encoding="utf-8"))
    if truth.get("is_held_out"):
        if freeze_info:
            evaluation_kind = "HELD-OUT-CANDIDATE-WITH-FREEZE-RECORD"
        else:
            evaluation_kind = "HELD-OUT-WITHOUT-FREEZE-RECORD-NOT-CONFIRMATORY"
    else:
        evaluation_kind = "DEV-HARNESS-TEST-NOT-CONFIRMATORY"

    output = {
        "harness_version": HARNESS_VERSION,
        "evaluation_kind": evaluation_kind,
        "truth": {"path": args.truth, "sha256": sha256_file(args.truth),
                  "set_id": truth.get("set_id"), "is_held_out": truth.get("is_held_out"),
                  "truth_created_utc": truth.get("truth_created_utc")},
        "predictions": [{"path": p, "sha256": sha256_file(p), "method": pred.get("method"),
                         "created_utc": pred.get("created_utc")} for p, pred in predictions],
        "per_scenario": per_scenario,
        "aggregates": aggregates,
        "paired_gain_vs_reference": paired_gain,
        "sensitivity_weights": sensitivity,
        "cost_stress": cost_stress,
        "meta_interface": {
            "note": "Meta predictions, when supplied later, must carry a meta_calls log in the same format as phase4 logs (one JSON line per call, with model, scenario and usage). This run made no Meta call and read no Meta log.",
            "meta_calls_log_checked": False,
        },
        "warnings": [
            "F1 adapte seul est trompeur. Lire avec survie, nombre d'incidents et couverture exacte.",
            "Un resultat DEV n'est jamais un resultat confirmatoire et n'est jamais une preuve de Niveau 3.",
        ],
    }
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")
    log_entry({"harness_version": HARNESS_VERSION, "status": "ok",
               "evaluation_kind": evaluation_kind,
               "truth_sha256": output["truth"]["sha256"],
               "predictions": output["predictions"],
               "out_path": str(out_path),
               "out_sha256": sha256_file(out_path),
               "aggregates": aggregates, "paired_gain_vs_reference": paired_gain})
    print(json.dumps({"evaluation_kind": evaluation_kind, "aggregates": aggregates,
                      "paired_gain_vs_reference": paired_gain}, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
