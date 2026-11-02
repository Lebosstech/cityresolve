#!/usr/bin/env python3
"""Mecanismes deterministes DEV pour phase4-retest-units (aucun appel Meta).

(a) Statut groupe contradictoire : un groupe fusionne est marque
    contradictoire si ses signalements portent des etats opposes
    (resolu contre en cours, detectes par lexique DEV limite) OU si
    l'ecart max des severityHint / exposureHint presents est >= 2.
    Les valeurs sont conservees, jamais moyennees ; le statut ne
    decoupe PAS le groupe, il le signale.
(b) Drapeau multi-probleme : un signalement est marque multi-probleme
    si ses jetons touchent >= 2 familles de problemes DEV (lexique
    limite documente, pas de pretention generale). Son groupe ne peut
    pas etre compte comme un seul incident propre sans ce drapeau.
(c) Porte temps Meta (post-modele, comme le garde-fou) : dans un
    groupe propose par le modele, deux signalements ne restent lies
    que si leur delai <= seuil. Seuil local (incidents ponctuels) :
    360 min (6 h), aligne sur la porte classique. Exception evenements
    etendus : si TOUS les signalements du groupe ont une categorie
    dans EXTENDED_CATEGORIES (coupure-electrique, panne-reseau),
    seuil 10080 min (7 jours), car un evenement reseau peut persister
    plusieurs jours. Categorie mixte ou ponctuelle -> seuil local
    (choix conservateur : on decoupe). La porte est appliquee APRES
    la sortie modele et chaque decoupe est comptee.
Aucune cle n'est lue ici. Aucun appel Meta ici.
"""
import math
import re

SPLITTER = re.compile(r"[^a-zàâäéèêëîïôöùûüç0-9]+")

# Familles de problemes DEV (lexique limite, vocabulaire des scenarios
# trompeurs + cas etendus). Ne pretend pas couvrir le francais general.
FAMILIES = {
    "voirie-nid": {"nid", "poule", "ndp", "trou", "chaussee", "chaus",
                   "degradee", "degrade", "abimee", "abim"},
    "eclairage": {"reverbere", "lampadaire", "eclairage", "eteint",
                  "defaillant"},
    "eau": {"fuite", "eau", "inonde", "canalisation", "ecoulement"},
    "electricite": {"coupure", "courant", "electrique", "electricite",
                    "panne"},
}
RESOLVED_TOKENS = {"resolue", "resolu", "sec", "seche", "termines",
                   "termine", "repares", "repare"}
ONGOING_TOKENS = {"inonde", "inondee", "coule", "coulee"}
LOCAL_GATE_MIN = 360          # 6 h, aligne sur la porte classique
EXTENDED_GATE_MIN = 10080     # 7 jours, evenements reseau persistants
EXTENDED_CATEGORIES = {"coupure-electrique", "panne-reseau"}


def tokens(text):
    return {w for w in SPLITTER.split(text.lower()) if len(w) > 2}


def report_families(report):
    toks = tokens(report["text"])
    return {name for name, lex in FAMILIES.items() if toks & lex}


def is_multi_problem(report):
    return len(report_families(report)) >= 2


def group_contradiction_reasons(reports, group_ids):
    """Raisons de contradiction d'un groupe, ou [] si aucune."""
    by_id = {r["id"]: r for r in reports}
    members = [by_id[i] for i in group_ids if i in by_id]
    reasons = []
    toks = set()
    for r in members:
        toks |= tokens(r["text"])
    if toks & RESOLVED_TOKENS and toks & ONGOING_TOKENS:
        reasons.append(
            "contradiction d'etat : marques resolu et en cours dans le meme groupe")
    for field, label in (("severityHint", "gravite"),
                         ("exposureHint", "exposition")):
        vals = [r[field] for r in members if r.get(field) is not None]
        if vals and max(vals) - min(vals) >= 2:
            reasons.append(
                f"contradiction de {label} : valeurs declarees {sorted(vals)}, ecart >= 2, conservees sans moyenne")
    return reasons


