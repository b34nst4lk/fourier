# fourier umbrella house rules

Umbrella for two Gleam/Lustre toys (see README.md). These rules apply to
both repos; docs of record live in each repo's `docs/PLAN.md` +
`docs/PROGRESS.md` and take precedence on product decisions.

- Toolchain rule: **every** build/test/run command passes
  `--target javascript` (no Erlang on this box).
- Logic-carrying code is TDD: the failing (RED) test lands before the
  implementation (GREEN). View/FFI layers are thin and covered by smoke
  checks + behavior contracts (`fourier_sketch/scripts/bench_render.mjs`).
- Gates before done: `gleam test --target javascript`, `gleam format
  --check`, the bench contracts. Commit only after gates are green.
- Plan-of-record discipline: product/decision changes are edited into
  `docs/PLAN.md` with rationale — silent drift is banned; progress and
  post-mortems land in `docs/PROGRESS.md`.
- Theme/visual language: parchment cartography (see fourier_sketch
  index.html variables; dark mode = lamplit variant). Both toys should
  share the visual family.
- Deliver/deploy: single-file rule — building a toy emits one self-contained
  `dist/index.html` (esbuild `--minify`). PUBLISHING runs through the blog
  repo (`~/…/projects/blog/`): `make deploy` reads the toys manifest
  (`content/toys/*.md` front matter), executes each toy's `deploy` command in
  its `repo` checkout, and copies the artifact into hugo's output tree
  (`public/toys/<slug>/index.html`). Every shipped toy pins a `version` ref
  (branch/tag/sha) in the manifest — the pipeline SHALLOW-CLONES the toy's
  github remote at exactly that ref into a throwaway temp dir, builds there,
  and moves the artifact out: fully hermetic deploys driven by the remote.
  Local checkouts are irrelevant to publishing; the blog's own deploys are
  gated on its tree being committed and print the deployed HEAD sha.
  Verify the live URL after deploy.
- Gleam version note: stdlib 1.x — bool negation is `bool.negate` (no unary
  `not`), Gleam Lists are iterables (no `.length`/index access from JS),
  floats keep `.0` on whole numbers in `float.to_string`.