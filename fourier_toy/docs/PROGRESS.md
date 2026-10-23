# fourier_toy — Progress

One row per phase. "Done" means every acceptance criterion is green and the
phase is committed. Sibling convention: see `../fourier_sketch/docs/PROGRESS.md`.

| Phase | Scope | Criteria | Status | Commits |
|-------|-------|----------|--------|---------|
| 0 | Toolchain | gleam binary; `gleam build/test --target javascript` verified Erlang-free | ✅ done | (env, not repo) |
| 1 | Scaffold | `gleam new` + lustre/json deps + `fourier_sketch` path dep; JS build green; linking proven by 3 smoke tests; repo init | ✅ done (3/3) | phase 1 commit |
| 1d | Plan of record | docs/PLAN.md drafted — product decisions marked PROPOSED, awaiting grilling; env/house rules already locked | 🟡 draft committed, §1 locks pending user session | docs commit |
| 2 | Puzzle core (TDD) | presets.gleam, bank.gleam, score.gleam, puzzle.gleam — RED suites then GREEN | ⬜ open | — |
| 3 | Shell + UI | lustre app: overlay SVG panel, slider bank, score readout, solved reveal | ⬜ open | — |
| 4 | Delivery | README, single-file dist bundle (house pattern), deploy to jacks.im/toys/fourier-toy/, final full-suite run + user browser smoke | ⬜ open | — |

## Notes

- Toolchain hard rule inherited from sibling: every build/test/run command on
  this box MUST pass `--target javascript` (no Erlang installed).
- Math core lands via path dependency `fourier_sketch = { path = "../fourier_sketch" }`;
  core modules are imported bare: `complex`, `resample`, `dft`, `terms` (they
  sit at the sibling package root). The sibling's UI/FFI/app code is NOT
  imported — fourier_toy defines all its own state, view, and modules.
- Scaffold smoke findings (recorded, then tolerated by tests):
  - gleeunit `should.equal` is exact — DFT zero-coefficients come out as
    ~1e-17, never literal 0.0 through the twiddle rotation; tolerance
    assertions required anywhere spectra are compared.
  - `err <. tol |> should.be_true` pipes the literal into the comparison —
    use `should.be_true(err <. tol)` call form.
  - `terms.position_at(full_terms, 0.0)` exactly equals the first dot only
    up to polar/argument round-trip error (~1e-15) — tolerance, not equality.
- Git identity is repo-local (jacksim / jacksim@localhost), matching sibling.
- Umbrella layout: `workspace/projects/fourier/` holds both repos; the
  umbrella itself is not versioned.
## Monorepo + GitHub (2026-10-20)

- Repo moved under the umbrella monorepo https://github.com/b34nst4lk/fourier
  (subtree import — full local history preserved). Path dep on
  ../fourier_sketch resolves unchanged inside the monorepo.
- CI: shared root workflow, JS-target truth; first real run caught format
  drift in this repo's test file — fixed.

## Prototype round (2026-10-23, branch `prototype`)

Four dial experiments against the sketch's star, deployed as one hash-routed
page (prototypes/), built single-file like the sibling. Rulings that shaped
it: (Q1) steppers, not sliders — k ±1 (signed, −16..16), phase ±5°, radius
±2% of MAX_R; (Q2) top panel = one overlay (dashed ghost target + solid
route-red current), not side-by-side; (Q3) feedback = aggregate only — one
match % (RMS pointwise / target RMS polar radius, the plan §7 metric), no
per-dial hints; solved at ≥ 95%.

Data integrity: proto.js is GENERATED from fourier_sketch's compiled pipeline
(star 10 dots → 512 resample → DFT → top-4: k=+1 r=27.57, k=−4 r=6.59, k=+6
r=2.93, k=−14 r=0.54; centroid (50,50) fixed in every synthesis; phases all
270°). Star of the process: an intermediate hand-written proto.js carried
fabricated coordinates (32768-saturation sentinels) — caught before any
commit by the out-of-span gate, regenerated from the script, and the gate is
now permanent. Verified: all four initial states below the solve gate
(−41.4 / −39.0 / 67.1 / −44.1%), truth = 97.69% (truncation-bound: a solved
board tops out there, not 100%), and the bundled artifact passes 16/16 jsdom
checks (routing, wrap, floor-disable, fixed slot, reset, match values vs
ground truth).

