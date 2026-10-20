# fourier_sketch — Code Review & Handoff

> Whole-codebase review, 2026-10-20. Framed as a cleanliness / simplicity /
> dead-code pass over the current `main` (no diff against a fixed point).
> Two axes, kept separate so one can't mask the other:
> - **Standards** — Fowler smell baseline (no `CODING_STANDARDS.md`/`CONTRIBUTING.md`
>   exists in this repo, so only the baseline applies) + general cleanliness.
> - **Spec** — `docs/PLAN.md` (plan of record) is the spec source; no issue
>   tracker is wired up.

All Standards findings are **judgement calls** (baseline smells are never hard
violations, and no documented repo standard exists to breach). Spec findings
are doc/code drift, not missing behaviour.

## Standards

### Dead code (confirmed unused — delete or annotate)

- **`complex.gleam`** — three `pub fn`s have zero callers in `src` or `test`:
  - `conjugate` (definition only)
  - `sub` (no `.sub` / `complex.sub` reference anywhere)
  - `magnitude_squared` (definition only)

  The DFT uses `add` / `mul` / `scale` / `exp_i`; `terms` uses `add` / `polar`
  / `to_xy` / `zero`. These three are leftover from a fuller complex API that
  was never exercised. **Delete**, or — if kept as a "math core" surface for
  `fourier_toy` — say so in a doc comment so a future reader doesn't read them
  as live.

- **`render.boot`** — `pub` but called only inside `render.sync` (no external
  caller). Drop to private `fn`.
- **`render.min_circles` / `render.max_circles`** — used only by
  `clamp_circles`. Fine to keep `pub` as named constants, but they are not
  part of any external contract.
- **`sketch.Snapshot`** — `pub` with a stale comment ("Public for the app
  layer's convenience") but `app.gleam` never references `Snapshot` (it goes
  through `sketch.dots` / `undo` / etc.). Make it private.
- **`store.schema_version`** — `pub` but used only inside `store.gleam`. Private.
- **`spark.amplitude` / `spark.mid`** — `pub` but used only inside
  `spark.path`. `columns` / `box_height` *are* used by `app.gleam` (legit
  `pub`). Tighten the two internal ones.

### Duplicated Code (the strongest smell)

- **`indices(n)`** — the `list.repeat(Nil, n) |> list.index_map(fn(_, i) { i })`
  helper plus its "gleam_stdlib 1.0 has no list.range" comment is copied
  **five times**: `dft.gleam`, `resample.gleam`, `sketch.gleam`,
  `spark.gleam`, and `dft_test.gleam`. Extract one shared helper (a tiny
  `src/util.gleam`, or place it in one module and import). The test copy can
  stay if you want test-independence, but the four `src` copies should
  collapse to one.
- **`const pi = 3.141_592_653_589_793`** — duplicated in `dft.gleam`,
  `sketch.gleam`, `terms.gleam`, and `dft_test.gleam`; `spark.gleam` has its
  own `two_pi`. One shared `pi` constant removes four copies.
- **Trig/sqrt FFI shims** — `cos` / `sin` / `sqrt` / `atan2` `@external`
  pairs are redeclared across `complex.gleam`, `resample.gleam`,
  `sketch.gleam`, `spark.gleam`. Gleam idiom tolerates module-local externals,
  but four modules each redeclaring `cos` / `sin` against the same
  `fourier_sketch_ffi.mjs` is the same shape in four places. Centralising the
  FFI in one module (e.g. `src/math_ffi.gleam`) and re-exporting is the
  cleaner option. Judgement call — flagged for simplicity.

### Mysterious Name

- `let fn_ = int.to_float(n)` in `dft.gleam` and `resample.gleam` — `fn_`
  reads as "function"; it's `n` as a float, named to dodge the `fn` keyword.
  `n_f` or `nf` says what it holds.
- `go_sum` in `dft.gleam` — generic tail-recursive accumulator;
  `term_accumulate` or `rotate_sum` would say what it does (walks samples
  multiplying a rotating twiddle).

### Minor cleanliness

- **`fourier_sketch_ffi.mjs`** — the `anim` object literal omits two fields
  that are later read/written dynamically: `io` (touched in `canvas_boot` via
  `anim.io.disconnect()` / `anim.io.observe(el)`) and `centers` (allocated via
  `anim.centers || (anim.centers = [])` in `draw`). Declaring `io: null` and
  `centers: []` up front makes the state shape legible in one place.
- **`fourier_toy/src/fourier_toy.gleam`** — `main` just prints
  `"Hello from fourier_toy!"`. Expected for a scaffold (PROGRESS phase 2
  open), but it's placeholder, not product. Not actionable yet.
