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

## Deployment failure post-mortem (2026-10-19) — fixed by single-file bundle

The first jacks.im deploy rendered nothing; three independent layers failed
in sequence:
1. MY bug: the relocatable rewrite produced `from "build/..."` — a bare
   relative specifier. ES modules require "./", "../" or "/" prefixes.
   Module graph died pre-render (user console error confirmed).
2. jacks.im serves .mjs as application/octet-stream — browsers refuse
   module scripts with non-JS MIME even when specifiers are valid.
3. The deployed build/ tree silently vanished from public/ (regardless of
   what the origin served) — external sync/shim process suspected.
Resolution: scripts/build-dist.sh now bundles EVERYTHING into one 210 KB
dist/index.html (esbuild via npx, --format=esm --platform=browser; script
tag inlined, guard against '</script' in bundle). Single file => none of
the three failure modes apply. Deploy = copy one file.
NOTE to self: `pkill -f dev-server.mjs` self-matches the invoking bash
command line and kills the session — use pkill -f 'dev-serve[r]\.mjs'.

## Resource audit: phone-heat report (2026-10-19)

User symptom: phone gets hot just from loading the page. Measured with
`scripts/bench_render.mjs` (real FFI module against an op-counting stub
canvas; raster cost itself is browser-side and modeled analytically).

| Metric (Node, JIT-hot) | Value |
|---|---|
| JS math per frame (canvas loop) | ~21 μs — irrelevant |
| Canvas ops/frame playing, circles=64 (default) | ~489 (37 arcs, 65 strokes, 256-seg trace) |
| Canvas ops/frame **paused** | ~501 — REPaints identical frame 60×/s |
| Canvas ops/frame **final mode** | ~631 |
| Canvas ops/frame playing, circles=256 | ~1245 |
| rebuild_cache per model change (every Msg) | 0.39 ms @64 terms / 1.5 ms @256 |
| Fill: 500 CSS-px panel, dpr=3 | 2.25 Mpx cleared+repainted per frame |

Root causes, ranked: (1) RAF loop draws unconditionally every frame — paused
and final modes burn at 100% play rate forever; (2) uncapped dpr ⇒ 3× phones
repaint 2.25 Mpx × 60 Hz just clearRect-ing; (3) default circles=64 + preset
seeded on empty storage ⇒ full-rate animation starts on load; (4) no
off-screen gating (stacked phone layout keeps painting while scrolled away);
(5) per-segment strokes (~102 stroke calls where 4 batched paths would do);
(6) rebuild_cache on every model change even when terms are unchanged.
NOT the cause: bundle size, DFT pipeline (3.9 ms on drag), no shadowBlur/
filters, no per-frame Gleam/VDOM dispatch (loop never calls back).

### Render-loop thermal fix (2026-10-19) — deployed

Fix bundle applied to src/fourier_sketch_ffi.mjs ONLY (dist regenerated by
scripts/build-dist.sh, never hand-edited), machine-verified RED→GREEN by the
bench harness's behavior contracts (`node scripts/bench_render.mjs`, 7 PASS):
dirty gate (paused/final = one repaint, RAF chain disengages), 30fps playing
cap (dt measured across skipped frames — pen speed unchanged), DPR cap 2,
IntersectionObserver off-screen gate, batched paths (~100× fewer stroke
calls), sync dedupe skipping rebuild_cache on unchanged terms.
Harness bug found on the way: dt must be measured from last DRAWN frame —
updating it per-tick halves pen speed under the gate (caught by contract).
After-numbers: paused/final ~0.5 ops/frame (was ~500), playing@64 ~112
ops/tick at 30fps ≈ 4.3 strokes/draw (was 489 at 60fps), off-screen 0 draws,
dpr=3 backing 1500→1000 px. Site redeployed (212 KB single file, live 200).

### Animation regression post-mortem (2026-10-19, same day as thermal fix) — fixed

