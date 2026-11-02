#!/usr/bin/env python3
"""Etape META phase4-retest-units : NOUVEAU listing avec unites explicites.

Difference par rapport a phase4-misleading (ancien listing) :
- chaque ligne donne t en minutes (ex. t=500 min) et x/y en km
  (ex. x=2,0 km, y=2,0 km), jamais de nombre nu ;
- un en-tete d'unites est affiche avant le listing ;
- pour chaque paire, distance en km et delai en minutes + conversion
  (heures/jours) sont calcules et affiches, ex. delai 4320 min = 3,0 jours ;
- le prompt systeme dit explicitement : ne jamais supposer une unite
  absente (les unites SONT donnees ici), et traiter 4320 min comme
  3 jours, pas comme un delai court.
Budget : 6 rapprochements uniquement, sous la limite de 30.
Aucune cle n'est lue, copiee ou journalisee ici : appels via le
helper du connecteur uniquement, modele muse-spark-1.3 uniquement,
raisonnement maximal demande dans le prompt (aucun parametre
reasoning_effort invente, non documente dans le connecteur).
La verite terrain (data/truth.json) a ete copiee AVANT ce script
(hash identique a phase4-misleading) et n'est jamais ecrite ici.
"""
import json
import subprocess
import sys
import time
from pathlib import Path

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from mechanisms import pair_summary  # noqa: E402

HELPER = Path.home() / "workspace" / "custom-connectors" / "custom.meta-model-api" / "bin" / "meta_chat.py"
MODEL = "muse-spark-1.3"
MAX_CALLS = 30
SYSTEM_MAX = (
    "Tu es un analyste exhaustif, niveau de raisonnement maximal. "
    "Analyse chaque element, chaque paire, chaque distance, chaque delai "
    "et chaque mot, sans raccourci, sans approximation non signalee. "
    "Si une information est absente, douteuse ou non verifiable, dis-le "
    "explicitement. N'invente jamais une gravite, un lieu, un temps, "
    "un fait, une certitude ou un signalement. Reponds UNIQUEMENT en JSON."
)
SYSTEM_MATCH = SYSTEM_MAX + (
    " Tu proposes un regroupement de signalements municipaux fictifs "
    "decivant le meme incident reel. Chaque signalement dans au plus "
    "un groupe. Si un rapprochement est douteux, dis-le dans "
    "\"incertitude\" (0=certain, 1=tres douteux) et justifie. "
    "REGLE D'UNITES, A APPLIQUER SANS EXCEPTION : les unites SONT donnees "
    "dans le listing ci-dessous (x et y en kilometres, t en minutes). "
    "Ne jamais ecrire qu'une unite est absente, inconnue ou non verifiable "
    "quand le listing la donne. Un delai de 4320 min vaut 3 jours, pas un "
    "delai court ; un delai de 20 min vaut 20 minutes. Pour un incident "
    "ponctuel (nid-de-poule, fuite d'eau), un delai de plusieurs jours au "
    "meme lieu ne prouve pas qu'il s'agit du meme incident : deux "
    "incidents distincts restent possibles meme avec un texte quasi "
    "identique, et la persistance d'une degradation ne prouve pas "
    "l'identite. Si deux signalements ont le meme texte mais des lieux "
    "ou temps eloignes, ne fusionne pas a l'aveugle : pese le type "
    "d'evenement, et signale l'ambiguite dans justification et incertitude. "
    "Si un signalement decrit deux problemes distincts, ou si les "
    "signalements se contredisent sur l'etat (resolu contre en cours), "
    "ou si la categorie declaree contredit le texte, signale-le "
    "explicitement dans justification et incertitude au lieu de "
    "l'imposer en silence."
)
HEADER_UNITES = (
    "Unites (donnees ici, ne jamais les supposer absentes) : "
    "x et y en kilometres (km) sur une grille fictive, "
    "t en minutes (min) depuis le debut du scenario. "
    "60 min = 1 heure, 1440 min = 1 jour."
)


def fmt_num(v):
    return f"{v:.1f}".replace(".", ",")


def listing_for(sc):
    lines = [HEADER_UNITES]
    for r in sc["reports"]:
        lines.append(
            f"{r['id']} | x={fmt_num(r['x'])} km, y={fmt_num(r['y'])} km, "
            f"t={r['t']} min | categorie={r['category']} | \"{r['text']}\"")
    lines.append("Distances et delais calcules :")
    lines.extend(pair_summary(sc["reports"]))
    return "\n".join(lines)


