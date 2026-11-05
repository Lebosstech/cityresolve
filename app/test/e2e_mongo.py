# Real MongoDB test (0.2.1): the CityResolve server must use
# MongoDB as its main database, survive a restart and accept
# concurrent writes without duplicate ids.
# Usage: python test/e2e_mongo.py   (from app/, mongod on 127.0.0.1:27017)
import concurrent.futures
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

PORT = 18097
BASE = f"http://127.0.0.1:{PORT}"
fails = []


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, method=method, data=data,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode())


def check(cond, name, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f" :: {detail}"))
    if not cond:
        fails.append(name)


def start():
    p = subprocess.Popen(["cmd", "/c", "dart", "bin/server.dart", "--port", str(PORT)],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(80):
        time.sleep(0.5)
        try:
            st, _ = call("GET", "/api/health")
            if st == 200:
                return p
        except Exception:
            pass
    raise RuntimeError("server did not start")


def stop(p):
    subprocess.run(["taskkill", "/T", "/F", "/PID", str(p.pid)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    p.wait(timeout=15)
    time.sleep(1)
    # Hard stop: remove the surviving single-instance lock.
    try:
        os.remove("data/server.lock")
    except OSError:
        pass


p = start()
try:
    st, db = call("GET", "/api/db")
    check(db["mongoConnected"] and "mongodb" in db["backend"],
          "MONGO main backend connected", str(db)[:200])
    check(db["mongoServerVersion"], "MONGO server version known", str(db))
    check(call("POST", "/api/scenario/load", {"kind": "jouet-1"})[0] == 200,
          "MONGO jouet-1 load")
    # Concurrent writes: 8 parallel inserts.
    def add(i):
        # Concurrent duplicates of the same incident: unique ids required,
        # stable grouping (incidents stay plannable).
        return call("POST", "/api/reports", {
            "text": "nid de poule rue des lilas chaussee abimee",
            "category": "nid-de-poule", "x": 1.0, "y": 1.0, "t": 900 + i,
            "severityHint": 2, "exposureHint": 1})
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        results = list(ex.map(add, range(8)))
    ids = [r[1]["id"] for r in results]
    check(all(r[0] == 200 for r in results), "MONGO 8 concurrent writes accepted", str(results)[:200])
    check(len(ids) == len(set(ids)) == 8, "MONGO no duplicate ids under concurrency", str(ids))
    # POST /api/reports no longer groups: explicit municipal grouping.
    check(call("POST", "/api/group", {"method": "classique"})[0] == 200,
          "MONGO explicit municipal grouping")
    st, plan = call("POST", "/api/plan", {})
    plan_id = plan["planId"]
    check(call("POST", "/api/plan/validate", {"decision": "valide"})[0] == 200, "MONGO validation")
    check(call("POST", "/api/simulate", {})[0] == 200, "MONGO simulation")
    time.sleep(2)  # let the Mongo write queue drain
    st, db = call("GET", "/api/db")
    counts = db["counts"]
    check(counts.get("reports", 0) >= 14, "MONGO reports collection populated", str(counts))
    check(counts.get("plans", 0) >= 1 and counts.get("journals", 0) > 0
          and counts.get("teams", 0) == 2 and counts.get("simulations", 0) >= 1,
          "MONGO collections plans/journals/teams/simulations", str(counts))
    st, state0 = call("GET", "/api/state")
finally:
    stop(p)

p = start()
try:
    st, state = call("GET", "/api/state")
    st, reps = call("GET", "/api/reports")
    got = [r["id"] for r in reps["reports"]]
    check(all(i in got for i in ids), "MONGO concurrent reports persisted after restart", str(got))
    check(state["planId"] == plan_id and state["planValidation"] == "valide",
          "MONGO plan+validation restored from Mongo", str(state))
    st, db = call("GET", "/api/db")
    check(db["mongoConnected"], "MONGO reconnected after restart", str(db)[:150])
finally:
    stop(p)

print(f"== E2E MONGO: {'FAILED ' + str(len(fails)) if fails else 'ALL PASS'} ==")
sys.exit(1 if fails else 0)
