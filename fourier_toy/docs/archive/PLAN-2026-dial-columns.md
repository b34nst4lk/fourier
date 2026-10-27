> **Archived (2026-10-27)** — shipped: the dial-column rework is merged to
> main (33ba774) and serving production (https://jacks.im/toys/doodle/), with
> the unlisted spike kept at /toys/doodle-dev/ for continued testing. All
> phases' acceptance criteria held; the device check was satisfied by the
> 2026-10-27 spike playtest. Follow-up work ruled by the user out of that
> playtest (varied daily starts, fetch-first boot + last-loaded cache, the
> legibility pass) proceeds under new per-feature plan documents; this plan is
> retired and kept for history.

# PLAN — Dial columns (the purely-visual dial rework)

> Per-feature plan of record (2026-10-26 convention). Product decisions in
> this plan are **user-ruled** through a grilling session on 2026-10-26.
> This document is written as the **TDD spec for the coding subagent**: §4
> enumerates the required tests and their expected outcomes; a phase is done
> when its RED suite has been seen failing for the intended reason, the
> implementation is GREEN, and the full gate set passes. Expected values in
> §4 are acceptance criteria — if one cannot be reproduced, STOP and report;
> never adjust the test to match the implementation. The superseded row UI's
> rulings live in `docs/archive/PLAN-2026-single-quaver-v2.md`.

## 0. What changes

The stepper **rows** (label + value readout + locked-note + text +/− buttons)
are replaced by three **visual dial columns** under the board canvas — one per
dialed term, in chain order. Each column is its term's canvas epicycle in
miniature, animated on the board's own clock, with one controlled indicator
per dial kind. **No text anywhere in the columns**: the numbers, the "term N"
headers and the locked-field notes are all gone; the board (comet vs dashed
target) is the precision instrument, the columns are reinforcement.

The dial *state machine is untouched* — phase ±5° wraps, radius ±2% of
`dial_max_r` clamped 0–200%, k ±1 clamped ±16 — so the difficulty, the
solve gate (≥95%), the counter-freeze semantics and all attempt/telemetry
behavior are exactly what ships today.

## 1. Decisions (all user-ruled, 2026-10-26)

| # | Decision | Ruling |
|---|----------|--------|
| 1 | Column anatomy | **Faithful epicycle mirror (A)**: every column draws circle + rotating arm + pen tip at its term's k-speed and locked phase; plus one controlled indicator per kind. Rejected the minimalist reading (B) — all three columns must read as the same machine with one knob each. |
| 2 | Radius cap | **No cap — the 200% state clamp stays.** The 100% cap proposal was rejected ("keep things simple first"): no semantic change, no clamp-test churn. The visual is a linear map instead: ring diameter ∝ r, **200% = fills the circle space, 100% = half of it**, 0% = empty. Nothing can overflow because the ceiling maps to the space exactly. |
| 3 | Ring sizes | **Phase & k columns: fixed ring at 50% of the circle space.** **Radius column: variable**, empty → full space over its 0–200% range (= the phase ring's size at 100%, = full space at the ceiling). Overrides honest proportions for the k column: its radius is locked, so ring size carries no gameplay information, and honest size is a 5–13% speck on real shapes (star 5%, flower 6%, quaver 13% of space) that cannot legibly show speed. The k column keeps matching the canvas epicycle's **motion** — angle, speed, phase; only its ring diameter is normalized. |
| 4 | Text in the columns | **None. No numbers, no headers, no term labels** — purely visual language. The readouts were redundant with the board; k speed-reading was never reliable anyway. `slot_value`, `locked_note`, `kind_class` retire. The score bar is NOT a dial and keeps its text (Match %, "· N changes", solved ✓). |
| 5 | Term 4 (fixed slot) | **Dropped.** No fixed slots exist anymore: every shape's term 4+ moves into `extras` (baked identically into target and comet — same math, same score, same gate; term 4's only presence becomes its faint extra epicycle on the board). The quaver fallback becomes a 3-dial puzzle. |
| 6 | Ink contract | **Ordinal, not kind-driven**: the 1st dialed column is red, 2nd yellow, 3rd blue, always — color answers "which wheel in the chain?", nothing more. **The symbology determines the kind**: start-dot = phase, ring size = radius, arm speed = k. Supersedes the kind-ink wire contract (`puzzle.kind_code` + FFI PALETTES keyed on it + `kind-*` CSS): the board canvas re-inks ordinally so a column and its circle always agree. For the standard arrangement the colors are visually identical; the change is contract semantics. |
| 7 | Phase direction | **Up = +5° = clockwise on screen** (down = anticlockwise). The marker must sit exactly where the pen is at t=0, so it inherits the math's convention; the pen and marker can never disagree. |
| 8 | Button glyphs | Kind-specific, motion-matching: phase = **rotate-cw / rotate-ccw**, radius = **expand / contract** (diagonal arrows), k = **fast-forward / rewind**. All inline stroke SVG (house icon pattern — nothing a platform can emoji-ize), icon-only, aria-labeled. The reset chip re-glyphs to **skip-back-to-start** (resolves its rotate-ccw collision with phase-down). |
| 9 | Column count | **Locked at exactly 3.** A puzzle dials exactly the first 3 terms; anything else is a fallback. The ≤6-term ceiling is recorded as product fact only — N>3 rendering, ordinal inks 4–6 and backend N>3 generation are **parked** (§5). |

## 2. The design, precisely

Column = [glyph button] → [circle space ~104px] → [glyph button], under the
canvas, three across the ~400px content width. Circle space height is an
implementation constant (rings ~52px at 50%), confirmed on a real phone in
the device check.

- **Shared clock**: the columns animate on the board canvas's own RAF loop —
  same `t`, same SPEED (0.125 laps/s), 30fps cap, DPR ≤ 2. "Matches the
  circle on the canvas" is literal: same angle, same speed, same phase, same
  ink.
- **Every column** draws: the ring, a rotating arm from center to tip, and a
  pen dot at the tip, at the term's k speed (direction by sign; **freezes at
  k = 0** — honest: the term stops rotating) starting at the term's phase.
