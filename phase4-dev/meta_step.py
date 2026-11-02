#!/usr/bin/env python3
"""Etape META Phase 4 DEV, via le helper du connecteur uniquement.

Aucune cle n'est lue, copiee ou journalisee ici. Le helper
meta_chat.py place un substitut securise ; le runtime substitue
la vraie cle uniquement pour api.meta.ai.
Modele : muse-spark-1.3, le plus recent de la liste verifiee.
Raisonement : niveau maximal demande dans le prompt systeme
(analyse exhaustive, aucun raccourci). Aucun parametre
reasoning_effort de l'API n'est utilise : il n'est pas documente
dans le connecteur, donc on ne l'invente pas.
Budget : 13 extractions + 4 rapprochements = 17 appels, sous la
limite de 20 fixee par la mission. En cas d'echec, l'erreur est
journalisee telle quelle, aucun resultat n'est simule.
"""
import json
import subprocess
import sys
import time
from pathlib import Path

BASE = Path(__file__).parent
HELPER = Path.home() / "workspace" / "custom-connectors" / "custom.meta-model-api" / "bin" / "meta_chat.py"
MODEL = "muse-spark-1.3"
MAX_CALLS = 20

SYSTEM_MAX = (
    "Tu es un analyste exhaustif, niveau de raisonnement maximal. "
    "Analyse chaque element, chaque paire, chaque distance, chaque delai "
    "et chaque mot, sans raccourci, sans approximation non signalee. "
    "Si une information est absente, douteuse ou non verifiable, dis-le "
    "explicitement. N'invente jamais une gravite, un lieu, un fait, "
    "une certitude ou un signalement. Reponds UNIQUEMENT en JSON."
)

SYSTEM_EXTRACT = SYSTEM_MAX + (
    " Tu extrais des informations de signalements municipaux fictifs."
)

SYSTEM_MATCH = SYSTEM_MAX + (
    " Tu proposes un regroupement de signalements municipaux fictifs "
    "decivant le meme incident reel. Chaque signalement dans au plus "
    "un groupe. Si un rapprochement est douteux, dis-le dans "
    "\"incertitude\" (0=certain, 1=tres douteux) et justifie."
)

EXTRACTION_IDS = {
    "jouet-1": ["R1", "R3", "R5"],
    "e1-diagnostic": ["A1"],
    "e2-synonymes": ["A1"],
    # dev-7 : premier signalement de chaque groupe vrai
    "dev-7": ["D1", "D5", "D8", "D11", "D14", "D16", "D18", "D20"],
}


def call_meta(kind, scenario, model, system, user):
    """Un appel via le helper. Retourne (record, parsed_content_or_None)."""
    started = time.time()
    proc = subprocess.run(
        [sys.executable, str(HELPER), model, system, user],
        capture_output=True, text=True, timeout=120,
    )
    wall_ms = int((time.time() - started) * 1000)
    record = {
        "kind": kind, "scenario": scenario, "model": model,
        "wall_ms": wall_ms, "returncode": proc.returncode,
        "stderr_tail": proc.stderr[-500:] if proc.stderr else "",
    }
    if proc.returncode != 0:
        record["error"] = proc.stdout[-2000:] or proc.stderr[-2000:]
        return record, None
    try:
        raw = json.loads(proc.stdout)
    except Exception as exc:  # noqa: BLE001 - journaliser tel quel
        record["error"] = f"sortie helper non JSON : {exc} : {proc.stdout[:1000]}"
        return record, None
    if "http" in raw:
        record["error"] = raw
        return record, None
    record["latency_ms"] = raw.get("_latency_ms", wall_ms)
    record["usage"] = raw.get("usage")
    record["api_model"] = raw.get("model")
    record["finish_reason"] = (
        raw.get("choices", [{}])[0].get("finish_reason")
        if raw.get("choices") else None
    )
    content = None
    try:
        content = raw["choices"][0]["message"]["content"]
    except Exception as exc:  # noqa: BLE001
        record["error"] = f"contenu inattendu : {exc} : {str(raw)[:1000]}"
        return record, None
    record["raw_content"] = content
    try:
        parsed = json.loads(content)
    except Exception as exc:  # noqa: BLE001
        record["error"] = f"contenu non JSON : {exc}"
        return record, None
    record["parsed"] = parsed
    return record, parsed


