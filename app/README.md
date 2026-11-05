# CityResolve — DEV sandbox 0.2.1

Local exploratory development application.
**Fictitious data. Scientific protocol NOT FROZEN. No proof.**

## Prerequisites

- Dart SDK only, no network dependencies (`app/pubspec.yaml` empty).
- Verified here: Dart SDK 3.13.7 via the Flutter cache, offline Windows.

## Running it

```powershell
cd E:\cytsense\app
dart test/test_all.dart
dart test/test_exploratoire.dart
python test/e2e_redemarrage.py
dart bin/server.dart --port 8080
# then open http://127.0.0.1:8080
# port busy: the server reports it and stops; restart with --port 8081
```

## Persistence (Phase 1 + MongoDB 0.2.1)

**Main database: local MongoDB** `mongodb://127.0.0.1:27017/cityresolve_dev`
(`mongo_dart` driver, collections reports/incidents/plans/teams/simulations/
journals/meta_calls/state, indexes on ids, `t`, `(x,y)`, `seq`). Start
MongoDB (bound to 127.0.0.1 only, no public access):

```powershell
& "C:\Users\brunotanguy\AppData\Local\Temp\opencode\mongo-bin\mongodb-win32-x86_64-windows-7.0.14\bin\mongod.exe" --dbpath "C:\Users\brunotanguy\AppData\Local\MongoDB\data" --bind_ip 127.0.0.1 --port 27017 --logpath "C:\Users\brunotanguy\AppData\Local\MongoDB\mongod.log" --logappend
dart run test/mongo_check.dart
```

Every HTTP mutation waits for the Mongo write before responding. No
multi-document transactions (no replica set): state document + mirrors
collection by collection. Atlas connection: timeout raised to 25 s (slow
TLS/SRV handshake on first contact; 5 s insufficient, wrongly falling back to JSON). JSON backup kept, read as an explicit fallback
if MongoDB is unreachable (`GET /api/db` shows the effective backend).
Pre-migration backup: `app/data/backup-pre-mongo-20261102/`.

Full state also persisted in `app/data/state.json`: reports and their
sources, groups/incidents, plans, validations, simulations, Meta calls,
id counters. Near-atomic write (tmp -> `.bak` rotation ->
rename, `lib/store.dart`). Permanent ids: reports `M<n>` and
plans `PLAN-<version>` from persisted monotonic counters, never
reassigned after restart (verified by `test/e2e_redemarrage.py`).

Journal/state consistency: the JSONL audit is written **before** the state (`auditSeq`
field in the document). This is **not** an atomic operation: a
hard stop between the two writes leaves a gap, detected at startup
and logged (`store.reconciled`), resume logged (`server.resumed`).
Do not run two servers on the same `data` directory.
Deleting `data/state.json` (+ `.bak`) restarts from toy no. 1.

## Unknown data (Phase 2)

Severity and exposure are **never** inferred from the category.
Each incident attribute carries value + status (`declaree`, `estimee`,
`contradictoire`, `inconnue`) + kept declared values
(`lib/incidents.dart`). Unknown or contradictory severity: no automatic
dispatch, reason "human verification required", no invented deadline.
Declared S5: human escalation, never dispatched to any team.
Borderline groupings flagged: `uncertain` groups (similarity near the
threshold, transitive chaining, contradictory severities) and
`separated but ambiguous` pairs (`ambiguousPairs`). Manual reports stay
operational; they are excluded from F1 for lack of ground truth, and that absence is
shown explicitly (never an invented score).

## Public page + areas (branch work/public-homepage)

- `/`: real public page (connected form, incident map,
  recent reports, tracking by id, about). Faithful to the
  mock-up; hero as an SVG illustration (no photo of a person); video
  and voice message shown as "Coming soon", disabled, no fake
  upload; GPS disabled (choice on the fictitious grid only);
  map labelled "Demonstration map — Fictitious data".
- `/municipal`: existing DEV interface, functionally unchanged,
  behind a login screen when a token is configured.
- Public map: free OpenStreetMap base (Leaflet 1.9, OSM tiles
  with attribution, clean offline fallback). Positions remain
  fictitious data explicitly labelled "projected" around a
  demonstration anchor (Abidjan-Plateau) — never presented as
  GPS readings. The selector converts the click into grid coordinates.
- Browser GPS: "My position (GPS)" button active, browser consent,
  explicit refusal outside the demo zone (3.54 km), refusal/absence/timeout handled.
  Reading stored (`gpsLat/gpsLon/gpsAccuracy`, validated) and visible
  only on the tracking record (never in lists). Unchanged x/y grid
  for the optimiser.
