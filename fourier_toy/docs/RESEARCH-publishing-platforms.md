# RESEARCH — Publishing platforms for Doodle (2026-10-31)

Question: where can the toy be published or linked beyond jacks.im, given it
must reach the live backend (`GET /api/puzzle/today`, `POST /api/solve`,
`POST /api/attempts/abandon`)? Live probes + platform docs, October 2026.

## The headline: two tiers, and one of them costs nothing

**Tier A — portals that embed OUR url (zero code change).** The doodle page
sends no `X-Frame-Options`/`CSP frame-ancestors` (verified live), so the toy
can be iframed as-is: it runs at the jacks.im origin, so the same-origin API
calls, localStorage attempt/uuid, and the fetch-first boot all work
untouched. Candidates (curated, non-exclusive, no cut):

- **I Love Web Games** — a real person plays each submission; accepted games
  embed your own build from your own URL, credit you, link back, take
  nothing.
- **Gamenora / WebGamer** — pitch a playable link; curated, selective.
- **Link-only channels** (not platforms, but the same zero-effort tier):
  r/WebGames, wordle-clone lists, HN Show HN, the blog itself.

**Tier B — platforms that host a copy of the file.** Requires the enabler
below. The toy is a single `dist/index.html`, which every HTML5 platform
accepts — but the copy is served from THEIR domain, so the API calls become
cross-origin, and the toy's relative `/api/...` paths would hit their host:

| Platform | Fit | Notes |
|---|---|---|
| **itch.io** | Best fit | Single HTML file uploads directly (no zip needed); iframe from their CDN (`v6p9d9t4.ssl.hwcdn.net`, moving to `itch.zone` — the admin confirms notice before any move); **external servers explicitly OK with CORS + HTTPS** (leafo, itch support); HTML5 payments are donation-only — free is fine; localStorage persistence is proven at scale on itch (Twine/Bitsy games). Instant listing, no gate; you bring the traffic. |
| **Newgrounds** | Strong second | HTML5 ZIP with root `index.html`, iframe embed; community judgment vote (blam risk low for a finished game); no ad revenue share currently — exposure/feedback venue. **Policy friction:** NG "prefers games that don't call third-party servers. If you use a third-party API or anything that could track a user, tell players at the start and let them opt out." Our telemetry is an anonymous uuid + move counts — disclosure in the author notes is the honest minimum; an in-toy notice/opt-out is the belt-and-braces version. |
| **GameJolt** | Fine third | Browser-build upload, indie community, free listing. |

**Tier C — poor fits, for the record.** Poki (the rev-share track is
**web-exclusive** — would disqualify jacks.im itself as the canonical home,
plus every other platform); CrazyGames/GameDistribution/GameMonetize (ad-SDK
pipelines built for session-monetized casual games); **GamePix explicitly
forbids network calls outside the bundle — disqualified on its face**; Y8
(managed ads + SDK); Kongregate (closed to open submissions — pitch-only);
Coolmath/Armor/Addicting (licensing pitches for a different game class —
possible later, not a venue for a small daily puzzle); Discord Activities
(Embedded App SDK + review — revisit only if a social angle emerges).

## The Tier-B enabler (small, testable)

1. **Absolute API base in the toy** — the FFI's fetch/POST paths prefix
   `https://jacks.im` (one constant; relative today). Host-agnostic
   everywhere, including jacks.im itself. One-file artifact stays one-file.
2. **CORS on the three public routes** — response headers for the platform
   origins (the itch CDN domain + `*.itch.zone`, newgrounds, gamejolt — or a
   wildcard, since no cookies/credentials are involved: the uuid rides in
   the POST body). Also route the OPTIONS preflight (today it 405s).
   Implementation: a small wisp middleware (TDD-able in the in-image gate)
   or a Cloudflare transform rule (zero code, invisible to the tests — the
   wisp route is the house-compatible one).
3. **Nothing else**: the daily calendar is fetched at runtime, so a
   platform copy stays in sync with the dailies forever; only toy CODE
   releases need re-uploads.

## Watch-outs

- **Per-platform identity**: browsers partition iframe/partitioned storage,
  so the same person gets separate uuids and attempts per host — stats stay
  honest (keyed by uuid+date) but unique-player counts fragment per venue.
- **Spikes vs the backend**: a portal feature means many boots (GETs are
  cheap) and solve POSTs; the per-IP throttle (60/300s) plus the parked
  Cloudflare rate-limit rule cover the realistic case.
- **The artifact on each platform goes stale between uploads** — the spike
  pattern (`/toys/doodle-dev/` pin) would want a platform twin if releases
  accelerate.

## Submission status

