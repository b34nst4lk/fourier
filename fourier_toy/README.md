# Doodle — the daily doodle (source name: fourier_toy)

Tune four Fourier terms — a phase, a radius, and a frequency — until the
solid comet closes onto the dashed target. A new puzzle every day
(wordle-style), approved by the human editor from the admin's drafts; the
built-in quaver is the fallback the app boots into.

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
the pinned git ref). See `docs/archive/PLAN-2026-single-quaver-v2.md` for the
archived build plan and `docs/PROGRESS.md` for the history.

## Licence

MIT