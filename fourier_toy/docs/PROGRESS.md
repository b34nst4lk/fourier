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

## "Still broken" false alarm — stale deployment (2026-10-23)

Report after the blank-board fix: "prototype 2 is still broken, nothing
renders on the canvas." The live /toys/fourier-toy-2/ artifact was a STALE
deployment — served bundle still carried the old payload-drop guard
(`if(!X.ctx&&!Yo())return`), no retry, no stash: it predated the fix push
entirely. Confirmed by md5-refuting every candidate build (current tree,
80d35e3, 4669dc9, prototype_js) and grep-verifying the old markers in the
served HTML. Redeployed via the blog pipeline (hermetic clone of
origin/prototype = 21e6419, "artifact published at 21e6419"); live page
now serves the fixed bundle byte-identically (modulo the GA tag + a
Cloudflare edge snippet), old guard gone, retry + rebind markers present,
cf-cache-status DYNAMIC so a plain reload fetches it. Lesson: "still
broken" against a deployed page → first check WHICH ref the served
artifact was built from before touching the code.

## v2 visual fixes — three browser reports (2026-10-23)

All three root-caused against the sibling's proven loop and fixed in one
draw-pass rewrite:

1. **Quarter-size animation**: the toy never applied the DPR transform —
   the backing store is w·dpr but everything painted in CSS-pixel space,
   so on 2× screens the whole scene landed in the top-left quarter (the
   sibling's first draw step is `ctx.setTransform(dpr,…)`; the port had
   dropped it). Also ported the sibling's letterbox mapping (sketch space
   0..100 centered by min(w,h), not stretched by w and h independently).