User report: "animation doesn't work at all." Reproduced the REAL deployed
bundle under happy-dom (probe scripts /tmp/fsd; seeded store + canvas ctx
wrap). Three stacked defects, all in src/fourier_sketch_ffi.mjs:
1. (my thermal fix) batching/dedupe indexed terms like a JS array — the app
   hands over a GLEAM LIST (iterable, no .length/index) ⇒ draw() threw
   RangeError every frame ⇒ no animation. THE killer. Pre-fix code used
   for..of so it never hit this. Fix: Array.from normalization at the sync
   boundary. Lesson recorded: harness feeds GleamishList now, tests must use
   the app's real data shapes.
2. (latent, pre-existing pattern) Lustre runs the init canvas_sync effect
   before the canvas element is attached; canvas_boot early-returned on
   el=null and nothing re-booted ⇒ loop never starts on fresh load without
   interaction. Fix: boot retries itself per RAF while unmounted.
3. (my thermal fix) rebuild_cache ran BEFORE anim.terms was reassigned —
   trace cache built from the previous term set (first boot: all zeros).
   Fix: assign then rebuild.
Harness: two new permanent contracts (boot-before-mount self-start; trace
cache reflects current terms), 9/9 PASS; both proven RED against HEAD, GREEN
after. Suite 79/79, format clean. happy-dom full-stack probe: boot→retry→
self-start→~30fps draws with batched ops. Redeployed (live 200).

## Monorepo + GitHub (2026-10-20)

- https://github.com/b34nst4lk/fourier — public; both toys live here as
  subtree imports (full per-repo histories preserved behind the import
  commits; original nested .git dirs archived to /tmp/fourier-archive).
- One CI workflow at the repo root (test matrix over both projects, JS-target
  truth per PLAN §2). The old per-repo workflows were never actually executed
  (no remote existed) — first real runs found toy-side format drift only.
  NOTE: local `gleam format --check … | tail` swallows exit codes — check
  exit status directly.

### Clear-and-redraw render bug (2026-10-20) — fixed, deployed

Report: after `clear`, new shapes (preset or custom) never rendered. Root
cause chain: clear ⇒ sketch <3 dots ⇒ the canvas ELEMENT unmounts (placeholder
swaps in) ⇒ the IO created at first boot fires isIntersecting:false for the
detached element ⇒ anim.visible=false; when the new shape mounts a NEW canvas
element, canvas_boot rebound canvas/ctx but never re-observed the IO →
visible stuck false ⇒ sync set dirty forever, pump/frame permanently gated
⇒ no rendering. Fix (3 small edits, src only): unmount boot nulls
canvas/ctx and idles the loop (bonus: no more detached-canvas painting);
frame() gains a ctx guard; boot re-observes the IO whenever the element
changes (fresh observation refreshes visibility). Harness: +2 contracts
(unmount idles; remount resumes ≥10 draws) = 11/11; harness rAF made
browser-faithful first (unique handles + per-tick drain) — the single-slot
stub returning undefined caused false pump refusals in the harness only.
79/79 + format ✓. Redeployed; live serves the fix.

### Brand + title font (2026-10-20)

Page titled "f-sketch" (title + on-page header above the sketch panel),
set in Sacramento — researched pick: monoline script whose letterforms read
like ONE continuous pen curve with circular bowls = the epicycle metaphor.
Runner-up Great Vibes rejected (high contrast, "invitation" register).
Font: latin subset woff2 (23.7 KB), base64-embedded in index.html so the
single-file rule holds; bundle 216→248 KB. OFL 1.1 licence text shipped at
docs/Sacramento-OFL.txt (embedding/redistribution permitted; README notes
it). Layout: body now flex-column (title band + grid as flex child).

### Whole-codebase review pass (2026-10-20) — CODE_REVIEW.md artifact processed + removed

