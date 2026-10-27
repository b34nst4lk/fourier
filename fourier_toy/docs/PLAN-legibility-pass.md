# PLAN — Legibility pass (the 2026-10-27 playtest answers)

> Plan of record for `fourier_toy`. Product decisions are **user-ruled**
> (2026-10-27 session, from the spike playtest — verbatim notes in the
> umbrella-root `docs/playtest-2026-10-27.md`); §4 is the TDD spec the coding
> subagent works against. Lands AFTER `PLAN-fetch-first-boot.md` on the same
> branch (both rewrite smoke sections; serializing avoids contract churn).

## 0. What changes

Five small features, all in the established visual language, answering the
playtest's comprehension and satisfaction complaints:

1. **Press-highlight** — stepping any column pulses its canvas circle: the
   question "which circle is mine?" is answered by the interaction itself.
2. **Blue arm trail** — the k column's arm leaves a fading sweep, so
   rotation speed (the dialed value) becomes legible motion.
3. **Comet loop closure** — the comet draws the full lap; the tail meets the
   head (the open seam read as "an unfinished stroke").
4. **Bigger corner chips** — theme/reset chips grow to real touch targets.
5. **Solve reveal** — at the ≥95% crossing the comet snaps solid over the
   dashed target for a beat: the shape becomes yours, visibly.

Extras-dash is **deferred** (the playtest flagged "circles beyond the third
term", but dark-mode extras are already near-invisible; dashing without
brightening would hide them further — the press-highlight answers the same
question by pulsing only the dialed circles). Revisit after the next
playtest with a brighter dark-mode neutral if extras still read as dials.

## 1. Decisions (user-ruled, 2026-10-27)

| # | Decision | Ruling |
|---|----------|--------|
| 1 | Press-highlight | Approved. Pulse the pressed slot's canvas circle + its column ring, ~600ms, ordinal ink. |
| 2 | Blue arm trail | Approved. K column only (phase has the marker, radius has size). |
| 3 | Comet closure | Approved. TAIL_FRAC 0.98 → full lap; the alpha ramp stays (40% tail → 85% tip). |
| 4 | Corner chips | Approved. 16px → 20px icons + padding to a ≥40px hit target; icon-only + aria unchanged. |
| 5 | Solve reveal | Approved. A one-shot full-lap solid comet for ~2s at the solve crossing, fired with the existing solve effect; board-only, no column changes, no text. |
| 6 | Extras-dash | **Deferred** with the dark-mode visibility question (above). |

## 2. Design

`src/fourier_toy_ffi.mjs` + `src/fourier_toy/ffi.gleam` + view/CSS:

- **Pulse**: new FFI export `canvas_pulse(slot)` (ffi.gleam binding); the
  view's `slot_step` effect batch calls it alongside `push_terms` (hold-repeat
  ticks re-arm it naturally — each synthesized click pulses again). The draw
  loop, for `PULSE_MS ≈ 600` after the pulse: the board's term-`slot` circle
  strokes at full ordinal ink with a thicker width (1.5 → ~3) and an
  ease-out radius swell (→ ~1.15×); the column's ring brightens for the same
  window. No payload changes.
- **Trail**: in `draw_column` for the k kind only: ~6 alpha-stepped arc
  segments (≈0.15 → 1.0) over the last ~45° behind the arm tip (the comet's
  chunk pattern in miniature). The phase/radius columns draw no trail.
- **Closure**: `TAIL_FRAC = 0.98` → `1.0`; chunk boundaries already end at
  the pen (the sibling's exact-boundary lesson), so the lap closes with the
  ramp intact.
- **Chips**: `.chip .icon` 16px → 20px; `.chip` padding to a ≥40px target;
  both themes.
- **Reveal**: new FFI export `canvas_reveal()`; the view fires it from the
  same solve-moment effect list that POSTs (once per crossing — the
  counter-freeze boundary already guarantees once). Draw loop for
  `REVEAL_MS ≈ 2000`: the comet strokes full-alpha (no ramp), width ×1.5,
  over the dashed target; afterwards the ordinary ramp returns.

## 3. Contracts

- The FFI surface grows two exports (`canvas_pulse`, `canvas_reveal`) — pure
  draw-state effects on the shared clock; the payload, kinds, palettes and
  storage are untouched.
- The solve POST's timing is unchanged (the reveal is a sibling effect, not
  a gate on it — a failed POST still re-sends on next boot, `reported`
  unchanged).
- No wire, attempt, or backend interaction.

## 4. TDD spec — required tests and expected outcomes

Working agreement: RED first, seen failing for the intended reason; GREEN;
all gates green before the commit. Tolerances follow the boot contract's
1.3px house pin.

### `scripts/boot_contract.mjs` — new sections (RED first)

- `pulse window`: after `canvas_pulse(1)`, frames within ~600ms stroke the
  term-1 circle wider/brighter than baseline (width > baseline, alpha up),
  the other circles unchanged; frames after the window return to baseline
  (op deltas zero). The column ring shares the beat.
- `trail on k only`: the k column draws ≥6 trail segments with alpha
  monotonically increasing toward the tip; phase/radius columns draw none
  (per-column op deltas).
- `full-lap comet`: the comet's first chunk begins where the lap starts —
  coverage pins replace the 0.98 seam; the alpha ramp pins (tail ≥ 40%,
  tip ≤ 85%, tail dimmer than tip) stay green untouched.
- `reveal window`: after `canvas_reveal()`, comet strokes carry alpha 1.0
  and width > baseline for ~2000ms, then the ramp pins return; the dashed
  target's ops are unchanged through the window.

### `scripts/artifact_smoke.mjs` — new pins (RED first)

- Click a phase glyph → the term-0 circle's ops show the pulse (emphasized
  stroke recorded); hold-to-repeat re-arms the pulse per tick (count > 1).
- Solve a board → the reveal window ops recorded (full-alpha comet) AND the
  solve POST still fires exactly once (the existing solve pin co-verifies).
- Shipped-CSS: `.chip .icon` ≥ 20px and the chip's hit target ≥ 40px.
- All existing pins stay green (score-vs-core, disables, daily flows).

Gates: smoke + boot contract + `gleam test --target javascript` (42) +
`gleam format --check` + bench budgets + dist byte-reproducible; then the
spike playtest round 2 (the plan's own acceptance: the three comprehension
complaints — dial↔circle link, extra circles, blue readability — should not
recur verbatim).

## 5. Parked

- Extras-dash (with the dark-mode neutral question).
- An onboarding overlay / first-visit hint (the press-highlight may make it
  unnecessary; the ordinal-vs-semantic color question stays ruled: ordinal).
- Semantic color legend (playtest open question #1 — ruled ordinal, the
  pulse is the explicit ordinal cue).
- Score/win-condition redesign for "solved by understanding" beyond the
  varied-starts answer (playtest open question #3 — revisit only if round 2
  still flags it).