def call_meta(kind, scenario, system, user):
    started = time.time()
    proc = subprocess.run([sys.executable, str(HELPER), MODEL, system, user],
                          capture_output=True, text=True, timeout=180)
    wall_ms = int((time.time() - started) * 1000)
    record = {"kind": kind, "scenario": scenario, "model": MODEL,
              "wall_ms": wall_ms, "returncode": proc.returncode,
              "stderr_tail": proc.stderr[-500:] if proc.stderr else ""}
    if proc.returncode != 0:
        record["error"] = proc.stdout[-2000:] or proc.stderr[-2000:]
        return record, None
    try:
        raw = json.loads(proc.stdout)
    except Exception as exc:
        record["error"] = f"sortie helper non JSON : {exc} : {proc.stdout[:1000]}"
        return record, None
    if "http" in raw:
        record["error"] = raw
        return record, None
    record["latency_ms"] = raw.get("_latency_ms", wall_ms)
    record["usage"] = raw.get("usage")
    record["api_model"] = raw.get("model")
    record["finish_reason"] = (raw.get("choices", [{}])[0].get("finish_reason")
                               if raw.get("choices") else None)
    try:
        content = raw["choices"][0]["message"]["content"]
    except Exception as exc:
        record["error"] = f"contenu inattendu : {exc} : {str(raw)[:1000]}"
        return record, None
    record["raw_content"] = content
    try:
        parsed = json.loads(content)
    except Exception as exc:
        record["error"] = f"contenu non JSON : {exc}"
        return record, None
    record["parsed"] = parsed
    return record, parsed


def groups_from_parsed(parsed, sc):
    known = {r["id"] for r in sc["reports"]}
    seen = set()
    groups = []
    for gj in parsed.get("groupes", []) or []:
        ids = sorted({str(x) for x in (gj.get("reportIds") or [])} & known - seen)
        seen.update(ids)
        if not ids:
            continue
        try:
            inc = float(gj.get("incertitude")) if gj.get("incertitude") is not None else 0.5
        except (TypeError, ValueError):
            inc = 0.5
        inc = min(1.0, max(0.0, inc))
        groups.append({"id": f"G{len(groups) + 1}", "reportIds": ids,
                       "confidence": 1.0 - inc, "singleton": len(ids) == 1,
                       "method": "meta", "uncertain": inc >= 0.35,
                       "uncertaintyReasons": ([f"incertitude modele {inc:.2f}"] if inc >= 0.35 else []),
                       "justification": gj.get("justification"),
                       "incertitude": inc})
    for r in sc["reports"]:
        if r["id"] not in seen:
            groups.append({"id": f"G{len(groups) + 1}", "reportIds": [r["id"]],
                           "confidence": 0.0, "singleton": True, "method": "meta",
                           "uncertain": True,
                           "uncertaintyReasons": ["non classe par le modele : singleton force"],
                           "justification": None, "incertitude": None})
    groups.sort(key=lambda g: g["reportIds"][0])
    for i, g in enumerate(groups, start=1):
        g["id"] = f"G{i}"
    return groups


def main():
    scenarios = {s["id"]: s for s in json.loads((BASE / "data" / "scenarios.json").read_text())["scenarios"]}
    log_path = BASE / "logs" / "meta_calls.jsonl"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    calls = []
    meta_groups = {}
    errors = []

    def log(record):
        calls.append(record)
        with log_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")
        print(f"[{len(calls)}/{MAX_CALLS}] {record['kind']} {record['scenario']} rc={record['returncode']} lat={record.get('latency_ms')} usage={record.get('usage')} err={bool(record.get('error'))}", flush=True)

    for sc_id, sc in scenarios.items():
        if len(calls) >= MAX_CALLS:
            errors.append(f"budget atteint avant rapprochement {sc_id}")
            meta_groups[sc_id] = None
            continue
        user = (f"Signalements :\n{listing_for(sc)}\n"
                "JSON attendu : {\"groupes\": [{\"reportIds\": [string], \"justification\": string, \"incertitude\": number 0..1}]}")
        rec, parsed = call_meta("rapprochement", sc_id, SYSTEM_MATCH, user)
        rec["listing"] = listing_for(sc)
        log(rec)
        if parsed is None:
            errors.append(f"rapprochement echoue {sc_id}: {rec.get('error')}")
            meta_groups[sc_id] = None
            continue
        meta_groups[sc_id] = groups_from_parsed(parsed, sc)
        print(f"  -> {sc_id} meta groups=", [g["reportIds"] for g in meta_groups[sc_id]], flush=True)
    (BASE / "data" / "meta_groups.json").write_text(
        json.dumps(meta_groups, indent=2, ensure_ascii=False))
    (BASE / "data" / "meta_calls_summary.json").write_text(
        json.dumps({"total_calls": len(calls), "errors": errors,
                    "model": MODEL, "max_calls": MAX_CALLS}, indent=2, ensure_ascii=False))
    print(f"TOTAL appels Meta : {len(calls)} (limite {MAX_CALLS})")
    print(f"Erreurs : {errors if errors else 'aucune'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
