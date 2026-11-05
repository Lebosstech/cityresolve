# REAL restart test (Phase 1/5): starts the Dart server twice
# on a dedicated port, checks persistence, permanent ids and journal.
# Usage: python test/e2e_redemarrage.py   (from app/)
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

PORT = 18099
BASE = f"http://127.0.0.1:{PORT}"
fails = []


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, method=method, data=data,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode())


def check(cond, name, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f" :: {detail}"))
    if not cond:
        fails.append(name)


def start():
    # On Windows, dart is a .bat: go through cmd.
    p = subprocess.Popen(["cmd", "/c", "dart", "bin/server.dart", "--port", str(PORT)],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(60):
        time.sleep(0.5)
        try:
            st, _ = call("GET", "/api/health")
            if st == 200:
                return p
        except Exception:
            pass
    raise RuntimeError("server did not start")


def stop(p):
    # dart spawns a dartvm child: kill the whole tree.
    subprocess.run(["taskkill", "/T", "/F", "/PID", str(p.pid)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    p.wait(timeout=15)
    time.sleep(1)
    # Hard stop: the single-instance lock survives (documented limitation
    # of server_lock.dart); remove it, no server is running here anymore.
    try:
        os.remove("data/server.lock")
    except OSError:
        pass


p = start()
try:
    check(call("POST", "/api/scenario/load", {"kind": "jouet-1"})[0] == 200, "E2E jouet-1 load")
    st, rep = call("POST", "/api/reports", {
        "text": "fuite persistante rue du test redemarrage",
        "category": "fuite-eau", "x": 3.0, "y": 3.0, "t": 560,
        "severityHint": 3, "exposureHint": 2})
    rid = rep["id"]
    check(st == 200 and rid.startswith("M"), "E2E report created", str(rep))
    # Unknown severity: created without a hint, must stay unknown.
    # (before the plan: adding a report after grouping invalidates
    # the plan, expected server behaviour verified elsewhere)
    st, rep2 = call("POST", "/api/reports", {
        "text": "probleme vague sans gravite", "category": "fuite-eau",
        "x": 0.5, "y": 4.5, "t": 700})
    rid2 = rep2["id"]
    # POST /api/reports no longer groups (public/municipal separation):
    # explicit municipal grouping before planning.
    check(call("POST", "/api/group", {"method": "classique"})[0] == 200,
          "E2E explicit municipal grouping")
    st, plan = call("POST", "/api/plan", {})
    plan_id, plan_ver = plan["planId"], plan["version"]
    check(st == 200 and plan_ver >= 1, "E2E versioned plan", str(plan)[:120])
    check(call("POST", "/api/plan/validate", {"decision": "valide"})[0] == 200,
          "E2E human validation")
    st, sim = call("POST", "/api/simulate", {})
    check(st == 200, "E2E simulation", str(sim)[:120])
    st, j0 = call("GET", "/api/journal")
    entries_before = len(j0["entries"])
finally:
    stop(p)

p = start()
try:
    st, state = call("GET", "/api/state")
    st, reps = call("GET", "/api/reports")
    ids = [r["id"] for r in reps["reports"]]
    check(rid in ids and rid2 in ids, "E2E reports persisted after restart", str(ids))
    check(len(ids) == len(set(ids)), "E2E no duplicate id")
    check(state["planId"] == plan_id and state["planVersion"] == plan_ver,
          "E2E plan restored (id/version)", str(state))
    check(state["planValidation"] == "valide", "E2E validation restored", str(state))
    check(state["simQ"] is not None, "E2E simulation restored", str(state))
    # New id: never reassigned.
    st, rep3 = call("POST", "/api/reports", {
        "text": "apres redemarrage identifiant nouveau",
        "category": "autre", "x": 2.5, "y": 2.5, "t": 800})
    check(rep3["id"] not in (rid, rid2), "E2E id never reassigned", str(rep3))
    call("POST", "/api/group", {"method": "classique"})
    st, inc = call("GET", "/api/incidents")
    vague = [i for i in inc["incidents"] if rid2 in i["reportIds"]]
    check(bool(vague) and vague[0]["severity"] is None and vague[0]["severityStatus"] == "inconnue",
          "E2E unknown severity kept after restart", str(vague)[:200])
    st, j1 = call("GET", "/api/journal")
    check(len(j1["entries"]) > entries_before, "E2E journal continues after restart",
          f"{entries_before} -> {len(j1['entries'])}")
    events = [e["event"] for e in j1["entries"]]
    check("server.resumed" in events, "E2E resume logged", str(events[-5:]))
finally:
    stop(p)

print(f"== E2E RESTART: {'FAILED ' + str(len(fails)) if fails else 'ALL PASS'} ==")
sys.exit(1 if fails else 0)
