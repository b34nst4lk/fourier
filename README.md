# fourier

Two Gleam/Lustre toys sharing one math core (signed-k 1D complex DFT,
arc-length resampler, amplitude-sorted term tables) and one design language
(parchment cartography: sepia ink on aged paper, serif small-caps,
2×2 panel grids).

| toy | what it is | live |
|-----|------------|------|
| `fourier_sketch` | draw dots → Fourier epicycles redraw your shape, term table explains it | https://jacks.im/toys/fourier-sketch |
| `fourier_toy` | **Doodle** (displayed name): the daily puzzle — turn dials until the comet closes on the day's dashed shape | https://jacks.im/toys/doodle (the old /toys/fourier-toy/ address redirects) |
| `toy_admin/` | daily-puzzle backend + Access-gated admin — serving the daily puzzle API in production | — |

## Layout

Both toys sit in this repo as subtree imports (full per-project histories
preserved, connected by the import commits); each project keeps its rolling
history in its own `docs/PROGRESS.md`:

    fourier_sketch/   draw-to-epicycles toy
    fourier_toy/      Doodle, the daily puzzle toy
    .github/          single CI workflow: test matrix over both projects

## Build & test

House rule: the truth target is JavaScript everywhere — every build/test/run
command passes `--target javascript`.

    cd fourier_sketch && gleam test --target javascript
    cd fourier_toy    && gleam test --target javascript

`fourier_toy` consumes the `fourier_sketch` core via a path dependency
(`complex`, `resample`, `dft`, `terms`); the path resolves inside this repo.

## Deployment

Single-file rule: `scripts/build-dist.sh` emits one self-contained
`dist/index.html`; deploying is copying that file to the site tree.

## Licence

MIT (both projects).