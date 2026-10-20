# fourier_toy — Plan of Record (DRAFT, pending grilling)

> Phase 2 of the `workspace/projects/fourier/` umbrella (see
> `fourier_sketch/docs/PLAN.md` §7, where the seed definition lives).
> Decisions marked **PROPOSED** have NOT been user-ruled yet — they are
> defaults written so the doc is complete. A grilling session replaces
> PROPOSED with locked, or edits with rationale. Silent drift is banned.

## 0. Product definition

A tuning puzzle, purely frontend, sibling app to fourier_sketch:

- A **target shape** (closed path) is decomposed into Fourier terms.
- The player gets the target's term **frequencies (k) locked**, but each
  term's **radius and phase start wrong** and are adjusted with sliders.
- The player's term configuration is reconstructed and overlaid on the
  target; a **score** (pointwise path distance, normalized) tracks progress.
- Solving = driving the score to the threshold. The educational point:
  *radius = size of the circle, phase = starting angle* — and amplitude
  ordering ("big circles first") becomes something you can *feel*.

Core mode only for v1: radius + phase sliders, k locked (orthogonality ⇒
per-term ground truth = the target's true DFT coefficient — `terms.compute`
gives it, so the puzzle is fair by construction and self-checking).

## 1. Decisions

| # | Decision | Choice | Status |
|---|----------|--------|--------|
| 1 | What is the target | Preset shapes (star, heart, wobbly circle, …), same fixture role as fourier_sketch presets | PROPOSED |
| 2 | Import player-drawn targets from fourier_sketch | NOT in v1 — needs the parked shareable JSON export format; shelf §7 | PROPOSED |
| 3 | Term bank composition | Target's own top-M terms by amplitude, ks locked from the target; no decoy zero-radius terms in v1 | PROPOSED |
| 4 | Bank sizes | Difficulty picker: {3, 6, 10, 16} terms | PROPOSED |
| 5 | Sliders | Radius: 0 → 2 × (bank's largest true radius), continuous. Phase: 0–360°, degrees (radians never shown) | PROPOSED |
| 6 | Initial slider values (the puzzle setup) | Radius: 50% of max; phase: 0° — visible mismatch, one-gesture improvement, never accidentally solved | PROPOSED |
| 7 | Scoring metric | RMS pointwise distance over the period, normalized by the target's RMS polar radius about the path centroid; displayed as a match % = (1 − score) | PROPOSED (exact normalizer is a TDD §3 contract item) |
| 8 | Sample count for scoring/curves | N = 512, same as sibling | PROPOSED |
| 9 | Solved gate | match ≥ 95% → "solved" badge + ground-truth reveal (show true radius/phase per term) | PROPOSED |
| 10 | Reveal | One button, shows true values and can apply them ("show me the solution") — applies only on explicit press | PROPOSED |
| 11 | Layout | Two panels: left = SVG overlay (target ghost dashed, reconstruction solid), right = slider bank (per-term k label, radius, phase, readouts); header = preset picker + difficulty + score % | PROPOSED |
| 12 | Dark theme + visual family | **Parchment cartography family** (rethemed 2026-10-20 with the sibling — user directed one house look from projects/cartographer; supersedes "dark theme, sibling palette genes") | PROPOSED |
| 13 | Animation | None in v1 — static overlay compare. RAF/animated play mode = shelf | PROPOSED |
| 14 | Persistence | None in v1 (no localStorage) — puzzle state is throwaway; best-score/recent-shelf later | PROPOSED |
| 15 | FFI line | Pure Gleam only: SVG/DOM via Lustre, math via fourier_sketch core. No canvas, no RAF, no storage FFI — the FFI modules of the sibling stay untouched | PROPOSED |
| 16 | Toolchain | Gleam → JavaScript only; every build/test/run passes `--target javascript` (no Erlang on this box — recorded hard constraint) | locked (environment) |
| 17 | Math core reuse | Path dependency on `../fourier_sketch`; core modules imported bare (`complex`, `resample`, `dft`, `terms`). Proven linking via scaffold smoke (3/3) | locked (verified) |
| 18 | Process | TDD red→green for all logic-carrying code (presets fixtures, bank extraction, scoring, puzzle state); view layer = thin translator + smoke checklist | locked (house rule) |
| 19 | Commits | Per phase, matching PROGRESS.md | locked (house rule) |
| 20 | Deployment | Single-file dist bundle (house pattern from the fourier_sketch post-mortem) → jacks.im/toys/fourier-toy/ | PROPOSED |

## 2. Architecture

- Package `fourier_toy` beside `fourier_sketch` in the umbrella; path dep
  consumes the math core. The sibling app's UI/FFI code is NOT imported.
- Lustre app for state; panels are declarative SVG/DOM. No FFI expected in
  v1 (decision #15), which also sidesteps the module-MIME class of bugs the
  sibling hit at deploy.
- New modules (plan):
  | Module | Responsibility | TDD |
  |--------|----------------|-----|
  | `src/presets.gleam` | target-shape fixtures: named closed dot paths | ✓ unit |
  | `src/bank.gleam` | extract puzzle bank: top-M terms from target, ground truth hidden, slider clamps/ranges | ✓ unit |
  | `src/score.gleam` | pointwise distance, RMS, normalization, match %, solved gate | ✓ unit + properties |
  | `src/puzzle.gleam` | state model: set radius/phase, reset, apply-truth, current score, solved flag | ✓ unit + properties |
  | `src/app.gleam` | Lustre Model/Msg/update/view | smoke checklist |

## 3. Scoring contract (the TDD §3)

- Both curves sampled at the **same phase points**: t_n = n/N, n = 0..N−1,
  N = 512.
- Target curve: `resample.resample_closed(target_dots, N)` — arc-length even,
  starts at first dot (sibling guarantees).
- Reconstruction curve: `terms.position_at(bank_player_terms, t_n)` — no
  resample needed; it is parametric.
- Player terms reconstruct with **signed-k chain semantics identical to the
  sibling's epicycles**, so a revealed truth exactly reconstructs the target
  (< 1e−9 RMS — a testable identity AND the fairness guarantee).
- Distance d_n = euclidean(target_n, reconstruction_n).
- Score = sqrt(mean(d_n²)) / R̄, R̄ = RMS polar radius of target curve about
  its centroid. Match % = max(0, 1 − score). Solved ⇔ match ≥ 0.95.
- Degenerates: empty bank → no score (UI empty state); zero-amplitude target
  (all dots identical) → no score, preset flagged unusable.

## 4. UI spec (v1 sketch)

- Header row: preset select, difficulty {3,6,10,16}, match % readout, reset,
  reveal.
- Left panel: 512-point SVG paths, target dashed ghost, reconstruction solid;
  fixed viewBox square, letterboxed like the sibling.
- Right panel: one block per term, amplitude-descending: `k=+3` label, radius
  slider + readout, phase slider (0–360°) + readout.
- Solved: badge + per-term ground truth inline revealed; "apply truth" (one press) snaps sliders,
  optional and never automatic.
- No persistence, no animation, no keyboard shortcuts beyond DOM defaults.

## 5. Quality gates

- Unit/property tests (gleeunit, JS target): bank extraction = sibling
  `terms.compute` top-M identity; truth application reconstructs target <
  1e−9 RMS; score invariants (identical config ⇒ 100%, zeroed config ⇒ 0%,
  score range [0, 1]); slider clamp properties; reset/undo-free state model
  (deliberately simple: no undo in v1 — sliders are self-undoing).
- Perf: trivial (N=512 once per slider input, no per-frame loop). Bench only
  if smoke shows drag lag.
- Smoke checklist (manual): slider scrub feels live, reveal honesty, preset
  switching resets bank, difficulty switch resets bank, letterbox resize.

## 6. Phases

| Phase | Scope | Criteria |
|-------|-------|----------|
| 0 | Toolchain | gleam binary; JS build/test verified | (env — done) |
| 1 | Scaffold | gleam new + deps + path dep linking on JS target (3 smoke) | ✅ done (commit fffa7a4) |
| 1d | Plan of record | this file; PROPOSED → locked via grilling | draft committed |
| 2 | Puzzle core (TDD) | presets, bank, score, puzzle — RED suites then GREEN | ⬜ open |
| 3 | Shell + UI | lustre app, two panels, slider bank, score readout | ⬜ open |
| 4 | Delivery | README, single-file dist, deploy to /toys/fourier-toy/, final suite | ⬜ open |
| 5+ | Shelf | see §7 | ⬜ |

## 7. Shelf (parked, NOT v1)

- **Import fourier_sketch drawings as targets** — requires the shareable
  JSON export format parked in the sibling's PLAN §7; define the format then
  (versioned schema, sketch dots + optional term table).
- **Hard mode**: k tunable / choose frequencies from a pool.
- **Animated play mode** (RAF, sibling-style epicycles overlay).
- **Scoreboard/persistence**: best match per preset+difficulty (localStorage,
  versioned schema like sibling `store.gleam`).
- More presets (letters, animals, user gallery), streaks/gamification.

## 8. Links

- Sibling plan/progress: `../fourier_sketch/docs/PLAN.md`,
  `../fourier_sketch/docs/PROGRESS.md`
- Deployed sibling: https://jacks.im/toys/fourier-sketch
- Site deploy post-mortem (single-file bundle rule): sibling PROGRESS
  §"Deployment failure post-mortem"