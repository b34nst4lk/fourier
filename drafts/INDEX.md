# drafts — the puzzle ledger

Every silhouette authored in this repo, keyed by admin id. The toy's database is the
authority; this file mirrors it so a figure can be found from the code that produced it
without opening the admin UI.

Snapshot **2026-11-06**: 52 rows — 43 scheduled or published, 9 undated
drafts. Figure directories on disk: 36.

`drafts/<YYYYMMDD>[-<HHMM>][-<subject>]/` holds what a figure needed while it was being
made — generator, dots of record, numbered review sheet, source icons, renders. A cron
slot stamps the date and hour and can leave several candidate ideas in one directory; the
dots file named below is the one that was posted.

> This branch commits the scripts only (`fourier-pipeline/`). The figure directories listed
> here exist in the working tree but are not tracked yet.

## Scheduled and published

| id | name | showDate | figure directory · dots of record |
|---:|---|---|---|
| 1 | star | 2026-10-25 | — |
| 2 | sailboat | 2026-10-26 | — |
| 3 | jellyfish | 2026-10-27 | — |
| 4 | fish | 2026-10-28 | — |
| 5 | whale | 2026-10-29 | — |
| 6 | octopus | 2026-10-30 | — |
| 7 | cloud | 2026-10-31 | — |
| 24 | diamond | 2026-11-01 | — |
| 25 | lightning | 2026-11-02 | — |
| 10 | heart | 2026-11-03 | — |
| 11 | mountains | 2026-11-04 | — |
| 26 | bird | 2026-11-05 | — |
| 13 | mushroom | 2026-11-06 | — |
| 30 | home | 2026-11-07 | `drafts/20261027-0601/` · home-dots.json |
| 15 | lightbulb | 2026-11-08 | — |
| 16 | crown | 2026-11-09 | — |
| 17 | bell | 2026-11-10 | — |
| 18 | moon | 2026-11-11 | — |
| 19 | umbrella | 2026-11-12 | — |
| 20 | pine tree | 2026-11-13 | — |
| 21 | rocket | 2026-11-14 | — |
| 29 | pear | 2026-11-15 | `drafts/20261027-0401/` · fruit-pear-dots.json |
| 28 | elephant | 2026-11-16 | `drafts/20261027-0201/` · elephant-dots.json |
| 27 | kettle | 2026-11-17 | `drafts/20261027-0052/` · kettle-dots.json |
| 38 | ghost-round-eyes | 2026-11-18 | `drafts/20261029-ghost-round-eyes/` · ghost-round-dots.json |
| 35 | ice-cream | 2026-11-19 | `drafts/20261029-0201/` · ice-cream-dots.json |
| 34 | car | 2026-11-20 | `drafts/20261028-0601/` · car-side-dots.json |
| 33 | snail | 2026-11-21 | `drafts/20261028-0400/` · snail-dots.json |
| 32 | pumpkin | 2026-11-22 | `drafts/20261028-0200-pumpkin/` · pumpkin-dots.json |
| 31 | castle | 2026-11-23 | `drafts/20261027-1304-castle/` · castle-dots.json |
| 40 | horse | 2026-11-24 | `drafts/20261030-0202/` · horse-dots.json |
| 46 | airplane | 2026-11-25 | `drafts/20261101-0400/` · airplane-dots.json |
| 45 | tshirt | 2026-11-26 | `drafts/20261101-0200-tshirt/` · tshirt-v-dots.json |
| 52 | tooth | 2026-11-27 | `drafts/20261103-0602/` · tooth-dots.json |
| 50 | shovel | 2026-11-28 | `drafts/20261103-0201/` · shovel-dots.json |
| 48 | shark | 2026-11-29 | `drafts/20261102-0400/` · shark-dots.json |
| 47 | hammer | 2026-11-30 | `drafts/20261102-0200/` · hammer-dots.json |
| 51 | music-note | 2026-12-01 | `drafts/20261103-0401/` · music-note-dots.json |
| 49 | cactus | 2026-12-02 | `drafts/20261030-0401/` · cactus-dots.json |
| 57 | truck | 2026-12-03 | `drafts/20261105-0401/` · truck-dots.json |
| 56 | wrench | 2026-12-04 | `drafts/20261105-0200/` · wrench-dots.json |
| 58 | bread-slice | 2026-12-05 | `drafts/20261105-0600/` · bread-slice-dots.json |
| 55 | headphones | 2026-12-06 | `drafts/20261104-0602-lock/` · headphones-dots.json |

Twenty of the 43 scheduled rows have no figure directory: every id **≤ 26**, the first
generation, authored through the admin UI and the SVG pipeline before `drafts/` existed. Their
dots live only in the toy's database.

## Undated drafts

A draft has no `showDate`. Publishing is a human act in the Access-gated admin UI; the
agent API refuses to set one (the server answers `400 AgentNoScheduling`).

| id | name | figure directory · dots of record | what it is |
|---:|---|---|---|
| 53 | spider | `drafts/20261104-0201/` · spider-dots.json | first spider, superseded by 59 |
| 59 | spider-slim-legs | `drafts/20261105-spider-slim-legs/` · slim45-dots.json | slim-leg spider, the version to publish |
| 60 | dumbbell | `drafts/20261106-0201/` · dumbbell-dots.json | validated |
| 61 | snowman | `drafts/20261106-0401/` · snowman-dots.json | superseded by 63 and 66 |
| 62 | kite | `drafts/20261106-0602/` · kite-dots.json | validated |
| 63 | snowman branch arms | `drafts/20261106-snowman-asym/` · snowman-branch-dots.json | first branch arms, built by mirroring one side; superseded by 66 |
| 64 | snowman asymmetric branches | `drafts/20261106-snowman-asym/` · asym2-A-dots.json | failed — same coupling bug, caught only at toy scale |
| 65 | snowman asymmetric arms | `drafts/20261106-snowman-asym/` · asym2-B-dots.json | failed — left fork collapsed; finger bearing is coupled to shoulder rake |
| 66 | snowman asymmetric arms v2 | `drafts/20261106-snowman-asym/` · asym2-D-dots.json | the keeper for the snowman: 46 nodes, arms 3.7% of body mass, fingers 18° apart |

The admin API has no delete or update route, so drafts 64 and 65 — both failures, kept for
their record — can be removed only by hand in the admin UI.

### Built but never posted

These dots files have no matching admin row: candidates that lost a bake-off, or drafts that
were discarded before the API was called.

`asym2-C`, `baguette`, `bee`, `bone`, `camera`, `car`, `cat`, `cone`, `fire`, `food-apple`,
`food-hot-dog`, `ghost`, `puzzle`, `rabbit`, `saxophone`, `snake`, `snowman-asym`,
`snowman-v2`, `train`, `tree`, `trophy`, `violin`, `violin-v2`, `wave`.

## Queue

Last scheduled date is **2026-12-06** (`headphones`, id 55). The
scheduler takes the next empty day, so a fresh draft lands on **2026-12-07** unless an
earlier gap is opened. 43 dates are filled; the undated drafts above are the reserve.