- 2026-11-05 — submitted to **I Love Web Games** (the form: the canonical
  game URL, the blurb + how-to-play texts, the dotted dark trace thumbnail
  via the webp URL) and **Good Browser Games** (public game URL = the
  canonical page; embeddable URL = the /embed/ twin with the trailing
  slash, after diagnosing their word-filter and the no-slash http redirect).
  Both pending review (ILWG plays every submission within days and replies
  by email with the live page link).

## Recommendation

1. **Now, free**: submit the jacks.im URL to I Love Web Games (+ Gamenora/
   WebGamer), and use the link-only channels.
2. **The enabler as one small plan** (absolute base + CORS/preflight,
   wisp-side, RED-first) — then **itch first, Newgrounds second** (with the
   disclosure), GameJolt third.
3. Leave Tier C alone unless a licensing pitch from Coolmath/Armor ever
   appeals.

## Submission URLs (verified 2026-10-31)

Tier A — the game is embeddable at two URLs: the canonical page
`https://jacks.im/toys/doodle/` and the purpose-built embed twin
`https://jacks.im/toys/doodle/embed/` (the same artifact served by the
pipeline at an /embed/ path; GA rides only the canonical page, so embeds
are tag-free). Use the embed twin where a form asks for an "embeddable URL"
specifically, the canonical page elsewhere:

- I Love Web Games — form: https://ilovewebgames.com/submit-game/ (or
  contact@ilovewebgames.com). Wants: title, iframe-embeddable URL, credit
  name, your site link, genre, 2–3 sentence blurb, 512×384+ thumbnail.
- Good Browser Games — https://goodbrowsergames.com/submit (public URL +
  embeddable URL; they track visits/playtime and surface player feedback).
- Gamenora — https://www.gamenora.com ; submissions by email to
  gamenoragames@gmail.com (their terms page: "send links, embed code, or
  game files links"). Selective, no payment.
- WebGamer — https://webgamer.io (curated; pitch via the About-page contact).

Tier B — upload the build (after the enabler):

- itch.io — create: https://itch.io/game/new (login); HTML5 guide:
  https://itch.io/docs/creators/html5 — upload `dist/index.html` directly
  (single-file projects skip the zip).
- Newgrounds — upload wizard: https://www.newgrounds.com/upload (login);
  canonical guide:
  https://www.newgrounds.com/wiki/help-information/content-submission/games-and-movies
  — ZIP with `index.html` at the root.
- GameJolt — add: https://gamejolt.com/dashboard/games/add (login); guide:
  https://gamejolt.com/help-docs/creators/add-game — Browser Build = ZIP
  with root `index.html`.

Tier C (for reference; not our targets):

- Poki — https://developers.poki.com
- CrazyGames — https://developer.crazygames.com
- GamePix — https://www.gamepix.com (developer program; forbids external
  network calls — disqualified for us regardless)
- GameDistribution — https://gamedistribution.com
- GameMonetize — https://gamemonetize.com
- Y8 — https://www.y8.com (developer flow via a Y8 Storage account)
- Kongregate — pitch by email: bd@kongregate.com
- Armor Games — pitch by email: mygame@armorgames.com
- Addicting Games — pitch by email: games@addictinggames.com
- Lagged — https://lagged.dev (or contact@lagged.com)
- Discord Activities — https://discord.com/developers/applications

Link-only channels:

- https://www.reddit.com/r/WebGames/
- https://news.ycombinator.com (Show HN)
- The 56-venue directory with per-entry links (checked Sept 2026):
  https://github.com/ayomide321/game-portals

## Sources

- itch.io HTML5 upload docs (itch.io/docs/creators/html5) — ZIP/single-file,
  limits, HTTPS-only, iframe embed, mobile-friendly mode.
- itch.io support threads: leafo (admin) on external servers ("headers
  configured correctly, HTTPS" — 2018) and on the game-serving CDN domain +
  `itch.zone` future (2019); the CORS/sandbox pitfall thread (2025).
- BitBite's Newgrounds upload guide + Newgrounds wiki (judgment thresholds,
  game guidelines incl. the third-party-server preference, monetization
  status) — checked 2026-10.
- ilovewebgames.com/publish-html5-game (portal comparison + their own
  embed-your-URL model); app.cinevva.com 2026 web-game publishing guide;
  github.com/ayomide321/game-portals (56-venue directory, Sept 2026).
- 8th Wall's publishing page (per-platform upload flows; GamePix's
  no-external-calls rule; Poki/Kongregate/Armor pitch routes).
- Live probes (2026-10-31): jacks.im page headers (no frame restrictions),
  API HEAD/OPTIONS (no CORS; 405 preflight), `/api/puzzle/today` serving.