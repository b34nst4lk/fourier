# fourier umbrella house rules

Umbrella for the Doodle daily-puzzle system: two Gleam/Lustre toys
(`fourier_sketch`, `fourier_toy`) and their backend (`toy_admin`). These
rules apply to all three projects; the docs of record are each project's
`docs/` plans and `docs/PROGRESS.md` ledger, which take precedence on
product decisions.

- Toolchain rule: for the toys, **every** build/test/run command passes
  `--target javascript` (no Erlang on this box). `toy_admin` is the
  exception: it compiles and tests to Erlang inside Docker (its README has
  the loop).
- Logic-carrying code is TDD: the failing (RED) test lands before the
  implementation (GREEN). View/FFI layers are thin and covered by smoke
  checks + behavior contracts (`fourier_sketch/scripts/bench_render.mjs`).
- Gates before done: `gleam test --target javascript`, `gleam format
  --check`, the bench contracts. Commit only after gates are green.
- Plan-of-record discipline (2026-10-24 convention): plans are per-feature
  documents — each plan is its own file in the project's `docs/`, the
  product decisions of its feature edited into the plan with rationale —
  silent drift is banned. Completed/superseded plans move to `docs/archive/`
  with a dated archival preamble (see `toy_admin/docs/archive/` for the
  shape); `docs/PROGRESS.md` remains the rolling ledger in every project.
- Theme/visual language: parchment cartography (see fourier_sketch
  index.html variables; dark mode = lamplit variant). Both toys should
  share the visual family.
- Deliver/deploy: single-file rule — building a toy emits one self-contained
  `dist/index.html` (esbuild `--minify`). PUBLISHING runs through the blog
  repo (`~/…/projects/blog/`): `make deploy` reads the toys manifest
  (`content/toys/*.md` front matter — a toy carries a bare repo NAME; the
  GitHub owner is spelled once, in the blog's hugo config `[params]` 
  `githubBase`), executes each toy's `deploy` command in a shallow clone of
  its github remote at exactly the manifest's pinned `version` ref, and
  moves the built artifact into hugo's output tree
  (`public/toys/<slug>/index.html`): fully hermetic deploys driven by the
  remote — local checkouts are irrelevant to publishing; the blog's own
  deploys are gated on its tree being committed and print the deployed HEAD
  sha. Verify the live URL after deploy.
- Gleam version note: stdlib 1.x — bool negation is `bool.negate` (no unary
  `not`), Gleam Lists are iterables (no `.length`/index access from JS),
  floats keep `.0` on whole numbers in `float.to_string`.