- Public exposure security (§6): `POST /api/reports` and
  `POST /api/photos` rate-limited (429 + Retry-After), text
  1–500 characters, closed categories, 500 reports max; everything
  else (scenarios, grouping, plan, simulation, injection, comparisons,
  journal, Meta, db/state/plans) requires the municipal token
  (`CITYRESOLVE_MUNICIPAL_TOKEN`, HttpOnly cookie or Bearer).
  Without a configured token: documented open mode (local dev only).
- Assumed change: `POST /api/reports` no longer groups (a visitor
  must not invalidate the municipal plan); the municipal interface
  groups explicitly. `Report.receivedAt` (server ISO-8601) added.
- Render: add `CITYRESOLVE_MUNICIPAL_TOKEN` (sync: false) in
  `render.yaml` — done. Never deploy without this token. The Meta key
  stays server-side, never exposed to the browser.

## API (JSON, local)

Health/policy: `GET /api/health`, `GET /api/policy`, `GET /api/state`, `GET /api/plans`.
AI connector: `GET /api/meta`, `POST /api/meta/verify` (real GET call to
`api.llama.com/v1/models`), `POST /api/meta/extract` `{reportId}`,
`GET /api/meta/calls` (model, inputs, outputs, errors, latency, usage).
Visible scenarios: `GET /api/scenarios`, `POST /api/scenario/load` `{kind: jouet-1|jouet-s5|dev, seed}`.
Reports: `GET /api/reports` (municipal), `POST /api/reports`
(public, limited, text 1–500, closed category, server `receivedAt`,
no grouping).
Public: `GET /api/public/reports`, `GET /api/public/reports/<id>` (tracking),
`GET /api/public/incidents` (filtered data, `fictive: true`).
Scalable public (never a full load):
`POST /api/public/report` (canonical creation alias),
`GET /api/public/reports/recent?limit&cursor` (cursor pagination),
`GET /api/public/incidents/map?bbox&limit` (grid bbox + strict limit),
`GET /api/public/report/<id>` (canonical tracking),
`GET /api/public/stats/summary` (counters only).
Municipal: `POST /api/municipal/login|logout`, `GET /api/municipal/status`.
Municipal dashboard (`/municipal/dashboard`, protected, SINGLE
MUNICIPAL PATH — the old DEV space `index.html`/`app.js`/`styles.css`
is deleted, `/municipal` and `/index.html` redirect here): `GET
/api/municipal/dashboard/{summary,latest-report,incident-status,map,
activity,priority-plan,search}` — bounded, cursor-paginated aggregates,
never a full read. Panels: KPIs, latest report, exclusive
statuses, labelled fictitious OSM map, logged activity, prioritised
plan + "Optimise the plan" button, simulation, revision (inject), comparison
CLASSIC/META, paginated journal, server search — every action
calls the existing endpoints (no duplicated logic). Load
measured at 1M via `dart run test/load_dashboard.dart --n=1000000`;
see `docs/PERSISTANCE_EVOLUTION.md` for the high-volume trajectory.

## Homepage scalability (reasoned, no million in the application database)

- The public page NEVER reads MongoDB directly: it serves the
  in-memory working state (bounded: 500 reports max + scenario), sorted and
  paginated server-side (`sortPublicReports`, cursor = last id seen,
  unknown cursor → empty page, no jump). No `SELECT *`, no
  join: incidents pre-computed by municipal grouping,
  counters only for stats, photos as on-demand thumbnails.
- Mongo indexes (mirrors + possible direct access): `reports(receivedAt
  -1, category, x/y, t, source)`, `journals(seq unique, event)`,
  `incidents(id)`, `plans(version)`, `simulations(planId)`,
  `meta_calls(kind)`. The `simulation_video` collection (1M, outside
  the application) is never touched by the homepage.
- Limits: in-memory sorting/pagination hold up to the 500 bound; beyond
  that (if the bound changes), Mongo will have to be queried with these indexes
  (already-indexed queries, no route refactor).
Grouping: `POST /api/group` `{distMaxM, deltaTMaxH, simMin, method: classique|meta}` -> groups + incidents + uncertainties + F1 (DEV ground truth).
Planning: `POST /api/plan` (exact optimiser shared by both methods, versioned plan), `POST /api/plan/validate` `{decision: valide|rejete}`.
Simulation: `POST /api/simulate` -> simulated R, violations, robustness ×1.2/×1.5.
Injection: `POST /api/inject` `{type: reports|team_down, ...}` -> oracle necessity + revision.
Comparisons: `POST /api/compare` `{configs: [...]}` (classic parameters),
`GET /api/compare-methods` (CLASSIC vs META, disagreements, separate F1/Q, DEV only).
Journal: `GET /api/journal` (mirror of `app/data/journal.jsonl`, not versioned).

