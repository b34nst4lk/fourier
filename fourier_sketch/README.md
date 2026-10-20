# fourier_sketch

Draw dots. Watch circles redraw your drawing.

A purely-frontend, single-page teaching app for the Discrete Fourier
Transform. You place dots on a sketch pad to form a closed shape; the app
resamples that polygon, takes its complex DFT, and animates the result as a
chain of rotating circles (epicycles) whose pen tip redraws your shape on a
loop. A table beside it lists every circle's configuration — frequency `k`,
radius, and phase — with a sine sparkline per row, so the whole causal chain
*draw → sum of circles → circle recipe* stays visible at once.

Part 1 of the `fourier/` umbrella. Phase 2 (`fourier_toy`) will turn the
configuration table into a tuning puzzle, consuming this repo's math core.

## Quick start

```sh
gleam build --target javascript
node scripts/dev-server.mjs   # -> http://localhost:3000
```

No Erlang needed anywhere — this project is JavaScript-target end to end
(`gleam test --target javascript`). A static bundle for any dumb file host:

```sh
./scripts/build-dist.sh        # writes dist/ (serve dist/ statically)
cp -r dist/* <webroot>/toys/fourier-sketch/   # e.g. deployed at jacks.im/toys/fourier-sketch
```

The bundle's module import is path-relative, so it works at any mount depth.

## Using it

**Sketch (top-left):** click = add a dot, drag a dot = move it (one undo step
no matter how long the drag), right-click = delete the nearest dot, toolbar
buttons or `Ctrl/Cmd+Z` / `Ctrl+Shift+Z` (also `Ctrl+Y`) for undo/redo,
`clear` to start over, ★/♥/○ load seed presets. The last dot always connects
to the first — the transform wants a closed loop. Your sketch autosaves.

**Fourier (top-right):** the epicycle animation loops once per period
(~4 s). `pause/play` freezes it; `final frame` shows the complete closed
trace. The `circles` slider (4–256) truncates the sum to the top-N terms by
radius — drop it low and watch the drawing become a wobble, raise it and the
corners snap back in. That slider is the whole lesson.

**Terms (bottom):** every circle the DFT produced, amplitude-descending:
`k` (laps per period, negative = clockwise), `radius`, `phase` (radians),
and a sparkline of the term's sine projection (cycles = |k|, shift = phase).
Rows the slider has cut render dimmed, so table and animation stay in sync.

## How it works

1. The closed polygon of dots is resampled to **512 points evenly spaced by
   arc length** (the DFT assumes uniform sampling).
2. Each 2D point is the complex number `x + iy`; the **1D complex DFT**
   decomposes the path into rotating vectors:
   `c_k = (1/N) Σ p_n e^(−2πikn/N)`, with signed `k` (negative = clockwise).
3. One row of the table is one vector: `c_k = radius · e^(i·phase)`. Chaining
   them tip-to-tail and animating reproduces the drawing: the trace at period
   time `t` is `Σ radius · e^(i(2πkt + phase))`.
4. Invariants the test suite enforces: forward→inverse round-trip < 1e−9,
   discrete Parseval (`Σ|p|² = N·Σ|c|²`), and `Σ c_k = p_0` — the chain tip at
   t=0 is exactly the first resampled sample.
5. No y-mirroring tricks anywhere: the browser canvas y-axis grows downward,
   same as sketch space, so complex-plane points plot directly.

## Performance

Worst-case live pipeline (60 dots → 512 samples → 512 terms, sorted), the
budget is 8 ms/frame to sit alongside rendering at 60fps:

```
naive per-(k,m) exp_i:  7.7 ms avg / 7.2 ms min   # 96% of budget
twiddle table + rotation: 4.5 ms avg / 3.4 ms min # shipped
```

Reproduce: `gleam run -m fourier_sketch/bench --target javascript`

## Developing

```sh
gleam test --target javascript   # 79 tests: math invariants, state model, store schema
gleam format src test            # CI enforces formatting
gleam run -m fourier_sketch/bench --target javascript
```

Layout: all logic is pure Gleam (`complex`, `resample`, `dft`, `terms`,
`sketch`, `store`, `render`, `spark`) with TDD'd contracts in `docs/PLAN.md`;
`src/app.gleam` is the Lustre UI; `src/fourier_sketch_ffi.mjs` is the thin
JS layer (canvas + RAF, pointer/keyboard FFI, localStorage). The full plan
of record lives in `docs/PLAN.md`, phase-tracked in `docs/PROGRESS.md`.

## Manual smoke checklist (run before saying it works)

- [ ] Fresh load: empty sketch, panels 2–3 show hints; load ★ — epicycles
      animate, table fills, animation restarts on edits
- [ ] Click adds dots; the closing segment (last → first) is always drawn
- [ ] Drag a dot: panels update live; undo returns exactly to pre-drag state
- [ ] Click a dot without moving: no phantom undo step appears
- [ ] Right-click deletes the nearest dot; browser context menu suppressed
- [ ] `Ctrl+Z` / `Ctrl+Shift+Z` mirror the toolbar buttons
- [ ] Clear, undo restores; spam-click 20× — nothing crashes
- [ ] Slider scrub 4 → 256 → 4 while dragging: no crash, dimming follows
- [ ] `final frame` shows the complete closed trace; `pause` freezes it
- [ ] Refresh mid-session: sketch restored from autosave
- [ ] DevTools: `localStorage.setItem('fourier_sketch', '{oops')`, refresh —
      clean empty state, presets still work
- [ ] Resize window during animation: canvas refits, trace stays correct
- [ ] Table: sticky header, scrollable, cut rows dimmed
- [ ] Drag feels ~60fps with the slider at 256 (bench says ~4.5 ms/frame)

## License

MIT.