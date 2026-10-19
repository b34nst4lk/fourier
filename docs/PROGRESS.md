# fourier_sketch — Progress

One row per phase. "Done" means every acceptance criterion is green and the
phase is committed.

| Phase | Scope | Criteria | Status | Commits |
|-------|-------|----------|--------|---------|
| 0 | Toolchain bootstrap | Gleam binary installed; `gleam build --target javascript` and `gleam test --target javascript` verified Erlang-free | ✅ done | (env, not repo) |
| 1 | Scaffold | `gleam new` + lustre dep; JS build green; repo initialized | ✅ done | phase 1 commit |
| 1d | Plan of record | docs/PLAN.md + docs/PROGRESS.md capturing all grills | ✅ done | docs commit |
| 2 | Math core (TDD) | RED suite: complex, resample, dft (round-trip, Parseval, known inputs, degenerates). GREEN: implementation makes suite pass | ✅ done (24/24) | RED commit + GREEN commit |
| 3 | Panel 1 sketchpad | sketch.gleam state model TDD'd (add/move/delete/undo/clear/presets/gate); SVG view wired; autosave store | ✅ done | RED + GREEN (1); shell+view+autosave (2) |
| 4 | Pipeline wiring | live resample→DFT→terms on every mousemove; feeds panels 2–3 | ✅ done | RED/GREEN part 1 + bench part 2 |
| 5 | Panel 2 output | canvas FFI, RAF epicycle animation, pause + final frame, circles slider 4–256, mirror fix visible | ✅ done | bridge RED/GREEN + canvas commit |
| 6 | Panel 3 term table | amplitude-sorted terms, (k, radius, phase) + sine sparklines, dimmed cut rows, empty states | ✅ done | spark + table commits |
| 7 | Delivery | bench ≤ 8 ms published; README (usage + smoke checklist); static build verified servable; final full-suite run | ✅ done (browser smoke = sole open item, user-run) | delivery commit |

## Notes

- Umbrella layout: both projects live under `workspace/projects/fourier/`
  (moved from `~/`; build cache wiped after the move). The pinned session
  shell anchor was first a symlink (`projects/fourier-toy` -> project),
  then replaced with a plain shim directory containing only a README note —
  the file tree now shows the project exactly once.
- Review pass (after phase-3 part 1): fixed CI target + workflow note, undo
  history cap (200, PLAN decision #19), dead import, three probe tests
  promoted (odd-N round-trip, negative coords, signed-k/Nyquist), Snapshot
  doc note, gleam.toml description/licence. Performance findings parked in
  PLAN §8. Retraction: `actions/checkout@v7` verified real — no change.
- Every build/test command on this machine must pass `--target javascript`
  (no Erlang installed). Recorded in PLAN.md §2.
- gleeunit JS runner auto-discovers `test/*_test.gleam` — suite stays modular.
- Git identity is repo-local (no global config on this box).
## Phase 3 part 2 notes

- Run: `gleam build --target javascript && node scripts/dev-server.mjs`
  -> http://localhost:3000
- Interactions: click = add dot, drag dot = move (one undo step),
  right-click = delete nearest within radius, toolbar = undo/redo/clear/
  presets. Autosave on every sketch-affecting message.
- Lustre v5 API notes (used against installed source): event handlers are
  `decode.Decoder(Msg)` (not fn(Json)); primitives are `pub const`
  (decode.int/float/string); Option comes from gleam/option; effects via
  `lustre/effect.from(fn(dispatch) -> Nil)`.
- Pending manual smoke (no browser in dev env): click/drag/delete round,
  autosave survives refresh, corrupt-storage fallback. Added to phase-7
  checklist scope.

## Phase 5 notes

- Loop design: Gleam pushes targets ([k, radius, phase] arrays — tuples
  compile to JS arrays) + mode flags on every sync-worthy change; the FFI
  RAF loop owns the clock (0.25 laps/s), caches the 256-step trace in
  SKETCH coords (resize-safe, letterbox mapping at draw time), and self-
  boots idempotently on every sync.
- Mirror story (PLAN §3 corrected): canvas y-down == complex im axis, so
  the trace matches the sketch with no y negation anywhere.
- Pending manual smoke: lap animation smoothness, slider scrub while
  dragging, final-frame freeze, play/pause states, resize refit.

## Phase 6 notes

- spark.gleam: x-projection sparklines as integer-coordinate paths
  (viewBox 0 0 36x16, 36 samples); per-row amplitude normalisation — the
  wave's own radius maps to the box, since absolute amplitudes span orders
  of magnitude across rows (correction recorded in module docs: (k, r, phi)
  vs (-k, r, phi) x-projections are identical only at phi = 0; elsewhere
  they are time-mirrors).
- Table shows ALL computed terms; rows at or below the circles-slider cut
  render dimmed (opacity .32) — table and animation stay visibly in sync.
- Perf watch item: 256 rows x (3 text cells + path attr) re-render on every
  drag frame — accepted for phase 6; if smoke shows lag, options are fewer
  sparkline samples for cut rows or sparklines only on active rows.
- Pending manual smoke: sticky header, scroll, dimming vs slider, live
  updates during dot drags.

## Phase 7 / ship notes

- README rewritten (usage, math summary, bench numbers, dev commands,
  14-point manual smoke checklist). Licence: MIT confirmed.
- Gap vs plan closed: Ctrl/Cmd+Z / Ctrl+Shift+Z / Ctrl+Y keyboard undo/redo
  (wire_keys FFI + Gleam dispatch closure — JS never builds Msg records).
- scripts/build-dist.sh: static bundle in dist/ (index + full JS tree,
  4.1 MB) — all endpoints curl-smoked 200 via a static server on dist/.
- Final bench at ship: 3.9 ms avg / 3.45 ms min (budget 8 ms).
- Format --check clean, 79/79 tests, build clean, no warnings in src.
- Open acceptance item: the user runs the README smoke checklist in a real
  browser once. Everything machine-verifiable has been run on this box.
- fourier_toy (phase 2) may now consume the math core: complex, resample,
  dft (signed-k forward/inverse), terms gates + invariants are all package
  surface with documented contracts in docs/PLAN.md section 3.

## Deployment (site: jacks.im)

- public/blog (~/hermes-users/jacksim/public/blog) is the live web root —
  asset links and og:url confirm it. The app is deployed at
  toys/fourier-sketch/ (4.1 MB: index.html + build/dev/javascript tree).
- build-dist.sh now rewrites the module import to a RELATIVE path, so the
  bundle works at any mount depth (/, /toys/fourier-sketch/, ...).
- Verified by serving the site root locally: toy page 200, every JS chunk
  200, pre-existing pages (/, /about/, index.xml) untouched.
- Caveat recorded: if jacks.im is regenerated by hugo into this public dir,
  a destination-tree cleanup could delete toys/ — keep the deploy step (or
  the toy source) part of the regeneration.

- URL: https://jacks.im/toys/fourier-sketch