Finding for the feel session: under the pointwise metric the k lever is
all-or-nothing — a wrong frequency shows 0% match (clamped); only the
overlay's gap carries the partial-credit signal.

## Prototype 2 in Gleam (2026-10-23) — the JS round archived first

The JS experiments froze at tag `prototype-js-v1` and moved to
`prototype_js/` (deploy wiring superseded). v2 = the toy's own Gleam app:
TDD'd pure core (`shapes.gleam` fixtures + `puzzle.gleam` dial logic, 14
gold tests asserting byte-parity with the archived JS numbers — including
the k0-must-filter lesson: the sketch's terms.compute includes the
centroid, the JS generator filtered it and v2 had to match), then the
Lustre shell + a compact canvas/RAF/theme routing FFI ported from the
sibling's loop with its heat-audit guardrails (30fps cap, DPR≤2, dirty
gate, rebuild-cache dedupe). Rulings: always-on comet, 50% of sibling max
speed (0.125 laps/s), dashed target under the comet, extras summed into
the comet so the illustration matches the score exactly, in-app light/dark
toggle, PRKR experiment P10 included (all four terms dialed). Verified:
gleam test 14/14; jsdom artifact smoke 16/16 (routing, deterministic
starts, dial-home solve paths, solved badge, reset, theme toggle, micro
radius home). Boundaries: gleam lists cross the FFI as cons iterables —
every list normalizes with Array.from; tuples are arrays.

## v2 blank-board fix — second visual check (2026-10-23, branch `prototype`)

Symptom: cold-loading straight onto a board (deep link like `#p6`) left the
canvas blank; the dials/score ran fine. First probe during the check: a
try/catch around draw() with stack logging (the probe was removed again —
it swallowed errors that gates should catch; the loop is draw-safe with
normalized inputs, and the sibling's production loop has no such guard).

Root cause, verified in Lustre's runtime source
(`lustre/src/lustre/runtime/client/runtime.ffi.mjs`, constructor):
`this.#handleEffects(effects)` runs BEFORE `this.#render()` — init effects
fire before the first render mounts the canvas. Same for hashchange: effects
run synchronously while renders are RAF-deferred. So `sync_effect`'s pushes
arrived with no `#toy-board` in the DOM, and the FFI's old
`if (!anim.ctx && !ensure_boot()) return;` guard DROPPED the payload — a
later boot bound the canvas but had nothing to draw. The interrupted
`boot_retry` half-fix (armed on the working tree when the session paused)
booted the canvas but could not re-deliver the dropped shape/terms — the
board stayed blank.

Fix (the sibling's proven production pattern): payload stashes
UNCONDITIONALLY, boot is orthogonal. `canvas_shape`/`canvas_terms` always
assign + rebuild + dirty; `ensure_boot()` only binds canvas/ctx, with
element-change detection (backing-store dims reset on rebind so a fresh
300×150 canvas cannot survive a same-size rebind) and a single
self-terminating per-frame retry while no element exists. A late boot just
starts painting the stashed payload. The retry also covers a REMOUNT
(reconciler replaces the element); the artifact smoke shows the reconciler
in fact PRESERVES the canvas across board→board swaps, so the rebind path
is defensive robustness, not load-bearing.

New committed gates (the previous session's jsdom smokes were ad-hoc and
deleted — a deleted gate is not a gate):
- `scripts/boot_contract.mjs` (pure Node, zero deps, house bench pattern):
  16 checks over the boot/payload contract — cold-load pre-mount sync,
  dial repaint, element-swap rebind, home→board stash survival, headless
  upright. RED first (8/16 on the broken tree), then GREEN (16/16).
- `scripts/artifact_smoke.mjs` (jsdom + manual RAF queue + op-counting
  canvas stubs; evals the exact dist bundle as a classic script — esbuild
  emits no ESM syntax for this entry): 23 checks — cold-load paint
  (regression), score vs core-computed ground truth on every board, phase
  wrap, radius floor + disable, dial-home solve badge (star tops at
  97.7%), reset, theme mirror, home↔board routing, fixed-slot hiding,
  reconciler element preservation. jsdom has no layout engine: the canvas
  rect is stubbed to 300×300 or every circle hits the sub-pixel skip.
Gates: gleam test 14/14; gleam format --check; boot contract 16/16;
artifact smoke 23/23; dist byte-reproducible from the tree.
