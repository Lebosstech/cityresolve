# CityResolve — Submission Pack (draft, not submitted)

Track proposed: Indie Developer. Theme proposed: Build for Your World.
Status: Level 1 — Idea only. Confirmatory protocol: NOT FROZEN.
All numbers below are DEV (fictitious) results unless stated otherwise.
No real municipal impact is claimed. No superiority over Ushahidi or any
other platform is claimed. No submission has been sent.

## A. Project presentation (English, for the portal form)

### Problem
Cities receive messy citizen reports: free text, photos, locations, times.
One report can describe several distinct problems. A grouping system that
keeps only one main label per report can silently drop the second problem,
so a broken streetlight next to a pothole may never reach a team.

### Solution
CityResolve turns citizen reports into structured, prioritised incidents.
It splits each report into atomic ORIGIN:FAMILY units, groups units into
distinct incidents, scores severity (S) and exposure (E), routes work with
one shared optimiser, simulates the plan, and revises it only when new
information justifies a change. A severity-5 (S5) incident is never
dispatched to ordinary teams: it triggers immediate human escalation.

### How CityResolve works
1. Reports in: text and location, with unknowns kept as unknown
   (severity/exposure are never inferred from the category).
2. Multi-problem split: one report can yield several units, so the
   secondary problem survives grouping.
3. Reconciliation: a classical deterministic grouping is the reference;
   Meta AI (Muse Spark, via the Meta Model API) proposes structured
   extraction and report matching, with justifications and uncertainties.
   No AI grouping is accepted as truth just because the model proposed it.
4. Planning: one exact optimiser for CLASSIQUE and META, with teams,
   skills, constraints, unassigned incidents and infeasibility reasons.
5. Simulation and revision: the plan is simulated (cost, time, budget
   violations, robustness); new information is scored by an oracle that
   revises the plan only above a threshold, otherwise keeps it stable.

### Why Meta AI is used
Meta AI does the judgement work that fixed rules do badly: reading a
report in free text, extracting the problems it actually describes,
flagging missing or contradictory information, proposing matches between
reports, and justifying a grouping. The classical method stays as a
transparent, reproducible baseline, so the demo can show where the two
methods agree and where they differ.

### What has actually been tested
- Unit tests on the current main code: 119 PASS, 0 FAIL; exploratory
  suite: 9 OK, 1 confirmed limit (the Q=0 budget cliff, a published
  behaviour, not a hidden bug).
- DEV seed 7 (20 reports, 8 true incidents): classical grouping,
  split grouping, plan (5 tasks), simulation.
- Split grouping on DEV: 11 groups, one report present twice
  (electricity + lighting) — the secondary problem survives.
  Classical grouping alone covered 5/9 incidents on the multi-problem
  DEV set, split grouping 9/9. DEV only, not a general proof.
- S5 toy scenario: S5 incident escalated, never dispatched.
- Injection after a plan: oracle says "keep the plan" (gain +0.0 < 5.0),
  demonstrating that not every new report should trigger a revision.
- Justified revisions, verified on DEV seed 7 (VM, main code):
  R1 team down (N1): PLAN-1 (all tasks on equipe-2, planned Q 60.98)
  → injection team_down equipe-2 → PLAN-2 (all tasks on equipe-1,
  planned Q 50.16; reseaux incidents I3/I5/I7 unassigned because
  equipe-1 lacks that domain). Simulated Q stays 0.0 after revision
  (realised budget 123.8 > 120) — the revision was necessary because
  the team disappeared, NOT because Q improved.
  R2 new S5 (N3-S5): a declared severity-5 report creates incident I9,
  triggers human escalation, and creates NO new plan by design.
  A Q-gain revision (N2) was attempted once and returned U
  (gain +0.0) — not demonstrated, not fabricated.
- Real Meta calls (not stubs): Muse Spark 1.3 via api.meta.ai, 9 models
  listed; a 3-call cost pilot (mean 5.5 s, 672 tokens per small call)
  and Phase 4 real calls (~20 s, ~3,670 tokens per call). The API does
  not return a monetary cost, so no money cost is stated.

### Split benefit vs Meta contribution — kept separate on purpose
- Split benefit (deterministic, no Meta involved): the secondary
  problem survives grouping. DEV evidence: 5/9 incidents covered
  without split, 9/9 with split, on the multi-problem DEV set. This
  is a grouping-mechanics result, not an AI result.
- Meta contribution (actually demonstrated): structured extraction
  with unknowns kept as null, justified match proposals with
  uncertainties, and disagreement cases against the classical baseline.
  Phase 4 results are mixed and reported as such: on HARD pairs Meta
  F1 0.80 vs a synonym baseline 0.90 (that baseline was written knowing
  the test pairs, so it is not an independent validation); on
  MISLEADING pairs Meta F1 0.57 vs classical 0.40 vs synonyms 0.50,
  with no statistical power. On DEV seed 7, Meta did NOT improve
  allocation over classical (same planned Q, same simulated Q 0.0).
  Better grouping F1 does not imply better allocation — that
  distinction is part of the demo.
- What Meta has NOT demonstrated: image segmentation (SAM 3.1
  untested), any gain on held-out data, any real-city impact.

### Limitations (stated plainly)
- Level 1 — Idea. The confirmatory protocol is NOT frozen: the Q cliff,
  the 10% gain threshold (unjustified), the 65/35 weights and the strict
  certainty rule (95% CI lower bound > 10%) are all unfrozen.
- A power study found the strict certainty rule almost impossible at
  60 scenarios unless the true gain exceeds ~28% (38.5% power at a true
  gain of 20%); 10% of outputs counted as Q=0 cut power to 2.3%.
