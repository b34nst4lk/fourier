# fourier

Two Gleam/Lustre toys sharing one math core (signed-k 1D complex DFT,
arc-length resampler, amplitude-sorted term tables) and one design language
(parchment cartography: sepia ink on aged paper, serif small-caps,
2×2 panel grids — see `fourier_sketch/docs/PLAN.md`).

| toy | what it is | live |
|-----|------------|------|
| `fourier_sketch` | draw dots → Fourier epicycles redraw your shape, term table explains it | https://jacks.im/toys/fourier-sketch |
| `fourier_toy` | tuning puzzle: adjust term radii/phases to match a target shape | in progress |

## Layout & history

Both toys sit in this repo as subtree imports (full per-project histories
preserved, connected by the import commits):

    fourier_sketch/   shipped toy — phases 0–7 complete (docs/PLAN.md, docs/PROGRESS.md)
    fourier_toy/      sibling puzzle — scaffold + plan-of-record draft
    .github/          single CI workflow: test matrix over both projects

## Build & test

House rule: the truth target is JavaScript everywhere — every build/test/run
command passes `--target javascript`.

    cd fourier_sketch && gleam test --target javascript
    cd fourier_toy    && gleam test --target javascript

`fourier_toy` consumes the `fourier_sketch` core via a path dependency
(`complex`, `resample`, `dft`, `terms`); the path resolves inside this repo.

## Deployment

Single-file rule (see the deploy post-mortem in `fourier_sketch/docs/PROGRESS.md`):
`scripts/build-dist.sh` emits one self-contained `dist/index.html`; deploying
is copying that file to the site tree.

## Licence

MIT (both projects).