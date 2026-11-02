#!/usr/bin/env python3
"""Etape META phase4-multi-split : 10 rapprochements, 0 extraction.

Deux variantes par scenario, meme listing avec unites (retest) :
- meta_nosplit : groupes d'identifiants de signalements, un signalement
  dans au plus un groupe (comportement historique).
- meta_split : groupes d'identifiants de SOUS-signalements
  "ID:famille", familles autorisees : voirie-nid, eclairage, eau,
  electricite. Instruction : decouper un signalement UNIQUEMENT s'il
  decrit explicitement deux problemes distincts ; ne jamais decouper
  un meme probleme decrit deux fois ; ne jamais inventer une famille
  a partir d'une mention vague ; chaque sous-signalement dans au
  plus un groupe ; les sous-signalements omis sont forces en
  singletons, comme dans le code Dart.
Budget : 10 appels, sous la limite de 30. Aucune cle n'est lue,
copiee ou journalisee ici : appels via le helper du connecteur
uniquement, modele muse-spark-1.3 uniquement, raisonnement maximal
demande dans le prompt (aucun parametre reasoning_effort invente,
non documente dans le connecteur).
La verite terrain (data/truth.json) a ete ecrite AVANT ce script
et n'est jamais ecrite ici.
"""
import json
import subprocess
import sys
import time
from pathlib import Path

BASE = Path(__file__).parent
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
HEADER_UNITES = (
    "Unites (donnees ici, ne jamais les supposer absentes) : "
    "x et y en kilometres (km) sur une grille fictive, "
    "t en minutes (min) depuis le debut du scenario. "
    "60 min = 1 heure, 1440 min = 1 jour."
)
FAMILIES = ["voirie-nid", "eclairage", "eau", "electricite"]


def fmt_num(v):
    return f"{v:.1f}".replace(".", ",")


def listing_for(sc):
    lines = [HEADER_UNITES]
    for r in sc["reports"]:
        lines.append(
            f"{r['id']} | x={fmt_num(r['x'])} km, y={fmt_num(r['y'])} km, "
            f"t={r['t']} min | categorie={r['category']} | \"{r['text']}\"")
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
        record["error"] = f"JSON modele invalide : {exc} : {content[:1000]}"
        return record, None
    return record, parsed


def parse_groups(parsed, ids_expected, key):
    """Groupes valides + singletons forces pour les unites omises."""
    groups = []
    seen = set()
    if isinstance(parsed, dict):
        for g in parsed.get("groupes", []):
            ids = [x for x in g.get(key, []) if x in ids_expected]
            if not ids:
                continue
            groups.append({"ids": sorted(set(ids)),
                           "justification": g.get("justification", ""),
                           "incertitude": g.get("incertitude")})
            seen.update(ids)
    for uid in sorted(ids_expected - seen):
        groups.append({"ids": [uid], "justification": "singleton force (omis par le modele)",
                       "incertitude": None})
    return sorted(groups, key=lambda g: g["ids"][0])


def main():
    scenarios = json.loads((BASE / "data" / "scenarios.json").read_text())["scenarios"]
    truth_doc = json.loads((BASE / "data" / "truth.json").read_text())
    families = truth_doc["families_lexicon"]
    import re
    splitter = re.compile(r"[^a-zàâäéèêëîïôöùûüç0-9]+")

    def report_families(r):
        toks = {w for w in splitter.split(r["text"].lower()) if len(w) > 2}
        return [name for name in families if toks & set(families[name])] or ["inconnu"]

    logs = []
    meta_nosplit, meta_split = {}, {}
    n_calls = 0
    for sc in scenarios:
        sid = sc["id"]
        listing = listing_for(sc)
        # Variante sans decoupage.
        system = SYSTEM_MAX + (
            " Tu proposes un regroupement de signalements municipaux fictifs "
            "decivant le meme incident reel. Chaque signalement dans au plus "
            "un groupe. Si un rapprochement est douteux, dis-le dans "
            "\"incertitude\" (0=certain, 1=tres douteux) et justifie. "
            "Si un signalement decrit deux problemes distincts, signale-le "
            "explicitement dans justification au lieu de l'imposer en silence.")
        user = (listing + "\n\nRegroupe les signalements par incident reel. "
                "Format JSON : {\"groupes\": [{\"reportIds\": [...], "
                "\"justification\": string, \"incertitude\": number 0..1}]}")
        rec, parsed = call_meta("rapprochement_nosplit", sid, system, user)
        logs.append(rec)
        n_calls += 1
        if parsed is None:
            meta_nosplit[sid] = {"error": rec.get("error"), "groups": []}
        else:
            expected = {r["id"] for r in sc["reports"]}
            meta_nosplit[sid] = {"groups": parse_groups(parsed, expected, "reportIds")}
        # Variante avec decoupage.
        system2 = SYSTEM_MAX + (
            " Tu proposes un regroupement de SOUS-signalements municipaux "
            "fictifs. Chaque signalement peut etre decoupe en sous-signalements, "
            "un par probleme distinct EXPLICITEMENT decrit, identifies "
            "\"ID:famille\" avec famille parmi : voirie-nid, eclairage, eau, "
            "electricite. Decoupe UNIQUEMENT si le texte decrit explicitement "
            "deux problemes distincts (ex. nid-de-poule ET reverbere eteint). "
            "Ne decouper JAMAIS un meme probleme decrit deux fois avec deux "
            "formulations, ni a partir d'une mention vague sans probleme "
            "explicite. Chaque sous-signalement dans au plus un groupe. "
            "Si un decoupage est douteux, dis-le dans \"incertitude\" "
            "(0=certain, 1=tres douteux) et justifie.")
        user2 = (listing + "\n\nDecoupe puis regroupe par incident reel. "
                 "Format JSON : {\"groupes\": [{\"subunitIds\": [...], "
                 "\"justification\": string, \"incertitude\": number 0..1}]}")
        rec2, parsed2 = call_meta("rapprochement_split", sid, system2, user2)
        logs.append(rec2)
        n_calls += 1
        if parsed2 is None:
            meta_split[sid] = {"error": rec2.get("error"), "groups": []}
        else:
            expected2 = set()
            for r in sc["reports"]:
                for f in report_families(r):
                    expected2.add(f"{r['id']}:{f}")
            meta_split[sid] = {"groups": parse_groups(parsed2, expected2, "subunitIds")}
        print(sid, "nosplit:", meta_nosplit[sid], "split:", meta_split[sid])
    assert n_calls <= MAX_CALLS, n_calls
    (BASE / "data" / "meta_groups.json").write_text(
        json.dumps(meta_nosplit, indent=1, ensure_ascii=False))
    (BASE / "data" / "meta_split_groups.json").write_text(
        json.dumps(meta_split, indent=1, ensure_ascii=False))
    with open(BASE / "logs" / "meta_calls.jsonl", "w") as f:
        for rec in logs:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    ok = sum(1 for r in logs if "error" not in r)
    print(f"Appels Meta : {ok}/{len(logs)} reussis, limite {MAX_CALLS} respectee.")


if __name__ == "__main__":
    main()
