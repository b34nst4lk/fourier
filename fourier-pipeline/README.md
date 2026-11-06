# fourier-pipeline

The Python that authors Doodle's daily silhouettes. Archived here so a figure can be
reproduced, argued with and improved without reverse-engineering a scratch directory.

This directory is **not** part of the Gleam build. Nothing imports it, no CI job runs it,
and it does not ship. It is a toolchain and a record — see §6 before you try to run
anything outside this machine.

```
54 files, 4,039 lines of Python
pipeline/     the reusable kit — the only part designed to be run as-is
figures/      per-figure generators, one directory per subject, version ladders included
diagnostics/  renders, sweeps and probes written to answer one question and then kept
```

## 1. What a puzzle is, in code

A puzzle is **one closed loop of 12–50 dots** in a 0–100 square, y pointing down. That is
the whole storage format:

```json
{"dots": [[x, y], ["...", "..."]]}
```

A bare `[[x, y], ...]` list is also accepted everywhere, which is why every reader does
`d = d["dots"] if isinstance(d, dict) else d`.

Everything the player sees is derived from that loop. `toy_admin/derivation.gleam` resamples
the outline to 512 points by arc length, takes the signed DFT, and picks the four largest
`|c_k|` for `k ≥ 1` as the movable dials. `k = 0` is the centroid — a translation, not a
dial, and a classic bug if you rank it in. The rest of the spectrum is frozen.

So the design target is never "the polygon looks right". It is: **four sinusoids, with the
amplitude ratios the player will be given, must reconstruct this outline recognisably.**
`pipeline/spectral.py` scores exactly that — it re-implements the Gleam derivation and
reports IoU plus how much of the shape's energy the four chosen dials own.

## 2. The seven stages

| # | stage | script | in → out |
|---|---|---|---|
| 0 | idea | — | a name, a check that no puzzle with that name exists in the admin ledger (`drafts/INDEX.md`) |
| 1 | source | `pipeline/svg_pipeline.py fetch` | icon name(s) → MDI SVGs cached locally |
| 2 | screen | `pipeline/svg_pipeline.py sheet`, `pipeline/inspect_svg.py` | SVGs → contact sheet + subpath count per icon |
| 3 | silhouette | `pipeline/svg_to_puzzle.py` | one closed contour → dots, via Douglas–Peucker simplification at a vertex budget, then arc-length resampling |
| 4 | gates | `pipeline/validate_puzzle.py`, `pipeline/spectral.py` | dots → pass/fail with numbers |
| 5 | review | `pipeline/numbered_preview.py`, `pipeline/toy_strip.py` | dots → 340 px toy panel with numbered nodes and a CSV of coordinates |
| 6 | post | `pipeline/svg_pipeline.py post --name "…"` | dots → an **undated draft** in the toy, printed id |
| 7 | publish | — | human, in the Access-gated admin UI. The agent API returns `400 AgentNoScheduling` if a `showDate` is set |

Stages 1–4 are mechanical and worth automating. Stage 0 is the judgement call and stage 7 is
deliberately not automatable: a draft exists as a candidate, a date is a commitment.

`pipeline/svg_pipeline.py` is the CLI that wires 1–6 together; `build` runs fetch → screen →
silhouette → gates in one go. The other scripts in `pipeline/` are also usable alone.

## 3. The gates, with the numbers that matter

`validate_puzzle.py` will refuse:

- fewer than 12 or more than 50 dots
- an open loop, or any self-intersection — **all pairs, not just neighbours**; an
  adjacent-only check passes polygons that visibly cross themselves