- **Phase column**: fixed 50% ring + a **static start-marker dot** on the
  edge at the dialed phase — the pen's t=0 position. The marker is a lone
  dot; the pen carries the arm, so the two stay distinguishable when they
  coincide. Buttons move the marker ±5° (up = clockwise on screen).
- **Radius column**: ring diameter linear in r — empty at 0% (no ring, no
  arm, nothing), = the phase ring's size at 100%, fills the space at the
  200% ceiling. Arm/pen animate at the locked k/phase all the while.
- **k column**: fixed 50% ring; the arm's rotation speed is the feedback —
  visibly faster per click, blur toward ±16, frozen at 0.
- **Disabled edges** (grayed glyphs as today): radius at 0% and 200%, k at
  ±16; phase never (wraps). Hold-to-repeat is unchanged — the document-level
  click-synthesis driver covers the new buttons for free, and the
  touch-action / user-select guards already live on the `button` rule.
- **Accessibility baseline**: buttons keep aria-labels naming the action
  ("increase phase", …). No value-announcement layer is built (stated once,
  veto possible): a value readout cannot make a shape-matching puzzle
  playable without sight.

## 3. Contracts and consequences

- **Board vocabulary**: exactly 3 dialable terms, kinds ∈ {phase, radius, k}.
  `puzzle.initial` takes exactly 3 patches. `DialFixed` retires from
  puzzle's public vocabulary (wire keeps a private fixed marker for
  normalization, below).
- **Wire decode (`wire.gleam`)**: old backend documents (the deployed
  `standard_dial_arrangement` [phase, radius, k, fixed]) keep working with
  **no lockstep**: each "fixed" slot's truth term is appended to `extras`
  (a fixed-correct term IS an extra) and its patch is dropped; this holds
  for a fixed slot at ANY position, not just slot 4. After normalization the
  document must be exactly 3 dialable terms, else `Error(Nil)` → quaver
  fallback.
- **Attempt schema v2**: `v` bumps 1→2, `state` is a 3-term array. A stored
  v1 document decodes to `Error(Nil)` → fresh start (the sanctioned
  version-bump retirement; only pre-change attempts are affected). Same-day
  v2 attempts resume exactly as today; solve/abandon POSTs and the
  `reported` re-send logic are untouched.