A whole-code review landed in docs (untracked). Every claim was verified
against the code before acting. Verified-correct and acted upon: visibility
tightening (render.boot, store.schema_version, spark.amplitude/mid —
Snapshot left pub: exposed by the pub Sketch constructor, review's
"make private" would not compile; comment corrected instead), duplicated
`indices` (5) + `pi` (4) collapsed into new src/util.gleam (test copy kept
for test-independence), fn_→nf + go_sum→rotate_sum renames in dft, anim
state shape declared fully in the FFI (io/centers), position_at annotated,
PLAN module map reconciled (animation.gleam removed — folded into terms
long ago; spark/util added), PLAN #6 records the right-click delete
decision, §4 storage-key + theme wording corrected, root README theme
wording corrected. Two review claims REFUTED by verification:
complex.sub is alive (fourier_toy dep-smoke calls it — "no reference
anywhere" scanned one repo only) and resample.gleam has no fn_.
conjugate/magnitude_squared kept + documented as puzzle core surface
(review's own "keep as documented surface" option).

CORRECTION (same day, tightening pass): the user's rule — code with no
production callers is removed — applied to the core: complex.sub/conjugate/
magnitude_squared DELETED (no production consumer in either repo; sub had
exactly one caller, the toy dep-smoke, which now asserts coordinate-wise
tolerances instead). render.min/max_circles also made private (used only
via clamp_circles). Still test-only today but NOT removed — dft.inverse and
terms.position_at — they are required primitives of the toy's written\scoring contract (PLAN §3), annotated as such; they become production code
in toy phase 2. Trig-FFI centralisation
parked in PLAN §8 (judgement call, zero-behaviour refactor).

### Minified bundle (2026-10-20)

build-dist.sh now ships esbuild --minify --charset=utf8: inline app JS
204 KB -> 66 KB; bundle file 242 KB -> 104 KB; over the wire (gzip)
63 KB -> 47 KB. Verified by the full-stack probe on the MINIFIED bundle:
boot -> self-start -> sustained ~30fps draws, correct terms DOM. (The
embedded font block is untouched by minification as a data URI.)

### UI simplification (2026-10-20) — one animate toggle

The two mode buttons (pause/play + animate/final frame) became ONE boolean:
Model.animate. playing = animate; final-frame = not animate — the static
mode now shows the complete closed trace (the thermally-idle state). Toolbar
button label: pause when animating, play when static. API notes learned:
gleam_stdlib 1.x has no unary `not` and bool.not is bool.negate.

### Dark mode (2026-10-20)

body[data-theme] flips a full variable override: lamplit-parchment dark
(warm brown-black page/panels #1b1510/#251d12, cream ink #ead9b4, accents
brightened to contrast; gold coin + families kept). Shadows/hover/glow are
variables now (--shadow/--hover/--glow). Toggle: "night|day" chip beside the
about chip (corner-tools group); choice stored at f-sketch-theme
localStorage key; unset = follows prefers-color-scheme. Canvas FFI reads the
attribute at draw time (palette()) — the toggle never touches the app code.
Gates: 79/79, 11/11 contracts, probe-verified dark draw loop. Bundle 112→116K.

### Term selection + csv export (2026-10-20)

- Feature 1: click a term row -> the row (tr.selected, hovered bg + full ink)
  and ITS circle on the fourier panel (excluded from the batched stroke,
  redrawn bright in the palette's highlight colour, lineWidth 2). Selection
  lives by k (unique in the signed spectrum); clicks on the selected row
  toggle it off. The slider cut resets it: SetCircles re-checks
  terms.index_of_k(row) < circles, else the selection clears. The FFI
  learns a 4th sync arg (highlight k; sentinel render.no_highlight =
  999_999 -> null). Note: because the spectrum always covers the full
  signed-k range at N=512, a selected k always exists in the table — the
  cut is the only thing that can retire a selection.
- Feature 2: terms.to_csv (tested: header + shortest-float rows, no
  trailing newline) + an "export csv" chip in the table's title band ->
  Msg ExportCsv -> FFI download_csv (blob + anchor) -> f-sketch-terms.csv.
- TDD: 4 new core tests RED (compile errors) -> GREEN (83/83). Two test
  bugs caught on the way (float.to_string keeps .0 on whole numbers; a
  sloppy "expect index 2 for a missing k" assertion) — both fixed in the
  tests, not the implementation. One missing brace in the palette insert
  (module parse error) fixed next turn.