- adjacent spacing below 0.5 normalised units (dots collide on the toy's 340 px panel)
- any point outside 0–100

`spectral.py` will warn:

- dial dominance below **~0.90** — if the top four terms hold less than 90% of the energy,
  the frozen tail is doing real work and the player cannot reach the shape
- `c4 : c5` below **~1.05** — the fourth and fifth terms are nearly equal, so a tiny drag
  swaps which one the toy picked and the puzzle jitters between two shapes

Readability floor is **IoU ≥ 0.93** against the source silhouette, and it has to be judged at
**340 px, dashed, unfilled** — the toy's actual rendering. Zoomed matplotlib panels hide the
exact failure that matters (a twig merging into a torso). `pipeline/toy_strip.py` renders
panels at exactly 340×340 px by composing figures rather than scaling one, because scaling
changes the stroke width and defeats the test.

## 4. File map

### `pipeline/` — the kit

| file | what it does |
|---|---|
| `svg_pipeline.py` | the CLI: `fetch`, `sheet`, `build`, `post`. Reads `FOURIER_AGENT_KEY` from `/opt/data/.env`; never has one baked in |
| `svg_to_puzzle.py` | SVG → dots. Contour extraction, Douglas–Peucker at a vertex budget, arc-length resample |
| `validate_puzzle.py` | the geometry gates. `--dots <file>` is required |
| `spectral.py` | the derivation re-implementation: DFT, top-4 dials, energy share, IoU |
| `numbered_preview.py` | the review sheet: toy-scale panel plus a numbered polygon, `--table` for a coordinate CSV. Every review image gets numbered nodes — feedback arrives as "node 34 is too long" |
| `limb_index.py` | which node indices form each limb: centroids, radii beyond `ratio` × the median of the lower half, contiguous runs reported |
| `toy_strip.py` | a row of candidate dot sets at exact toy scale, for choosing between variants |
| `inspect_svg.py` | subpath count and contour sizes per icon — the screen that catches multi-part icons before they are silently truncated |
| `bootstrap.sh` | creates the venv at `$FOURIER_VENV` (default `/opt/data/cache/fourier-puzzle`) — **outside** this tree by design |

### `figures/` — one directory per subject, version ladders intact

| directory | contents |
|---|---|
| `castle/` | `make_castle.py` — hand-built from a mirrored half after MDI icons read as a bottle |
| `ghost/` | 8 generations, `make_ghost.py` → `make_ghost_round_final.py`, plus a parametric sweep. The ladder is the point: the eyes went from polygon holes to rounded dots |
| `violin-snowman/` | `make_v2.py` … `make_v10.py`, `make_final.py` — the shared body used by both the violin (draft 43) and the snowman body |
| `snowman/` | the arm work: `make_branch.py`, `make_branch2.py` (topology B), `make_branch_final.py` (topology C, mirrored) → `make_arms_asym.py`, `make_asym2.py` (per-side parameters), `measure_asym.py` |
| `spider/` | `build_spider.py`, `make_slim.py` (draft 59), `inspect_ring.py` (radial profile, read-only), `make_variants.py`, `render_strip.py` |

The snowman ladder is the most instructive, because the first three versions were wrong in a
way that looked fine:

- **v2 arms were 389 sq units, 13.6% of the body** — too heavy, they read as paddles. The fix
  was mass, not span: draft 63/66 arms are 106 sq units, 3.7%, at the same ~67-unit reach.
- **tapering follows Leonardo**: a fork of even width means each prong carries half the
  cross-section, so `d = D/√2 ≈ 0.707 D`. `make_asym2.py` encodes that as `taper=0.45`
  against a half-width of `w0=1.55`.
- **`finger_bearing = 90° − shaft_rake − fork`**. This is one degree of freedom, not two.
  Changing the shoulder rake silently rotates the fingers, which is why drafts 64 and 65
  failed: the intended asymmetry cancelled itself. To separate fingers by Δ you need
  `fork_shallow − fork_steep ≈ Δ + Δrake`. Below a fork of about **35°** the outbound leg
  crosses the return leg — the floor is geometric, not stylistic.

### `diagnostics/` — kept, not maintained

`render_final.py`, `render_toy_style.py`, `render_toy_pair.py`, `render_toy3.py`,
`render_asym.py`, `render_asym2.py` (renders), `sweep.py`, `sweep2.py`, `sweep3.py` (parameter
sweeps), `zoom.py`, `zoom2.py`, `grid2.py`, `strip.py`, `compare.py`, `probe.py`,
`spectrum.py` (one-off spectral dumps).

**These are not reusable as-is.** 10 of them have no docstring and several carry the question
they answered in a filename only (`zoom2.py` is "the left arm, larger"). They exist because
the numbers in §3 were measured with them.

## 5. Running it

```sh
export FOURIER_VENV=/opt/data/cache/fourier-puzzle     # keep the venv out of this tree
bash pipeline/bootstrap.sh                              # uv venv + numpy, matplotlib, pillow, requests

$FOURIER_VENV/bin/python pipeline/svg_pipeline.py --help
$FOURIER_VENV/bin/python pipeline/validate_puzzle.py --dots figure.json
$FOURIER_VENV/bin/python pipeline/spectral.py --dots figure.json
$FOURIER_VENV/bin/python pipeline/numbered_preview.py figure.json -o review.png --name "snowman" --table
```

The API key lives in `/opt/data/.env` as `FOURIER_AGENT_KEY`. It is not in this tree and must
never be committed.

## 6. Where this stops being portable

This is an archive of working code, not a library.

1. **32 of the 54 files hardcode `/opt/workspace/...` or `/opt/data/...`** — input dots paths,
   output PNG paths, and the `sys.path` insert that lets `figures/` scripts import
   `svg_pipeline`. Moving the tree requires touching those lines.
2. Several scripts `import make_branch2 as mb` or open sibling JSON by relative path, so they
   only run from inside their own `figures/` directory.
3. `measure_asym.py` imports the pipeline scripts from the skill directory by absolute path.
4. Most `diagnostics/` scripts take no arguments; the parameters are module constants you are
   meant to edit.
5. Python is 3.13 with numpy/matplotlib/pillow. No `requirements.txt` was ever needed while
   they lived in scratch directories; `bootstrap.sh` is the substitute.

## 7. What was deliberately left out

- **The figure directories, PNG review sheets and dots JSONs.** This commit is the scripts
  only. `drafts/INDEX.md` maps every admin id to the dots of record so the data is findable
  without being tracked here.
- **The venv.** `$FOURIER_VENV`, outside the tree.
- **`.env`.** See above. `.gitignore` at the repo root covers it, along with `__pycache__/`,
  `*.pyc` and `*.log`.
- **The throwaway shell one-liners.** They were how the batch runs were launched, not logic.

## 8. Provenance

Written over 2026-10-25 → 2026-11-06, alongside the puzzle series it produced: 43 scheduled
dates (through 2026-12-06) and 9 undated drafts, ids 1–66 in `drafts/INDEX.md`. The code here
is verbatim from the working directories at the moment of the commit — reformatting it would
destroy the only evidence of what each version actually did.
