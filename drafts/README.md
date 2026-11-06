# drafts — the per-figure record

One directory per silhouette, named `<YYYYMMDD>-<HHMM>[-<subject>]` where the
timestamp is when the draft was authored (scheduled drafts use the cron slot
time; side quests use the hour and a subject slug).

Each directory holds whatever was needed to justify the shape and to answer
"why is node 17 there?":

- `*-dots.json` — the dots of record, in order around the loop
- `*-preview.png` / `*-review.png` / `*-numbered.png` — review renders; the
  numbered ones carry a node index beside every point plus a legend or a
  `-nodes.csv` table
- `contact.png`, `sweep*.png`, `grid*.png` — the search record for the idea
  (candidate icons, parameter sweeps, forks that were tried and rejected)
- `make_*.py`, `render_*.py` — the generator that produced the dots, and the
  scripts that drew the comparison sheets
- `svg/` — the source icons that were fetched and considered, rejected ones
  included
- `MANIFEST.md` — present where a figure went through several rejected
  attempts; states which draft id shipped and why the others did not

The kit that produces these lives in [`../tools/fourier-puzzle-drafting/`](../tools/fourier-puzzle-drafting/).
A directory here is a record of work, not an input to any build — nothing
under `drafts/` is compiled, served or deployed.

Draft ids referenced in manifests are ids from the admin API, not folder
names; a folder may contain several ids (see
`20261106-snowman-asym/MANIFEST.md`, which covers drafts 63–66).