- **Shapes (`shapes.gleam`)**: every fixture's `dial` becomes the top-**3**
  terms; the former 4th term moves into `extras`. The synthesis term set is
  IDENTICAL (top-4 = top-3 + extras[0]), so target traces, `rms_polar`,
  `dial_max_r` and every match value are unchanged — the gold suite re-pins
  the split, not the numbers.
- **Test roster**: the P6–P10 experiments retire as board data (the shipped
  interface is the quaver; P10's 4-dial setup violates the 3-lock). The
  roster may collapse to `quaver_setup()` alone (dead-code discipline);
  step-logic coverage continues via the direct kind tests.
- **Ordinal ink**: positions 1–3 keep today's red/yellow/blue in both themes
  (the standard arrangement makes ordinal ≡ kind visually); the FFI
  PALETTES, the page CSS and the canvas circles all switch from
  `kind_code` to ordinal lookup. Extras on the board stay neutral wash.
  The `canvas_terms` payload still carries the per-slot KINDS — behavior
  (which symbology a column draws) needs them; only the color lookup
  changes.

## 4. TDD spec — required tests and expected outcomes

Working agreement for the coding subagent: **per phase**, land the RED suite
first, run it, and see it fail **for the intended reason** (record the RED
count); then implement; then the phase's gates must be green before the
phase commit (whose message records the RED numbers, house style). Never
commit an implementation whose RED suite was not demonstrated first. Where a
constant must be re-derived, derive it ONLY by running the current pipeline
before touching the module, and pin the observed value — never invent a
number. If an expected outcome below cannot be reproduced, stop and report.

### Phase 1 — core (Gleam; gates: `gleam test --target javascript`, `gleam format --check`)

#### 1a. `test/fourier_toy_test.gleam` — top-3 fixtures (RED)

- `star_dial_top3_gold_test`: `shapes.star().dial == [TermState(1, 27.574653, 270.0), TermState(-4, 6.5871, 270.0), TermState(6, 2.927629, 270.0)]`; `extras == [TermState(-14, 0.537771, 270.0)]` (length 1).
- `flower_dial_top3_gold_test`: `flower().dial == [TermState(1, ≈14.3, 0.0), TermState(-5, ≈5.46, 325.0), TermState(7, ≈5.46, 35.0)]` (same approx tolerances as today); `extras == [TermState(-11, 0.78, 0.0)]` (length 1).
- `fish_dial_top3_gold_test`: `fish().dial == [TermState(-1, 26.07, 255.0), TermState(1, 16.27, 90.0), TermState(-2, 7.51, 340.0)]`; `extras` length **26**, head `TermState(2, 4.9, 180.0)`.
- `quaver_dial_top3_gold_test`: `quaver().dial == [TermState(-1, 17.97, 265.0), TermState(1, 11.3, 305.0), TermState(-3, 4.68, 260.0)]`; `extras` length **26**, head `TermState(3, 2.83, 195.0)`.
- `dial_max_r_unchanged_test`: per fixture, `dial_max_r == {star: 27.574653, flower: ≈14.3, fish: 26.07, quaver: 17.97}` (term 1 is the biggest under both splits).
- **Unchanged metric pins stay green untouched** (they are the proof the split is score-neutral): `star_target_is_traced_not_synthesized_test` — star match-at-truth still ∈ (96.5, 98.5); `synthesizable_shapes_solve_to_about_100_test` — flower/fish/quaver still > 99.9.

#### 1b. `test/fourier_toy_test.gleam` — puzzle 3-patch board (RED)

- `quaver_setup_is_three_dials_test`: `quaver_setup().dials == [DialP, DialR, DialK]`; `quaver_setup().patches == [PhaseDeg(355.0), RPct(73.0), KSet(-5)]`.
- `initial_resolves_three_patches_test`: `puzzle.initial(quaver, quaver_setup().patches) == [TermState(-1, 17.97, 355.0), TermState(1, ≈0.73·17.97 = 13.1181, 305.0), TermState(-5, 4.68, 260.0)]` (approx 1e-9 on the radius); length 3.
- `quaver_start_is_unsolved_gold_test`: `match_pct(quaver, initial(…)) == 0.0` (k −5 vs truth −3 clamps the metric to 0 — the live seam check recorded the same number for the served start).
- `flower_p7_start_test` (replaces the retired P10 flower start): `initial(flower, [PhaseDeg(90.0), RPct(72.0), KSet(5)]) == [TermState(1, ≈14.3, 90.0), TermState(-5, ≈0.72·14.3, 325.0), TermState(5, ≈5.46, 35.0)]`, and `match_pct < 95.0`.
- `fish_p8_start_clamps_to_zero_test` (rewritten to 3 patches): `initial(fish, [PhaseDeg(345.0), RPct(72.0), KSet(-6)])` → `match_pct == 0.0` (unchanged expected value — the synthesis set is identical).
- **Step contracts stay green untouched** (the state machine does not move): `phase_step_wraps_test` (0 ↔ 355), `radius_step_has_floor_and_ceiling_test` (floor 0, ceiling 2·max_r — the rejected cap, now pinned as a decision), `k_step_clamps_test` (±16, and k 1→0).
- **Deletions** (compile is the test): `DialFixed`, `kind_code`, `kind_class`, `slot_value`, `locked_note` and their helpers (`fmt_k`, `pct`, `deg`) are gone from `puzzle.gleam`; `locked_note_names_the_locked_fields_test`, `kind_ink_is_keyed_on_the_dial_kind_test`, `star_initial_p3_match_gold_test` (a 4-slot JS-prototype experiment, unrepresentable under the 3-lock) and the P10 flower start are deleted. The setups roster collapses to `quaver_setup()` (dead-code discipline).

#### 1c. `test/attempt_test.gleam` — schema v2 (RED)

- `a_fresh_attempt_encodes_the_documented_document_test`: `encode(fresh())` == exactly `{"v":2,"date":"2026-10-26","state":[{"k":-1,"r":17.97,"phase":355},{"k":1,"r":11.3,"phase":305},{"k":-3,"r":4.68,"phase":260}],"moves":[],"count":0,"solved":false,"reported":false}` (3-term `terms()` fixture; v:2).
- `an_attempt_round_trips_test`: encode→decode identity on a played v2 attempt (moves, count, date, state, solved, reported).
- `a_v1_document_is_stale_test`: the v1 4-term literal (the current test's exact document) → `Error(Nil)` — a stale attempt means fresh start, never a crash.
- `the_state_must_be_three_terms_test`: v2 docs with a 4-term or 2-term state → `Error(Nil)`; `{"v":3,…}` → `Error(Nil)`; `{}` / `""` → `Error(Nil)`.
- `whole_number_terms_read_back_as_floats_test` (v2 spelling): `{"r":18}` reads back as `18.0`.
- **Unchanged, stay green**: moves-in-play-order, the 500 move cap (count 520 vs list 500), `record`/`mark_reported` transitions, `solve_body` literal (`moves:[{slot,dir}…]`), `abandon_body` literal (`moves: N`). `storage_key` stays `j-att`.

#### 1d. `test/wire_test.gleam` — normalization + exactly-3 board contract (RED)

- `the_served_puzzle_decodes_to_a_setup_and_a_shape_test` (old-format `star_json`, unchanged fixture): `Ok`. Expected after normalization: `setup.dials == [DialP, DialR, DialK]`; `setup.patches == [PhaseDeg(0.0), RPct(73.0), KSet(4)]`; `shape.dial == [TermState(1, 27.574653306648354, 270.0), TermState(-4, 6.0, 270.0), TermState(6, 3.0, 270.0)]` (the first 3 served terms); `shape.extras == [TermState(-14, 0.5, 270.0), TermState(2, 0.25, 90.0)]` (served fixed term FIRST, then the served extras); `dial_max_r == 27.574653306648354`; `rms_polar` == the `from_parts` derivation (unchanged expected number); target/centroid unchanged.
- `the_start_resolves_against_the_served_shape_test` (rewritten): `initial` on the normalized doc == 3 slots `[TermState(1, 27.574653306648354, 0.0), TermState(-4, ≈0.73·27.574653306648354, 270.0), TermState(4, 3.0, 270.0)]`; no fourth slot.
- `a_new_format_document_decodes_directly_test`: a 3/3/3 document (dials `["phase","radius","k"]`, 3 dial terms, 3 patches, no fixed) → `Ok` with the same shape identity rules.
- `a_fixed_slot_anywhere_normalizes_test`: a document with arrangement `["phase","fixed","k","radius"]` → `Ok`; `dials == [DialP, DialK, DialR]`; `dial` == the served slots 1/3/4 terms; `extras` == [slot-2's term, ..served extras]; `patches` == slots 1/3/4's patches.
- `a_real_board_starts_unsolved_test`: unchanged expected outcome — the normalized start's match < 95.
- **Refusals, all `Error(Nil)`**: a 4-dialable document (P10-style `["phase","radius","k","radius"]` with 4 dial terms + 4 patches) — the 3-lock; a 2-dialable document; a 6-dialable document (the ceiling exists but the board does not — fallback); patches-length mismatch after normalization (incl. the empty-patches fixture); unknown patch kind; `"none"`/`"error"` envelopes, `""`, an HTML error page (existing pins). `whole_number_coordinates_read_as_floats_test` stays green (int-or-float spelling, unchanged).
- Implementation notes for `wire.gleam`: the private fixed marker lives in wire only; `"keep"` stays a parsable patch kind (fixed slots carry it; a dialable Keep is harmless and allowed, as today); the `slots` constant becomes 3.

### Phase 2 — FFI columns + ordinal ink (JS; gates: rewritten `node scripts/boot_contract.mjs`, then Gleam gates still green)

`scripts/boot_contract.mjs` — rewritten RED against the current FFI (expected: the new sections fail, the retained board sections pass). All geometry checks compute expectations from the same math the FFI uses (`angle = 2πkt + φ`), tolerance 1.3px (house pin tolerance):

- `column canvases bind like the board`: three column canvases stash their payload unconditionally pre-mount (cold-load), a late boot binds and paints them (the blank-board lesson generalized to 4 canvases), an element swap rebinds. Retained board pins (payload stash, DPR transform args, pen-on-curve, comet-overlays-target at truth, alpha ramp) stay green.
- `fixed rings`: phase and k columns stroke their ring at **0.5 × circle space** (ratio pinned, not px).
- `radius ring is linear`: radius column ring radius == `(r / (2 · dial_max_r)) × space` for probe states r = {0, 0.5·max, max, 2·max}: at `0` **no arc and no pen ops are drawn for that column** (op-count 0); at `max` the ring equals the phase ring; at `2·max` it equals the full space.
- `arm matches the canvas chain`: for probe times t, each column's drawn arm/pen position matches the independently computed term-i chain point (same t, same k/φ) within 1.3px, for all three columns.
- `start-marker sits at the phase`: the phase column's lone marker dot is drawn at `(cx + R·cos(φ), cy + R·sin(φ))` within 1.3px; the marker is a dot without an arm (distinguishable from the pen, which carries the arm).
- `k0 freezes`: with k = 0 on the k column, two frames at different t draw the identical arm angle.
- `ordinal ink`: column 1/2/3 stroke colors are the palette's index-0/1/2 entries in BOTH themes (light `#c8321e`/`#8a6d00`/`#1f5fae`, dark `#e05a4a`/`#ffd93d`/`#5aa0e8` — the current term colors, re-keyed from kind to ordinal); the board's term circles use the same ordinal hexes; extras stay neutral wash.
- `one clock`: all four canvases repaint from the same RAF tick (30fps cap, DPR ≤ 2 unchanged); no rebuild when terms are unchanged (dedupe pin retained).

### Phase 3 — view + CSS (Gleam + `index.html`; gates: Gleam gates, boot contract, format)

`src/fourier_toy.gleam` — the rows die, the columns are born (RED evidence here is Phase 4's smoke DOM pins; the module change is covered by them):

- `board_view` renders 3 columns under the canvas — each `[glyph button ↑][canvas][glyph button ↓]`, no text nodes; `.rows` → `.cols` grid (3 × 1fr), circle space 104px.
- Glyphs per kind as inline stroke SVG: phase rotate-cw/rotate-ccw, radius expand/contract, k fast-forward/rewind; up = +, down = −. aria-labels exactly: `increase phase`, `decrease phase`, `increase radius`, `decrease radius`, `increase k`, `decrease k`.
- `at_min`/`at_max` unchanged semantics on the new buttons (radius 0/200%, k ±16; phase never disabled).
- The reset chip re-glyphs to skip-back-to-start (aria-label `reset to start` unchanged).
- `index.html`: `kind-*` classes → ordinal classes; button glyph sizing;
  existing `touch-action`/`user-select` guards on `button` remain
  (hold-to-repeat + anti-loupe).
- Deletions: `dial_row`'s text machinery (labels, readouts, notes) and the
  "+"/"−" button text. The score bar, `changes_text` and `fmt1` stay —
  they are not dials.

### Phase 4 — artifact smoke rewrite (JS; gates: `node scripts/artifact_smoke.mjs` GREEN, boot contract, Gleam gates, `node scripts/bench_puzzle.mjs` budgets re-verified, `./scripts/build-dist.sh` byte-reproducible)

`scripts/artifact_smoke.mjs` — rewritten RED against the current dist bundle. Canvas stubs handle 4 canvases with per-canvas op counting. Expected outcomes:

- **DOM contract**: exactly 3 dial columns under the board; ZERO text readout nodes (no `.row`, `.val`, `.id`, `.sub`, no "term N" strings anywhere in the app); 6 icon-only glyph buttons (each contains an svg, no text) with the exact aria-labels above; the reset chip's svg carries the skip-back bar+triangle geometry (not the rotate-ccw arc).
- **Edge disables**: radius contract disabled at r=0 (drive down from start 73%: 37 steps of −2% reach 0%); expand disabled at 200% (64 steps of +2% from 73%); k fast-forward disabled at +16 (21 steps from −5), rewind disabled at −16 (11 steps); phase buttons still enabled after a full wrap (72 steps).
- **Score vs core**: per-step match % equals the core-computed ground truth (the smoke imports the compiled core, existing pattern); dial-home solve from the start lands ≥ 95 with the solved badge; counter freeze at first solve (extra steps don't count); reset restores start + counter semantics (pre-solve zero, post-solve record kept).
- **Hold driver on glyph buttons**: hold 700ms ⇒ n repeats with score matching step-for-step; the release click swallowed; a quick tap steps exactly once (existing pins, new buttons).
- **Theme**: toggle flips both palettes and the body attribute (existing pins); columns follow.
- **Daily flows on schema v2**: fetched boot paints 3 columns from the served (old-format) document via normalization; same-day v2 stored attempt resumes dials/count/solved badge exactly; a **stale v1 stored attempt boots fresh** (counter 0, no crash); solve-once-report; reset-abandon and new-day abandon POSTs; offline/500/malformed → quaver fallback with zero POSTs (existing S8a–h scenarios, v2 fixtures).
- **Quaver fallback**: boots into 3 columns, score matches core from the first paint.

### Phase 5 — ship (gates: all of the above + live)

- Full gate set green; dist byte-reproducible from the tree.
- Deploy via the blog pipeline (hermetic clone of `prototype`); verify the live URL serves the new bundle (grep the served HTML for the new markers — ordinal palette keys, column canvases, glyph svgs); md5 the artifact against the local build.
- Device check on a real phone: column reachability (~210px block), ring legibility, hold-to-repeat on glyphs, no double-tap zoom.
- `docs/PROGRESS.md` gains the phase rows; this plan is updated with any drift (silent drift is banned).

## 5. Parked (out of scope, recorded)

- N > 3 rendering (auto-fit grids, wrapped column blocks).
- Ordinal inks for positions 4–6.
- Backend generation of N > 3 puzzles (a `toy_admin` plan when it happens).
- Any value-announcement accessibility layer.

## 6. Rationale notes (overruled alternatives, for the record)

- **100% radius cap (rejected)**: would have been safe (dial truth is
  amplitude-sorted, so term 2 truth < 100%; the only patch generator emits
  73%) but changes dial semantics and the overshoot room for no product
  gain; the linear map makes the existing 200% ceiling render honestly.
- **Honest k-column proportions (rejected)**: correct as a mirror,
  illegible as a dial — the k column's job is speed legibility on every
  day's shape, and a 5–13px ring cannot deliver it. Motion still matches
  the canvas; only the ring's diameter is normalized.
- **Numeric readouts (rejected)**: precision lives on the board (comet vs
  target); the columns carry perception, and text would re-introduce the
  chrome this rework removes.
- **Kind-driven ink (superseded)**: the old contract made color answer
  "what does this dial do?"; the new design answers that with symbology,
  freeing color to be pure ordinal identity — which also makes "introduce
  new terms" (up to the recorded 6 ceiling) a palette entry, not a contract
  rework.