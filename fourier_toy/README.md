# fourier toy — the quaver puzzle

Tune four Fourier terms — a phase, a radius, and a frequency — until the
solid comet closes onto the dashed eighth-note target. One puzzle, no
menus: the app boots straight into the board.

- **Dials**: term 1 phase (±5°, wraps), term 2 radius (±2% of the biggest
  dialable, 0–200%), term 3 k (±1, −16…+16); term 4 is fixed and correct.
  Steppers only — tap to step, **press and hold to auto-repeat** (accelerating).
- **Score**: one Match %, pointwise-RMS against the target's polar radius;
  solved at ≥ 95%. The fixed higher-harmonic extras are baked into both the
  target and the comet, so the illustration always matches the score.
- **Live**: https://jacks.im/toys/fourier-toy

Built with Gleam + Lustre. The math core (signed-k DFT, arc-length
resampling, amplitude-sorted terms) comes from
[`fourier_sketch`](../fourier_sketch) via a path dependency; the canvas /
RAF / theme / hold drivers live in `src/fourier_toy_ffi.mjs` (sibling
loop patterns).

## Build & test

House rule: the truth target is JavaScript — every build/test command
passes `--target javascript`.

```sh
gleam test --target javascript   # 14 gold tests (core parity with fixtures)
gleam format --check
node scripts/boot_contract.mjs   # 23 checks — canvas boot/payload behavior
node scripts/artifact_smoke.mjs  # 24 checks — the real bundle in jsdom
./scripts/build-dist.sh          # dist/index.html — ONE self-contained file
```

Deploying runs through the blog repo's toys manifest (hermetic build from
the pinned git ref). See `docs/PLAN.md` for the plan of record and
`docs/PROGRESS.md` for the build history.

## Licence

MIT