## Meta Model API (Phase 3, fixed in 0.2.1)

Official Meta Model API documentation (developer.meta.ai): base
`https://api.meta.ai/v1`, Bearer `MODEL_API_KEY`, `GET /models`,
`POST /chat/completions` (OpenAI-compatible, `choices[0].message.content`,
standard usage). Key **server-side only**, never to the browser.
Main variable: `MODEL_API_KEY` (alias `LLAMA_API_KEY` /
`CITYRESOLVE_META_API_KEY` as explicit fallback only, source shown).
Key used as provided, server-side only, never logged.

State verified on 2026-11-02: **real access confirmed** — `GET /v1/models`
HTTP 200, 9 authorised models (muse-spark-1.1/1.2/1.3, muse-wonder-1.0,
muse-image-1.0, sam-3.1, etc.). Real inferences (muse-spark-1.1):
extraction of R1 without invention (absent severity -> null + uncertainty),
toy-1 matching identical to classic (F1 = 1.0 and Q = 100 for both,
0 disagreements), real divergence on DEV synonyms (CLASSIC separates, META
merges, F1 unchanged as manuals are outside ground truth). Latencies 1.7–5 s, usage
logged. No conclusion of superiority: DEV data only.
The classic engine works fully without Meta.

## Active policy (provisional, NOT validated)

Q 65/35, S1 7d / S2 72h / S3 24h / S4 4h calendar, S5 escalation off-plan,
E bands 0–4 (unknown≠0, decision E=4; decision severity 4 for weight
calculation only, no dispatch), 2 teams (voirie+EV / voirie+reseaux),
08:00–16:00, 5×5 km grid at 20 km/h, budget 120 fictitious units.
Details: `lib/policy.dart`. No value is a real measurement.

## Q score and cliff (verified, unchanged)

DEV seed 7: plan estimated at 118.4/120, simulated realised cost 142.2, Q = 0.
"Global violation → Q=0" rule from SPECIFICATION_D_SIMU §7 and
PREENREGISTREMENT_V1.5 §3 (D-Q0 register: business validation required),
applied in `lib/simulator.dart`. Q formula unchanged.

## Photos and visual analysis (P1, branch work/multimodal-vision)

- `POST /api/photos` (raw bytes, jpeg/png/gif/webp ≤ 5 MB, magic-bytes
  check) → `{mediaId, mime, size}`; `GET /api/photos/<id>` serves
  the file. Storage: `app/data/uploads/` (never in the JSON state nor
  in the database; `Report.photo` carries only the mediaId).
- `POST /api/meta/analyze-image` `{reportId}` or `{mediaId}`: real call
  (base64 images only in the `user` message, documented compatible
  model: `muse-spark-1.3`), server-side validated contract (observations /
  hypotheses / uncertainties mandatory, no invented severity). Without a key:
  explicit 502 refusal, "AI visual analysis not available", the photo
  stays an attachment and the analysis continues on the text.
- Multi-problem splitting: the "caniveau + lampadaires"
  (§8) description produces 2 parts (assainissement→reseaux, eclairage→voirie),
  unknown severity kept (test T30). DEV lexicon extended in a
  documented way (`assainissement` family, `lampadaires` plural).

## Tests

- `dart test/test_all.dart`: 161 assertions (engine, unknowns, uncertainties,
  unit persistence, Meta connector + api.meta.ai provider regression,
  media T28, image request body + visual contract T29, §8 demo T30,
  oracle T31, public security T32–T35).
- `dart test/test_exploratoire.dart`: 9 OK, 1 confirmed published limit
  (Q policy cliff).
- `python test/e2e_redemarrage.py`: 14 real restart checks.
- `python test/e2e_mongo.py`: 12 real MongoDB checks (main
  backend, 8 concurrent writes without duplicates, restart, collections).

## Known limits

- Exact optimiser ≤ 9 known S1..S4 incidents (guard, explicit 400 error).
- Single-machine persistence: local JSON file, no inter-process lock;
  do not run two servers on the same `data/`.
- Classic engine: borderline merges/splits flagged but not resolved
  semantically (that is the expected role of the META method, not verified here).
- AI visual analysis: implemented and wired, but no real inference
  executed in this environment (no Meta key); to prove on Windows
  via docs/SERVER_END_TO_END_RUNBOOK.md. Without a key: explicit message.
- Audio/video: NOT undertaken (explicit P2 decision) — no fake
  transcription or fake video understanding; future features.
- Frontend really tested in the browser, no automated JS harness.