def apply_statuses(reports, groups):
    """Ajoute les statuts aux groupes, sans changer leurs reportIds.

    Retourne (groupes_enrichis, nb_groupes_contradictoires,
    nb_groupes_multi_probleme). Un groupe peut porter les deux statuts.
    """
    out = []
    n_contra = 0
    n_multi = 0
    for g in groups:
        reasons = list(g.get("uncertaintyReasons", []))
        contra = group_contradiction_reasons(reports, g["reportIds"])
        if contra:
            n_contra += 1
            for r in contra:
                if r not in reasons:
                    reasons.append("statut-contradictoire : " + r)
        by_id = {r["id"]: r for r in reports}
        multi_ids = [i for i in g["reportIds"]
                     if i in by_id and is_multi_problem(by_id[i])]
        if multi_ids:
            n_multi += 1
            reasons.append(
                "drapeau-multi-probleme : signalement(s) " + ",".join(multi_ids)
                + " listant >= 2 problemes distincts ; groupe non comptable comme un seul incident propre")
        ng = dict(g)
        ng["uncertaintyReasons"] = reasons
        ng["contradictoire"] = bool(contra)
        ng["multiProbleme"] = bool(multi_ids)
        ng["multiProblemeIds"] = multi_ids
        if contra or multi_ids:
            ng["uncertain"] = True
        out.append(ng)
    return out, n_contra, n_multi


def time_gate_for(reports, group_ids):
    by_id = {r["id"]: r for r in reports}
    cats = {by_id[i]["category"] for i in group_ids if i in by_id}
    if cats and cats <= EXTENDED_CATEGORIES:
        return EXTENDED_GATE_MIN, "etendu"
    return LOCAL_GATE_MIN, "local"


def apply_time_gate(reports, groups):
    """Decoupe post-modele les groupes violant la porte temps.

    Retourne (groupes, nb_groupes_decoupes, details). Chaque composante
    conserve method/justification d'origine + une raison porte-temps
    si elle provient d'un decoupage.
    """
    by_id = {r["id"]: r for r in reports}
    out = []
    n_split = 0
    details = []
    for g in groups:
        ids = list(g["reportIds"])
        if len(ids) <= 1:
            out.append(g)
            continue
        gate, kind = time_gate_for(reports, ids)
        parent = {i: i for i in ids}

        def find(x):
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        for a_i in range(len(ids)):
            for b_i in range(a_i + 1, len(ids)):
                a, b = by_id[ids[a_i]], by_id[ids[b_i]]
                if abs(a["t"] - b["t"]) <= gate:
                    parent[find(ids[a_i])] = find(ids[b_i])
        comps = {}
        for i in ids:
            comps.setdefault(find(i), []).append(i)
        if len(comps) == 1:
            out.append(g)
            continue
        n_split += 1
        delays = sorted({abs(by_id[a]["t"] - by_id[b]["t"])
                         for a_i, a in enumerate(ids)
                         for b in ids[a_i + 1:]})
        details.append({"group": g["id"], "reportIds": ids,
                        "gate_min": gate, "gate_kind": kind,
                        "delays_min": delays,
                        "components": sorted(comps.values())})
        for comp in sorted(comps.values()):
            ng = dict(g)
            ng["reportIds"] = sorted(comp)
            ng["singleton"] = len(comp) == 1
            reasons = list(g.get("uncertaintyReasons", []))
            reasons.append(
                f"porte-temps-meta : fusion proposee decoupee, delai > {gate} min (seuil {kind})")
            ng["uncertaintyReasons"] = reasons
            ng["timeGateSplit"] = True
            out.append(ng)
    out.sort(key=lambda gg: gg["reportIds"][0])
    for i, gg in enumerate(out, start=1):
        gg["id"] = f"G{i}"
    return out, n_split, details


def format_delay(dt_min):
    if dt_min >= 1440:
        days = dt_min / 1440
        return f"{dt_min} min = {days:.1f} jours".replace(".", ",")
    if dt_min >= 60:
        hours = dt_min / 60
        return f"{dt_min} min = {hours:.1f} heures".replace(".", ",")
    return f"{dt_min} min"


def pair_summary(reports):
    """Lignes distance/delai avec unites, pour le listing Meta."""
    by_id = {r["id"]: r for r in reports}
    lines = []
    ids = [r["id"] for r in reports]
    for a_i in range(len(ids)):
        for b_i in range(a_i + 1, len(ids)):
            a, b = by_id[ids[a_i]], by_id[ids[b_i]]
            d = math.hypot(a["x"] - b["x"], a["y"] - b["y"])
            dt = abs(a["t"] - b["t"])
            d_str = f"{d:.2f} km".replace(".", ",")
            lines.append(
                f"Paire {a['id']}-{b['id']} : distance {d_str}, delai {format_delay(dt)}.")
    return lines