- No independent held-out evaluation has been run; sets A and B are
  not built and must never be used for development.
- Image segmentation (SAM 3.1) is untested; no image has been processed.
- The demo uses fictitious DEV data and a local 5×5 km grid map, not a
  real city map. MongoDB resilience (reconnect/fallback when MongoDB
  drops) is a known fragility.
- The interface is in French in the current build; this pack and the
  video narration are in English for the international jury.

### Future potential
If the confirmatory evaluation (after a frozen protocol, on held-out
sets, with an independent semantic baseline) ever shows a real gain,
the same pipeline could be piloted with a real municipality on real
reports — with human escalation for critical cases kept mandatory.
Until then, CityResolve is a demonstrable DEV prototype, not a product.

## B. Reproducible demo script (DEV only, no held-out sets)

Prerequisites (Windows machine): server running from E:\cytsense\app,
MongoDB coherent, MODEL_API_KEY entered in the PowerShell session only,
then "Verify Meta" in the interface. If Meta is unconfigured, show the
classical + split path only and say so — never simulate an AI result.

1. Dashboard: load DEV seed 7 (20 reports, 8 incidents). Show the DEV
   banner and the fictitious local map.
2. Reports: add one report by hand; note it is outside ground truth,
   so no metric is claimed for it.
3. Group CLASSIQUE: show the groups, then group DÉCOUPÉ: show 11 groups
   and the report present twice (electricity + lighting). State the
   DEV numbers (5/9 vs 9/9 on the multi-problem set) and that they are
   DEV only.
4. META: run a real extraction on one report (severity null when not
   expressed — nothing invented), then a real Meta grouping; show the
   justifications, uncertainties and any disagreement with CLASSIQUE.
   If CLASSIQUE scores better, show it.
5. Plan: run the shared optimiser; show teams, tasks, unassigned
   incidents and infeasibility reasons.
6. Simulate: show the simulated outcomes, the budget violation and
   Q 0.0 on seed 7, and explain the Q cliff honestly.
7. New information, three cases in order:
   (a) Stability (U, verified): inject an ordinary report after the
   plan; the oracle keeps the plan (gain +0.0 < 5.0).
   (b) Justified revision R1 (N1, verified): inject team_down for
   equipe-2; show necessity N1, PLAN-1 → PLAN-2, planned Q
   60.98 → 50.16, and the simulated Q staying at 0.0 — revision
   necessary, not a Q gain.
   (c) S5 escalation (N3-S5, verified): inject a declared severity-5
   report; show incident I9, human escalation, and NO new plan.
   A Q-gain revision (N2) is NOT part of the demo: one attempt
   returned U and no reproducible N2 case was found.
8. S5: load the S5 toy scenario; show the escalation and that the S5
   incident is never dispatched. State clearly that the system does not
   replace emergency services.
9. Close on limits: Level 1, protocol not frozen, DEV only.

## C. Video capture plan (to be shot on the Windows machine, real UI)

- Length: to be confirmed from the portal (UNVERIFIED — do not assume
  3 minutes until the portal says so).
- Narration: English, from section A above, shortened to the demo steps.
  Suggested narration (read slowly, one sentence per shot):
  "Cities receive messy citizen reports, and one report can hide two
  problems. CityResolve splits each report, so the second problem
  survives. Classical grouping is our transparent baseline. Meta AI
  reads the report, extracts what is actually there, and justifies its
  matches — unknowns stay unknown. One optimiser plans the work for
  both methods. On this demo, the simulated plan breaks the budget,
  and we show that honestly. When a team goes down, the plan is
  revised because it must be, not because the score improved. A
  severity-five incident is never dispatched: it goes straight to a
  human. This is a development prototype. The confirmatory protocol
  is not frozen, and no real-city impact is claimed."
- Shots: the 9 steps of section B, in order, on the real interface.
  No mockups, no simulated inference, no fictitious maps presented as
  real. The DEV banner and the fictitious-grid note must stay visible.
  Show the split groups, the plan before and after the team-down
  injection, the N1 justification, the S5 escalation, and the U
  stability case. Show a worse score when it occurs.
- If capture tools are unavailable on that machine, deliver this script
  and the narration text instead of claiming a video exists.

## D. Code and documentation (for the submission)

- Repository: Lebosstech/cityresolve (private; the submission must use
  whatever link/extract the portal requires — UNVERIFIED).
- Launch: `dart test/test_all.dart`, then `dart bin/server.dart
  --port 8080`, then open http://127.0.0.1:8080 (Windows path
  E:\cytsense\app). Requires Dart SDK and, for full persistence, MongoDB;
  without MongoDB the server falls back to explicit JSON storage.
- Meta model actually used: Muse Spark 1.3 via https://api.meta.ai/v1
  (server-side key only, never in the browser or in Git).
- Verified features, tests and limits: see SUIVI_SOUMISSION.md and
  sections A–B above. No secret is included in any file.
- Existing project documentation: PROTOCOLE_V1.md (pre-validation),
  ANNEXE_V1_2.md, phase-confirm-harness (harness verified on DEV only),
  Cahier_des_charges_CityResolve_2026-11-03.md (new drafting, 3 Nov 2026,
  corrected the same day, Level 1, protocol not frozen).

## E. Submission — NOT SENT

Everything above is prepared text. The final submission is reserved
to the owner: it requires the owner's confirmation of the portal fields,
the track and theme, the repository link/extract, and the video, and
the owner's explicit go-ahead. Do not present this pack as submitted.
