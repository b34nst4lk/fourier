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