- `dft.inverse` and `terms.position_at` are `pub`, exercised only by tests
  (and, for `position_at`, the sibling smoke). Both are documented as such —
  keep, but they're test-driven public API. A one-line "public for the
  sibling/tests" note on `position_at` would stop a future reader assuming
  the app calls it (the canvas draws analytically in JS and never calls
  `position_at`).

### Standards summary

~14 findings. Worst: the **5-way `indices` / 4-way `pi` / 4-way trig-FFI
duplication** (one shared util module clears the bulk of it), closely
followed by **3 genuinely dead `pub fn`s in `complex.gleam`**.

## Spec

*Light pass — the review was framed as cleanliness/dead-code. Spec source:
`docs/PLAN.md`.*

### Implemented but drifted from the written spec

- **PLAN §2 module map lists `src/animation.gleam`** ("time→chain pose, TDD
  ✓ unit"). **That module does not exist** — its responsibility
  (`position_at`) was folded into `terms.gleam`. Functionally fine, but the
  module map and §8 (which references the animation module's role) describe a
  file that isn't there. Update the module map or restore the split.
- **Decision #6 says** "click=add, drag=move, **click existing dot=remove**".
  The implementation deletes via **right-click** (button 2) and makes
  left-click-on-dot **grab/drag**. That's a deliberate, better UX choice
  (drag and delete can't both be left-click), but the locked-decision table
  still states the old behaviour. PLAN §4 also says "delete affordance (`✕`
  or alt-click, decided at implementation)" — the decision was made
  (right-click) and the README documents it, but PLAN #6 wasn't edited with
  the rationale. Per the doc's own rule ("Changes require editing this file
  with the rationale, not silent drift"), this is drift.
- **PLAN §4 says storage key `localStorage["fourier_sketch/v1"]`.**
  `store.gleam` uses key `"fourier_sketch"` with the version *inside* the
  payload (`{"v":1,...}`). Intent (versioned schema) is met; literal key
  differs. Worth a one-line note in §4.
- **PLAN §4 / root README say "Dark-only palette (traces glow on dark)".**
  Decision #15 rethemed to parchment cartography, but §4's prose and the
  **root `README.md`** ("dark-only, glowing traces") still describe the dark
  theme. Stale doc text — `fourier_sketch/README.md` and `index.html` are
  correct; the root README and PLAN §4 aren't.
- **`spark.gleam`** is not in PLAN §2's module map, though decision #16
  clearly calls for sparklines. Add it to the table.

### Missing or partial

- Nothing in the locked decisions is unimplemented for `fourier_sketch` — all
  19 decisions have corresponding code. `fourier_toy` is scaffold-only
  (phases 2–4 open), which matches its PROGRESS; not a spec gap for this
  review.

### Scope creep

- None observed. The bench module (`fourier_sketch/bench.gleam`) and
  `scripts/bench_render.mjs` are explicitly sanctioned by decision #13 / §5
  perf budget. The FFI thermal guardrails go beyond the written spec but are
  a performance/reliability win documented in PROGRESS — not creep.

### Spec summary

5 findings, all **doc/code drift** rather than missing behaviour. Worst: the
**`animation.gleam` module listed in the plan that doesn't exist** (folded
into `terms.gleam` without updating the module map), plus the
**right-click-delete vs PLAN #6 "click=remove"** wording that should be
reconciled per the plan's own no-silent-drift rule.

## Suggested fix order (smallest impact → largest)

1. Delete the three dead `pub fn`s in `complex.gleam`; tighten the other
   over-exposed `pub`s (`render.boot`, `sketch.Snapshot`, `store.schema_version`,
   `spark.amplitude`/`spark.mid`). Pure visibility changes, no behaviour move.
2. Add `io: null` and `centers: []` to the `anim` literal in
   `fourier_sketch_ffi.mjs`.
3. Extract one shared `indices` (+ `pi`) into a tiny `src/util.gleam`; import
   from the four `src` modules. Leave the test copy if you value
   test-independence from internals.
4. Rename `fn_` → `nf` and `go_sum` → something honest, in `dft.gleam` /
   `resample.gleam`.
5. Reconcile the doc drift: update PLAN §2 module map (drop
   `animation.gleam`, add `spark.gleam`), edit PLAN #6 + §4 to record the
   right-click-delete decision and the actual storage key, and fix the
   "dark-only" wording in root `README.md` and PLAN §4.
6. (Judgement call) Centralise the trig/sqrt FFI in `src/math_ffi.gleam` and
   re-export, removing the four-way shim duplication.

Each step is independently shippable; none are blocked by another.