2. **Pen/comet desync**: the comet's chunk math (`chunk =
   ceil(span/CHUNKS)`, `s <= start+chunk`) overshot — the last chunk ended
   at head+3, the comet's bright tip poking 3–4 samples ahead of the pen.
   Ported the sibling's exact boundaries (last chunk ends AT the sample
   index). The pen is now the chain tip itself — circles, links, pen and
   comet all read one chain pass, so they cannot drift apart again.
3. **Comet ≠ score on quaver** (96.7% match, comet visibly a 4-term
   curve): the fixed extras were summed as a CONSTANT offset
   (extrasSum), but the score's synth_trace has every extra rotating at
   its own k — the comet was a 4-term curve + shift, not the scored
   synthesis. Extras now chain as real epicycles after the four dials
   (most sub-pixel and skipped by the 1.2px guard; the visible few draw
   as faint honest circles) and rebuild() computes the full rotating
   synthesis — at truth the comet overlays the dashed target exactly.

Mid-fix catch (the contract earning its keep): my own chain-pass edit
read the previous center's X when accumulating Y (`c[2i]` for `c[2i+1]`)
— the comet stayed perfect (it reads the trace cache) while the pen went
garbage; the contract's pen-on-curve check caught it before any deploy.

Contract grown to 21 checks: DPR transform args, pen-on-comet-edge
(≤1.3px), comet-overlays-target at truth (measured 0.000px),
pen-on-full-synthesis-curve. Gates: gleam 14/14, format green, boot
contract 21/21, artifact smoke 23/23 (its canvas stub gained the
setTransform no-op the new draw requires).

## Mobile fix — rapid stepper taps caused double-tap zoom (2026-10-23)

User report: tapping +/− quickly on a phone zoomed the page in. Root cause
is the browser's double-tap-to-zoom gesture, not the app. Fix: surgical
`touch-action: manipulation` on `button` and `.board` in index.html —
kills double-tap zoom (and the legacy tap delay, so steppers feel
snappier on iOS) while pinch-zoom stays fully available everywhere; the
accessibility-hostile alternative (`user-scalable=no` / `maximum-scale`
in the viewport meta) was rejected on purpose. Artifact smoke grew a
shipped-CSS contract (jsdom cannot synthesize gestures): the button rule
must carry touch-action: manipulation AND the viewport must stay
user-scalable — 25/25.

## Top bar back to the prototype layout (2026-10-23)

User report: the text-wide "dark mode" toggle crowded the bar and squashed
the Match %, and the percentage read like a boxed element. The box was
the global .val dial-readout rule leaking onto the score span. Fix: bar
restored to the original prototype's structure — plain-text score
(`Match <b>67.2%</b>`, b at 1.25rem, solved turns the b green, no border)
— and the toggle restyled as the sibling's corner-chip convention
(12px small-caps letter-spaced "night"/"day", width:auto so the global
button width:100% no longer applies). Two leftover CSS quirks cleaned:
the duplicated .bar rule from the earlier rebalance, and .score .val
styles. Artifact smoke pins the layout: score is an unboxed <b>, chip
reads "night" and flips to "day" — 27/27.

## Theme chip: icon-only sun/moon (2026-10-23)

The night/day word chip became an icon chip: inline stroke SVGs (Feather-
style geometry, 24×24 viewBox) inked via CSS currentColor — moon when
light (tap → dark), sun when dark. Chosen over unicode glyphs (☀/☾)
deliberately: Android renders U+2600 as a color emoji, breaking the
parchment ink family; an inline SVG can't be platform-restyled. aria-label
keeps the button's meaning for screen readers ("dark mode"/"light mode" —
the target state). Drawn through lustre/element/svg with plain string
attributes — the sibling's sketch-panel pattern; ink follows var(--ink)
in both palettes. Smoke updated to pin the icon chip: aria-label flip +
sun's ray lines present after toggle — 27/27.

## Hold-to-repeat on the steppers (2026-10-23)

Implemented as a device-level input driver in the FFI (`hold_init`, bound
once at init): pointerdown on a stepper schedules the first repeat after
400ms, then the chain restarts at 120ms and accelerates ×0.88 to a 45ms
floor (~22 steps/s — a full phase lap or radius 0→100% in ~2–3s of
holding). Each repeat is a synthesized `btn.click()`, so Lustre's click
handler stays the single stepping path — dial state, score, and the
canvas sync exactly like a tap; disabled buttons suppress clicks, so
clamps stop the effect naturally. A quick tap still steps exactly once:
repeats only begin after the threshold, and the natural release-click
that follows a repeated hold is swallowed in the capture phase (before
Lustre's delegated listener).

Two bugs caught by the probes before any deploy: (1) the swallow flag
was armed BEFORE the synthesized click, so the driver swallowed its own
repeats — every tick died at the document gate (0 steps in jsdom);
fix: clear-then-arm around each synthesized click, disarm on
pointerout/pointercancel (a slide-off must not eat the next innocent
tap), re-arm fresh on each pointerdown. (2) the chain multiplied the
initial threshold (400→352→310ms) instead of restarting at 120ms —
HOLD_FIRST_MS was defined but never used; fix: hold_begin fires the
first repeat and hands the chain to hold_tick at 120ms.

Smoke S8 (31/31 now): hold 700ms ⇒ n repeats with the score matching the
core step-for-step; the release click swallowed; a quick tap steps
exactly once. Note for future checks: read row values only after tick()
— Lustre renders are RAF-deferred, so post-click DOM reads are stale
without a frame flush.

## Comet readability pass (2026-10-23)

User report: the moving comet was hard to parse — the tail faded to
((1/12)×0.85 ≈ 7%), so most of the lap was near-invisible and the shape
read as a disconnected stub. Fix: comet alpha ramp re-based to a 40%
floor at the tail, 85% at the tip, linear across the 12 chunks
(COMET_TAIL/COMET_TIP constants; was (k+1)/12 × 0.85). The gradient
still shows motion, but the whole lap stays readable. Circles and links
dialed ~10% fainter in both palettes (light 0.25→0.225 / 0.55→0.495;
dark 0.12→0.108 / 0.35→0.315) so the epicycle scaffolding recedes
behind the now-stronger comet. Boot contract grew the alpha-ramp pins
(tail ≥ 40%, tip ≤ 85%, tail dimmer than tip) — RED first (min 0.071),
then GREEN — 23/23.

## Epicycles receded further (2026-10-23)

Follow-up to the comet readability pass: circles and links dialed down
another ~10% (light 0.225→0.2 / 0.495→0.45; dark 0.108→0.095 /
0.315→0.28) — the scaffolding now sits clearly behind the comet and the
dashed target. Palette data only; gates unchanged and green (contract
23/23, smoke 31/31, gleam 14/14).

## Finalization — single-puzzle interface, prototype round retired (2026-10-23)

Product decision (recorded in PLAN §9): the toy ships as ONE puzzle — the
quaver — with no routing. The app rewrite: Page/route/hash machinery,
home view, back link and the hash FFI are gone (Model is just state+dark;
the match % is computed in the view from the tested core); boots straight
into the board at any URL; title "quaver"; quaver Setup retitled for the
product (`puzzle.quaver_setup()` is the shipped accessor; the P6–P10
roster stays in setups() for the gold tests). Home/card CSS dropped from
index.html.

prototype_js/ deleted from the tree — the JS prototype round is retired;
tag `prototype-js-v1` preserves it in history. The v2 Gleam app becomes
the toy served at /toys/fourier-toy/ (manifest updated in the blog repo;
the /toys/fourier-toy-2/ slug disappears and its stale artifact removed).

Smoke rewritten for the final interface — 24 checks: boot-straight-in
(paint, initial score vs core, no routing chrome, unboxed score, icon
chip), phase wrap, radius floor+disable, dial-home solve at the nearest
reachable radius step (the quaver's 2%-grid radius cannot hit truth
exactly — the score is asserted against the core for the actual stepped
state, badge at ≥95%), reset, theme, hold-to-repeat (hold/swallow/tap).
Gates: gleam 14/14, format, boot contract 23/23, artifact smoke 24/24.

## Typo fix — term 1's small print named the wrong locked fields (2026-10-23)

User report, confirmed: the phase dial's sub read "locked: r 100% · φ 265°"
— listing φ, which is exactly what that dial CHANGES. The locked pair on
the phase dial is r and k. The DialP branch of locked_note printed
r · φ (copy of the DialK branch); DialR and DialK were correct. Fix:
DialP now prints r · k. Caught by a new gold test (fixture-derived
expectations via the public readout helpers — hand-typed expected strings
for the other branches were first drafted from memory and wrong, so the
test derives every number from the fixture) plus an artifact-smoke pin on
the rendered sub. Gates: gleam 15/15, format, contract 23/23, smoke 25/25.

## Theme persistence (2026-10-23)

The toggle now persists: stored choice (localStorage key f-toy-theme,
sibling's f-sketch-theme convention) beats the system preference at boot,
prefers-color-scheme is the fallback, and every toggle saves. All storage
access is guarded (private-mode Safari throws). Architecture: the model
stays the single source of truth — init reads ffi.theme_load(), the
ToggleTheme effect saves via ffi.theme_save(); the canvas palette
follows through the existing canvas_theme push plus the boot snapshot
reading the body attribute. Known trade-off (shared with the sibling):
the stored theme applies when the module script runs, so a dark-stored
visitor sees a brief light flash — an anti-flash head script was
deliberately skipped to keep one source of truth for the fallback logic.
Smoke grew a persistence section (themed boots: stored dark / stored
light vs system dark / system dark with nothing stored) plus localStorage
assertions on both toggles — RED 26/30, then GREEN — 30/30.

## Long-press no longer triggers the text-selection loupe (2026-10-23)

User report: press-and-hold on +/− registered as press-and-hold-to-select
— the mobile selection loupe stole the pointer (pointercancel) and killed
the hold-to-repeat. Fix: -webkit-user-select: none + user-select: none +
-webkit-touch-callout: none on the button rule — the standard touch-
control guard; the +/− glyphs are control labels, never selection
targets. (touch-action: manipulation already covered double-tap zoom;
Android's contextmenu long-press was already prevented in the hold
driver.) Smoke's shipped-CSS contract pins all three properties — RED
30/31, then GREEN 31/31.

## Reset: small icon chip in the bar (2026-10-23)

The full-width "reset to start" text button is gone; reset is now a
compact chip in the bar's tools group beside the theme chip — the
standard counterclockwise arrow (feather's rotate-ccw, inline stroke SVG,
currentColor). The chip styling is shared: .chip replaces the
theme-specific rules, icon stroke scoping includes polyline. Icon-only
buttons keep their meaning via aria-label ("reset to start"). The board
gains the reset button's former vertical space. Smoke pins the bar as
score + reset chip + theme chip (RED 30/31 → GREEN 31/31).

## Change counter + plain-text dial readouts (2026-10-23)

The bar's score line now carries a muted change counter — "· N changes"
(singular at one) — counting every stepper step (hold-repeat ticks count
individually; reset zeroes it: a fresh attempt). Dial row readouts
(k/phase/radius) are plain centered text now — the boxed .val styling
(their border/card background) is gone; the score counter is .score .mv,
muted small. Smoke pins all of it: shipped-CSS val rule has no border/
background; counter 0 at boot, 1 change singular, exact counts through
the radius loop (38), reset to zero, repeat ticks counted, tap counted —
RED 31/38 → GREEN 38/38. (Mid-fix: a stray double comma after the score
span — the compiler caught it before any gate ran.)

## Counter freezes at the first solve (2026-10-23)

"· N changes" is now the number you solved in: the model tracks
solved_once (set the first time a step lands ≥ 95%), and once set, steps
stop counting — permanently, even after dialing back into unsolved
territory (the badge itself still tracks the live state). Reset starts a
fresh attempt: counter 0, solved_once cleared, counting resumes. Smoke
pins the semantics: extra step past the solve doesn't count, k-off-truth
step still doesn't count, badge drops while the number stays — RED
39/41 → GREEN 41/41 (reset-resumes is covered by the existing S4/S6
counter checks after the reset).

## The solved record survives reset (2026-10-23)

Refinement of the freeze semantics: once solved, reset restores the dials
but the record stays — "· N changes" is the number you solved in, reset
or not, and post-solve play never re-counts. Before ANY solve, reset
still starts a fresh attempt (counter zero). Reset branches on
solved_once. Smoke restructured to pin the full semantics: sections
reordered (hold-to-repeat before the solve, so counting scenarios all
run pre-solve), the solve path is now generic (computes clicks from the
tracked state, wherever the dials stand), the hold's step-count math is
wrap-aware (the hold now starts from phase 0° and wraps to 355°), and S2
pins the pre-solve reset zeroing. Two self-catches en route: my first
Reset change preserved the counter unconditionally (the pre-solve S2
check caught it — reset-before-solve must zero), and the hold check's
n=(v0−v1)/5 broke across the wrap. RED 37/46 → GREEN 46/46.

## Review pass — dead code applied, fixture memoized (2026-10-24)

The repo-wide review handoff (fourier_sketch/docs/DEAD_CODE_HANDOFF.md)
was verified item-by-item against the code, then the toy-side findings
were applied. Visibility: `setups`/`find` and `round6`/`norm_deg`/`snap5`
dropped to private — with one correction to the doc (it missed that the
boot contract consumed `puzzle.find` via compiled JS; the contract now
uses the public `quaver_setup()`, and `find` is confirmed absent from the
compiled ESM surface). Redundancies: `shapes.ints` → `util.indices`;
`mod360` deduplicated (one definition in shapes, puzzle imports it;
`shapes.solved_at` made pub so update can gate without recomputing the
metric). Perf (C1+C2): the immutable quaver fixture (512-pt synth) is
memoized in the Model — built ONCE at boot instead of up to 6× per step
(worse than the doc's 2×: dial_row/at_max also called the wrappers); the
metric is computed ONCE per step in update and read by the view (was
2×). C3: new `scripts/bench_puzzle.mjs` proves it — measured 3.96×
cheaper per step (legacy 1.81ms vs 0.458ms), budgets pinned (boot ≤5ms,
metric ≤2ms, ratio ≥1.5×). The Plan §10 parked Reset record-copy finding
is resolved by the rewrite's record-update spread. PARKED (cross-repo,
out of toy scope): B3/B5 fourier_core extraction, C4 sketch-side sync
dedupe, C5/C6 accepted debt. Gates: gleam 15/15, format, contract 23/23,
smoke 46/46, bench green.

## Docs convention change (2026-10-24)

The v2 plan (single quaver puzzle) archived to
`docs/archive/PLAN-2026-single-quaver-v2.md` with a dated preamble; its
§10 parked findings stay tracked in the dead-code handoff doc's
application record. The daily-puzzle system's plan of record is the first
per-feature plan: `../toy_admin/docs/PLAN-daily-puzzles.md`. No code
changed.

- **The rename: Doodle (2026-10-25)** — the feedback line said "fourier-toy
  doesn't catch"; the user picked Doodle from a wordle-flavor shortlist and
  specified the mark's `e`: an incomplete circle (the aperture at the lower
  right) crossed by a HALF stroke that connects to the bowl's left edge and
  stops at the centre. The board now opens with a slim wordmark row (Doodl +
  the svg-e: raster-verified before insertion; the strokes ride currentColor
  so the theme switch paints it); <title>Doodle — the daily doodle</title>;
  the admin's title "Doodle admin". The BLOG side: content/toys/doodle.md
  (the card + the blurb, the slug /toys/doodle/), the old address served
  from static/toys/fourier-toy/index.html as a meta-refresh stub (goldmark
  strips raw html — a content-page redirect rendered nothing; static/
  copies verbatim). Commit 02d6f88 + the blog's 4e68b37/3c3a7f6. LIVE
  verified: the new page 200 with the glyph in the bundle + the B/W palette
  (the theme revamp's PUBLISH gap closed by the same deploy), the stub
  refreshes, the cards list Doodle.
