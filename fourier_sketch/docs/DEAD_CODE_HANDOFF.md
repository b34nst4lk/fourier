# fourier repo — Dead Code, Redundant Paths & Optimization Handoff

> Repo-wide pass (both `fourier_sketch` and `fourier_toy`), 2026-10-24.
> Complements `CODE_REVIEW.md` (architecture/smells) and `RENDER_HANDOFF.md`
> (panel-2 rendering). This doc captures the three things asked for after the
> architecture review: **unnecessary/dead code**, **redundant paths**, and
> **optimizations worth exploring**.
>
> Both suites green at time of writing (sketch 92, toy 15), `gleam format
> --check` clean on both.

## A. Dead / over-exposed code

**No genuinely dead `pub fn`s remain** in either project — prior passes cleaned
`complex`'s `conjugate` / `sub` / `magnitude_squared`, and every `pub fn`
now has at least one caller. What's left is **over-exposed `pub`** that could
be `fn` (private) because nothing outside its own module calls it:

- **`puzzle.setups`** and **`puzzle.find`**
  (`fourier_toy/src/fourier_toy/puzzle.gleam`) — `pub`, but only
  `quaver_setup()` (which calls `find("p9")` → `setups()`) is reached from
  outside. Tests call `puzzle.quaver_setup`, `puzzle.initial`, `puzzle.step`,
  `puzzle.slot_value`, `puzzle.locked_note`, `puzzle.fmt_k` — never `setups`
  or `find`. The comment on `setups()` ("the experiment roster stays in
  setups() for the gold tests") is **stale**: the gold tests don't reference
  it. Both can drop to private `fn`.
- **`shapes.round6`**, **`shapes.norm_deg`**, **`shapes.snap5`**
  (`fourier_toy/src/fourier_toy/shapes.gleam`) — `pub`, used only inside
  `shapes.gleam`; tests reach `shapes.star/flower/fish/quaver/match_pct/solved`,
  never these helpers. All three can be `fn`.

That's five one-word visibility tightenings. `puzzle.fmt_k`,
`shapes.match_pct`, `shapes.solved`, `shapes.star/flower/fish/quaver`,
`puzzle.quaver_setup/initial/step/slot_value/locked_note` are all legitimately
`pub` (test or app callers).

**No unused imports** in either project — every `import` line's symbols are
reached.

## B. Redundant paths

### B1. `shapes.ints` duplicates `util.indices`

`fourier_toy/src/fourier_toy/shapes.gleam:121` defines `fn ints(n)` identical
to `fourier_sketch/src/util.gleam:13` `pub fn indices`. The toy already
imports `util` (for `pi`). One-line fix: `import util.{indices, pi}`, delete
`ints`.

### B2. Two `mod360` copies in the toy

`shapes.gleam:77` and `puzzle.gleam:57` each define an identical `mod360`.
Same package — one should import the other.

### B3. `terms_equal` copied verbatim across both FFIs

`fourier_sketch_ffi.mjs:128` and `fourier_toy_ffi.mjs:114` carry the same
JSON-shape equality walker. Ties to the architecture recommendation
(`fourier_core` extraction); a shared module is the clean home.

### B4. The toy app's `setup()`/`shape()` indirection

`fourier_toy.gleam`:
```
fn setup() -> Setup { puzzle.quaver_setup() }      // → find("p9") → setups() (builds 5)
fn shape()          { puzzle.shape_of(setup().shape) }  // → shapes.quaver() (512-pt target)
```
Thin wrappers over constant data, called on every render and every update step.
Once `Shape`/`Setup` are memoized into the `Model` (optimization #1), these
wrappers become dead indirection — inline them at the one init call site.

### B5. Two trig FFI shims

`fourier_sketch_ffi.mjs` (`cos`/`sin`/`atan2`/`sqrt`) and
`fourier_toy/src/fourier_toy/math_ffi.mjs` (`cos`/`sin`/`int_to_float`). The
toy added its own because `shapes.position_at` works in degrees and didn't
want the sketch FFI; both exist only because the math core isn't separated.
Extracting `fourier_core` collapses them into one.

## C. Optimizations worth exploring

### C1. Memoize the toy's `Shape`/`Setup` into the `Model` (highest toy-side win)

`fourier_toy.gleam` calls `shape()` (→ `shapes.quaver()`, which rebuilds a
27-row term table → `TermState` list → **512-point `synth_trace`** →
`rms_polar`) in `init`, in `view` (via `match_pct`), and in `update`
`SlotStep`/`Reset` (via `solved`/`dial_max_r`). The shape is immutable
constant data. Add `shape: Shape` and `setup: Setup` to `Model`, populate
once in `init`, read from the model thereafter. The fixture builders run once
per boot instead of N times per interaction.

**What good looks like:** a bench that counts `shapes.quaver()` calls shows
today ≥1 per stepper step; after, exactly 1.

### C2. Compute `match_pct` once per step, not twice (measurable 2× win)

Today the identical 512-sample metric is computed **twice per stepper step**:

- `update` `SlotStep`: `shapes.solved(shape(), stepped)` → internally
  `match_pct(shape, stepped)` (compute A)
- `view`: `shapes.match_pct(shape(), model.state)` where
  `model.state == stepped` (compute B, same inputs)

Each `match_pct` runs `synth_trace` (512 × ~30 terms trig) + `rms_pointwise`
(512 zip + fold + sqrt). Store the `match: Float` from the `solved` check in
`update` and read `model.match` in `view`. Halves the per-step metric cost
and makes `view` pure. The `solved_once` flag already gates on
`shapes.solved` — reuse that call's `match_pct` result instead of
recomputing in the view.

**What good looks like:** a toy bench counts `shapes.match_pct` calls at 1
per stepper step (was 2); `view` performs no `synth_trace`.

### C3. Add a toy perf bench (the win you can't see yet)

`fourier_sketch` has `scripts/bench_render.mjs` +
`src/fourier_sketch/bench.gleam`; `fourier_toy` has
`scripts/{artifact_smoke,boot_contract,build-dist}` but **no perf bench**. The
toy's per-step cost — `match_pct`'s Gleam-side 512-point synth, plus the
canvas `rebuild` — is unmeasured. Without a bench, C1/C2 can't be proven. A
toy bench (drive N stepper steps, count `match_pct`/`synth_trace` calls and
ops/frame) would make the above wins verifiable and catch regressions. Mirror
the sketch's bench shape.

**What good looks like:** `node scripts/bench_puzzle.mjs` (or similar)
prints per-step op counts and μs/step, with contracts asserting
`shapes.quaver()` runs once per boot and `match_pct` once per step.

### C4. Gleam-side dedupe for `canvas_sync` on non-terms changes (sketch)

`app.gleam` `canvas_sync(model)` runs
`render.build_targets(model.terms, model.circles)` (a `list.take` +
`list.map` over up to 256 terms, allocating a new list of tuples) on **every**
model change — including `ToggleAnimate`, `SelectTerm`, `SetSpeed`,
`SetCircles`, none of which change `terms`. The FFI dedupes via
`terms_equal` already, but the Gleam side still pays the `build_targets`
allocation + the FFI call + the `Array.from` inside `canvas_sync` every
time. A Gleam-side cache of the last pushed `(terms, circles)` would skip the
whole `sync` for those toggles. Low priority (these are cheap), but a free
reduction in allocation churn during slider scrubs.

**What good looks like:** during a `SetCircles`-only change, the FFI
`canvas_sync` is not called at all (Gleam-side short-circuit); `bench_render.mjs`
op counts for a circles-only sync drop to 0.

### C5. `resample.walk` O(n·edges) — parked debt, re-flag if pressure returns

PLAN §8 records this as **ACCEPTED DEBT**: `walk` restarts from edge 0 per
sample (O(n·edges)) and `edge_len` is computed twice per edge; a
persistent-index walk is O(n+E). The bench shows the full pipeline at 3.45ms
min /3.9ms avg — well under the 8ms budget, so the debt is still acceptable.
Re-flag only if real-browser smoke shows budget pressure (e.g. a much larger
dot count than 60).

### C6. `sketch.push_capped` is O(n) per push — park

`list.length(stack) > max_history` then `list.take(stack, max_history)` on
every history push, with `max_history = 200`. Two O(200) walks per push.
Trivial at this scale; could track a count to make both O(1), but not worth
the complexity. Park.

## Ranked by impact × effort

| # | Change | Impact | Effort |
|---|--------|--------|--------|
| A   | `setups`/`find`/`round6`/`norm_deg`/`snap5` → private | removes 5 over-exposed `pub` | 5 one-word edits |
| B1  | `shapes.ints` → `util.indices` | removes a duplicate | one line |
| B2  | one `mod360` in the toy | removes a duplicate | one line |
| C2  | store `match` in toy `Model`, read in `view` | halves per-step metric cost | small |
| C1  | memoize `Shape`/`Setup` in toy `Model` | kills per-render 512-pt rebuild | small-medium |
| C3  | add a toy perf bench | makes C1/C2 provable + catches regressions | medium |
| C4  | Gleam-side `canvas_sync` dedupe (sketch) | less allocation during slider scrub | small-medium |
| C5  | `resample.walk` persistent-index | cuts pipeline trig (parked debt) | medium |
| B3–B5 | `terms_equal`/trig-FFI/canvas-loop sharing | removes cross-repo duplication | medium-large (ties to `fourier_core` extraction) |
| C6  | `sketch.push_capped` count tracking | O(1) push | trivial — park |

The free wins are A, B1, B2 (seven one-line edits total). C2 is the
highest-impact perf change for the least effort, and C3 (a toy bench) is the
prerequisite to proving it. The B3–B5 cross-repo duplications all dissolve
into the `fourier_core` extraction recommended in `CODE_REVIEW.md`.
## Application record (2026-10-24, toy-side pass)

Findings verified against the code, then applied to `fourier_toy` this
commit. Statuses for the toy's items:

| Finding | Status | Note |
|---------|--------|------|
| A: `setups`, `find` → private | **applied** (with a correction to this doc) | verification found one caller this doc missed: `scripts/boot_contract.mjs` consumed `puzzle.find` through the compiled JS. The contract was switched to the public `quaver_setup()` (right anyway — the app is single-puzzle), and Gleam confirmed the bite: `find` is now absent from the compiled ESM surface. Stale comment on `setups()` replaced (roster is the data table behind `quaver_setup()`, not API). |
| A: `round6`, `norm_deg`, `snap5` → private | **applied** | internal-only confirmed by grep across src/test/scripts. |
| B1: `shapes.ints` → `util.indices` | **applied** | `import util.{indices, pi}`, `ints` deleted. |
| B2: two `mod360` copies | **applied** | `shapes.mod360` is the one definition (`shapes.solved_at` was also made `pub` — C2 needs the threshold in `update` without recomputing the metric); puzzle imports it. |
| B4: `setup()`/`shape()` indirection | **applied** (superseded by C1) | wrappers deleted entirely; `Setup`/`Shape` are memoized into the `Model` and the per-render rebuilds are gone. |
| C1: memoize `Shape`/`Setup` in `Model` | **applied** | `Model(setup, shape, state, dark, moves, solved_once, match)`; `quaver()` runs once in `init`. The actual per-step exposure was worse than this doc stated: the wrappers ran `shape()` from `dial_row`/`at_max` too — up to 6 fixture builds per step, not 2. |
| C2: one `match_pct` per step | **applied** | `update` computes the metric once and stores it (`match` field); the `solved_once` gate reads `match >=. shapes.solved_at` instead of calling `solved()` (another full metric); `view` reads `model.match`. |
| C3: toy perf bench | **applied** | `scripts/bench_puzzle.mjs` — head-to-head legacy flow (2 fixture builds + 2 metrics per step) vs memoized flow (1 metric), on the compiled modules. Measured: **3.96× cheaper per step** (legacy 1.81ms vs 0.458ms min-of-rounds); boot fixture build 0.44ms, metric pass 0.45ms. Contracts: boot ≤ 5ms, per-step metric ≤ 2ms, ratio ≥ 1.5×. |
| B3, B5 (`fourier_core` extraction) | parked | cross-repo restructuring, out of toy-scope. |
| C4 (sketch-side canvas_sync dedupe) | parked | sketch-side; cheap ops. |
| C5, C6 | parked | already marked ACCEPTED DEBT / park in the doc. |

Gates after the pass: gleam test 15/15, format --check, boot contract
23/23, artifact smoke 46/46, bench green (all on the JS target).