def main():
    scenarios = {
        s["id"]: s
        for s in json.loads((BASE / "data" / "scenarios.json").read_text())["scenarios"]
    }
    log_path = BASE / "logs" / "meta_calls.jsonl"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    calls = []
    extractions = {}
    meta_groups = {}
    errors = []

    def log(record):
        calls.append(record)
        with log_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")
        print(f"[{len(calls)}/{MAX_CALLS}] {record['kind']} {record['scenario']} "
              f"rc={record['returncode']} "
              f"lat={record.get('latency_ms')} usage={record.get('usage')} "
              f"err={bool(record.get('error'))}")

    # 1) Extractions structurees, echantillon defini a l'avance.
    for sc_id, rids in EXTRACTION_IDS.items():
        sc = scenarios[sc_id]
        by_id = {r["id"]: r for r in sc["reports"]}
        for rid in rids:
            if len(calls) >= MAX_CALLS:
                errors.append(f"budget atteint avant extraction {sc_id}/{rid}")
                break
            r = by_id[rid]
            user = (
                f"Signalement {r['id']} (catégorie déclarée: {r['category']}) : "
                f"\"{r['text']}\"\n"
                "JSON attendu: {\"probleme\": string, \"description\": string, "
                "\"localisationMentionnee\": string|null, "
                "\"graviteExprimee\": integer 1..5|null, "
                "\"expositionMentionnee\": string|null, "
                "\"incertitudes\": [string], \"elementsNonVerifies\": [string]}"
            )
            rec, parsed = call_meta("extraction", sc_id, MODEL, SYSTEM_EXTRACT, user)
            rec["report_id"] = rid
            log(rec)
            if parsed is None:
                errors.append(f"extraction echouee {sc_id}/{rid}: {rec.get('error')}")
            else:
                extractions.setdefault(sc_id, {})[rid] = parsed

    # 2) Rapprochements, un appel par scenario, meme format que le
    # connecteur Dart (listing id | x y t | categorie | texte).
    for sc_id, sc in scenarios.items():
        if len(calls) >= MAX_CALLS:
            errors.append(f"budget atteint avant rapprochement {sc_id}")
            break
        listing = "\n".join(
            f"{r['id']} | x={r['x']} y={r['y']} t={r['t']} "
            f"| catégorie={r['category']} | \"{r['text']}\""
            for r in sc["reports"]
        )
        user = (
            f"Signalements:\n{listing}\n"
            "JSON attendu: {\"groupes\": [{\"reportIds\": [string], "
            "\"justification\": string, \"incertitude\": number 0..1}]}"
        )
        rec, parsed = call_meta("rapprochement", sc_id, MODEL, SYSTEM_MATCH, user)
        log(rec)
        if parsed is None:
            errors.append(f"rapprochement echoue {sc_id}: {rec.get('error')}")
            meta_groups[sc_id] = None
            continue
        known = {r["id"] for r in sc["reports"]}
        seen = set()
        groups = []
        for gj in parsed.get("groupes", []) or []:
            ids = sorted(
                {str(x) for x in (gj.get("reportIds") or [])}
                & known - seen
            )
            seen.update(ids)
            if not ids:
                continue
            inc = gj.get("incertitude")
            try:
                inc = float(inc) if inc is not None else 0.5
            except (TypeError, ValueError):
                inc = 0.5
            inc = min(1.0, max(0.0, inc))
            groups.append({
                "id": f"G{len(groups) + 1}",
                "reportIds": ids,
                "confidence": 1.0 - inc,
                "singleton": len(ids) == 1,
                "method": "meta",
                "uncertain": inc >= 0.35,
                "uncertaintyReasons": (
                    [f"incertitude modèle {inc:.2f}"] if inc >= 0.35 else []
                ),
                "justification": gj.get("justification"),
                "incertitude": inc,
            })
        for r in sc["reports"]:
            if r["id"] not in seen:
                groups.append({
                    "id": f"G{len(groups) + 1}",
                    "reportIds": [r["id"]],
                    "confidence": 0.0,
                    "singleton": True,
                    "method": "meta",
                    "uncertain": True,
                    "uncertaintyReasons": ["non classé par le modèle : singleton forcé"],
                    "justification": None,
                    "incertitude": None,
                })
        groups.sort(key=lambda g: g["reportIds"][0])
        for i, g in enumerate(groups, start=1):
            g["id"] = f"G{i}"
        meta_groups[sc_id] = groups

    (BASE / "data" / "meta_extractions.json").write_text(
        json.dumps(extractions, indent=2, ensure_ascii=False))
    (BASE / "data" / "meta_groups.json").write_text(
        json.dumps(meta_groups, indent=2, ensure_ascii=False))
    (BASE / "data" / "meta_calls_summary.json").write_text(
        json.dumps({"total_calls": len(calls), "errors": errors,
                    "model": MODEL}, indent=2, ensure_ascii=False))
    print(f"TOTAL appels Meta : {len(calls)} (limite {MAX_CALLS})")
    print(f"Erreurs : {errors if errors else 'aucune'}")
    for sc_id, groups in meta_groups.items():
        print(sc_id, "meta groups=",
              None if groups is None else [g["reportIds"] for g in groups])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
