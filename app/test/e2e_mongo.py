# Test réel MongoDB (0.2.1) : le serveur CityResolve doit utiliser
# MongoDB comme base principale, survivre à un redémarrage et accepter
# des écritures concurrentes sans doublon d'identifiant.
# Usage : python test/e2e_mongo.py   (depuis app/, mongod sur 127.0.0.1:27017)
import concurrent.futures
import json
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
    raise RuntimeError("serveur non démarré")


def stop(p):
    subprocess.run(["taskkill", "/T", "/F", "/PID", str(p.pid)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    p.wait(timeout=15)
    time.sleep(1)


p = start()
try:
    st, db = call("GET", "/api/db")
    check(db["mongoConnected"] and "mongodb" in db["backend"],
          "MONGO backend principal connecté", str(db)[:200])
    check(db["mongoServerVersion"], "MONGO version serveur connue", str(db))
    check(call("POST", "/api/scenario/load", {"kind": "jouet-1"})[0] == 200,
          "MONGO chargement jouet-1")
    # Écritures concurrentes : 8 ajouts parallèles.
    def add(i):
        # Doublons concurrents du même incident : ids uniques exigés,
        # regroupement stable (les incidents restent planifiables).
        return call("POST", "/api/reports", {
            "text": "nid de poule rue des lilas chaussee abimee",
            "category": "nid-de-poule", "x": 1.0, "y": 1.0, "t": 900 + i,
            "severityHint": 2, "exposureHint": 1})
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        results = list(ex.map(add, range(8)))
    ids = [r[1]["id"] for r in results]
    check(all(r[0] == 200 for r in results), "MONGO 8 écritures concurrentes acceptées", str(results)[:200])
    check(len(ids) == len(set(ids)) == 8, "MONGO aucun doublon d'identifiant en concurrence", str(ids))
    st, plan = call("POST", "/api/plan", {})
    plan_id = plan["planId"]
    check(call("POST", "/api/plan/validate", {"decision": "valide"})[0] == 200, "MONGO validation")
    check(call("POST", "/api/simulate", {})[0] == 200, "MONGO simulation")
    time.sleep(2)  # laisser la file d'écriture Mongo se vider
    st, db = call("GET", "/api/db")
    counts = db["counts"]
    check(counts.get("reports", 0) >= 14, "MONGO collection reports alimentée", str(counts))
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
    check(all(i in got for i in ids), "MONGO signalements concurrents persistés après redémarrage", str(got))
    check(state["planId"] == plan_id and state["planValidation"] == "valide",
          "MONGO plan+validation restaurés depuis Mongo", str(state))
    st, db = call("GET", "/api/db")
    check(db["mongoConnected"], "MONGO reconnecté au redémarrage", str(db)[:150])
finally:
    stop(p)

print(f"== E2E MONGO : {'ECHEC ' + str(len(fails)) if fails else 'TOUT PASS'} ==")
sys.exit(1 if fails else 0)
