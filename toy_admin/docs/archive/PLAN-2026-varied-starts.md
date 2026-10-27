> **Archived (2026-10-27)** — shipped: this plan's work is merged to main
> (66abb65, varied-starts via its own Phase 1+2) and serving production
> (https://jacks.im/toys/doodle/), with every phase's acceptance criteria
> green and the whole-repo review's findings fixed or recorded. Retired and
> kept for history; live plan work continues in new per-feature documents.

# PLAN — Varied daily starts (per-puzzle offset draw at save time)

> Plan of record for `toy_admin`. Product decisions are **user-ruled**
> (2026-10-27 session); §4 is the TDD spec the coding subagent works against.
> Companion plans: `../fourier_toy/docs/PLAN-fetch-first-boot.md` (the toy
> side of the daily loop) and `../fourier_toy/docs/PLAN-legibility-pass.md`.

## 0. What changes

Today every served puzzle starts at the same deterministic offsets: phase
+90°, radius 73%, k −2 (`derivation.standard_patches`). A player who plays
several days learns the recipe ("rotate −90, k +2") and stops solving by
understanding — the 2026-10-27 playtest's deepest complaint. This plan
replaces the fixed offsets with a **per-puzzle draw at save time**:

- The draw happens ONCE, when the puzzle's fixture is derived and saved.
- The drawn offsets are embedded in the served document (the `patches` field,
  exactly as today) — **every player playing the same day starts at the
  identical position** (the wordle property is preserved; nothing is
  per-player).
- Day-to-day the pattern varies, so no cross-day recipe is learnable.

The toy changes NOTHING — it already resolves whatever patches it is served
(`puzzle.initial`). The wire vocabulary, the fixture document shape, the
admin UI and the agent door are all untouched.

## 1. Decisions (user-ruled, 2026-10-27)

| # | Decision | Ruling |
|---|----------|--------|
| 1 | Granularity | **Per-puzzle at save time, never per-player.** The user's pushback ("would prefer everyone start at the same position") is satisfied by construction: the start is part of the published document. |
| 2 | Phase offset | Drawn on the 5° dial grid with magnitude in **[45°, 315°]** — at least a 45° turn from truth, either direction (315° ≡ −45°). 55 possible values. *(Amended 2026-10-27, the whole-repo review's drift finding: the offset itself is ≥45° and on-grid, but `snap5` runs AFTER the offset is added, so the OBSERVED turn — patch minus the off-grid truth phase — can round to as little as 42.5°. The ruling's intent — a clearly perceivable turn, never near-truth — holds, and the derivation test pins the observed floor at 42.5°; adjusting the snap order would re-derive the whole published calendar for an imperceptible 2.5°, so the ruling text takes the honest amendment instead.)* |
| 3 | k shift | Drawn nonzero from **{−3, −2, −1, +1, +2, +3}**; the `k_min` (−16) wall flip is preserved (a shift that would fall below the wall flips sign). |
| 4 | Radius | **Constant 73%** — the anchor the ring's meaning is built on; not flagged by the playtest, not varied. |
| 5 | Determinism | The draw is a **pure function of the puzzle** (a hash over its dial truth): same drawing → same patches (reproducible saves, deterministic tests); different drawings → different offsets. No RNG state, no OTP dependence. |
| 6 | Existing puzzles | **Not-yet-served puzzles are re-derived** through the new draw (their fixtures embed the new offsets). Already-served days keep what they served. The quaver fallback is untouched (it is not part of the daily sequence). |

## 2. Design

`derivation.gleam`:

- `standard_patches(dial)` becomes `varied_patches(dial)`:
  - `seed = fnv1a(dial)` — a small pure-Gleam FNV-1a over the dial rows
    flattened as ints: per row `[k, float.round(r *. 1_000_000.0), float.round(phase_deg *. 100.0)]`. The dial derives deterministically from the
    drawing, so this is a pure function of the puzzle.
  - Phase offset: `idx = seed mod 55`; `offset = 45 + 5·idx`;
    `PhaseDeg(snap5(phase_truth + offset))` (snap5 keeps the on-grid
    guarantee even after wrap).
  - k shift: `shift = k_shifts((seed / 55) mod 6)` over
    `[-3, -2, -1, 1, 2, 3]`; the wall flip generalizes today's `start_k`.
  - Radius: `RPct(73.0)` unchanged; slot 4 `Keep` unchanged (the toy
    normalizes the fixed slot away; the document shape stays as deployed).
- The retired constants (`start_phase_turn_deg`, `start_k_shift`) delete;
  `start_radius_pct` stays.
- `derive_fixture` calls `varied_patches(dial)` where it called
  `standard_patches`.

## 3. Contracts

- The served document (fixture_json) carries the SAME vocabulary — only the
  values differ. Encoder, decoder, admin UI, agent door: untouched.
- The TOY is untouched: it resolves served patches as data (`puzzle.initial`),
  and its gold tests already pin "a real board starts unsolved (< 95)".
- Ops: puzzles with `show_date` **after today** are re-derived by re-saving
  their own dots through the admin API (the save path re-derives the fixture,
  patches included). A probe verifies the change landed.

## 4. TDD spec — required tests and expected outcomes

Working agreement: RED suite first, seen failing for the intended reason
(record the count); then GREEN; gates green before the phase commit. Expected
values below are acceptance criteria — if one cannot be reproduced, stop and
report. Gates run in the established in-Docker loop (README §"faster
edit/test loop": the `toy-builder` image, bind-mounted, `gleam format --check
src test && gleam test --target erlang`).

### Phase 1 — the draw (TDD, `test/derivation_test.gleam` grows)

- `varied_patches_is_deterministic_test`: `varied_patches(dial)` twice over
  the star fixture → identical patch lists (the pure-function pin).
- `varied_phase_offset_is_far_and_on_grid_test`: for each of ≥6 probe
  fixtures: the phase patch differs from the slot's truth phase by
  `offset` with `offset` mod 360 ∈ [45, 315] AND offset mod 5 == 0 (before
  snap; the patch itself must be on the 5° grid by construction).
- `varied_k_shift_is_small_and_nonzero_test`: for each probe fixture:
  shift ∈ {−3..−1, 1..3}; the patched k differs from truth.
- `k_wall_flip_generalizes_test`: a dial with truth k = −15 and a drawn
  shift of −3 → patched k = −12 (the flip), still inside k_min.
- `radius_stays_anchored_test`: every probe's slot-2 patch is `RPct(73.0)`.
- `distinct_drawings_draw_distinctly_test`: across ≥6 probe fixtures, the
  set of (phase offset, k shift) pairs has MORE than one distinct member
  (guards a degenerate constant draw — with 330 combinations this cannot
  fail by chance).
- `fixture_round_trips_varied_patches_test`: a varied fixture
  encode→decode round-trips its exact patches (fixture_json untouched).

### Phase 2 — re-derive the not-yet-served puzzles (ops, live-verified)

- A small script (the `insert-drafts.sh` pattern: fence token from the env,
  posts through the admin API) re-saves each puzzle row with
  `show_date > today` — the save path re-derives the fixture with the new
  draw.
- Probe battery after: for ≥3 re-derived rows, `GET /api/admin/puzzles/<id>`
  shows patches that are NOT the old +90°/−2 signature, and at least two
  rows differ from each other.
- Gate: the Docker test suite green (unchanged by ops), the probe battery
  green, and today's puzzle still serving (untouched).

### Ship

`docker compose up -d --build` (the backend's deploy path), probe `/api/puzzle/today`
live through the tunnel — served patches unchanged in SHAPE, the future
calendar varied. No blog deploy: the toy is untouched by this plan.

## 5. Parked

- Varying the radius percent (the anchor stays; revisit if a playtest flags it).
- Emitting 3-slot documents from the backend (the toy's fixed→extras
  normalization is proven; a trivial future alignment).
- Difficulty-tiered draws (e.g. smaller |k shift| for "easy" days) — the
  draft calendar's easy→hard ordering is untouched by uniform variation.