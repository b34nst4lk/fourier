// Render contract for the admin UI's single-file artifact: loads the BUILT
// priv/admin.html into jsdom, evals the EXACT shipped bundle (jsdom cannot run
// type="module" scripts, but the esbuild bundle is self-contained with no
// import/export syntax, so it evaluates identically as a classic script), and
// drives the real Lustre runtime end to end — menu → authoring → test play →
// back → save.
//
// Why this exists (PLAN-daily-puzzles.md §13): the drawing panel stopped
// painting when a view swap returned to it (the paint effect ran before the
// canvas it was about to mount existed, and nothing retriggered it), and test
// play scored only the dial terms while the comet drew the dial terms PLUS the
// fixture's extras. Both are DOM-observable and neither the pure gleam suites
// nor a type check can see them, so the artifact gets its own contract.
//
// Determinism: window.requestAnimationFrame is replaced with a manual queue
// (drained by tick()); canvas 2D contexts are op-counting stubs (element
// identity + op counts are the assertions; pixels are not); Path2D is a stub.
// Ground truth for every displayed Match % comes from the compiled pure core
// (admin_ui/build/dev/.../score.mjs + dial.mjs) — the same code the app runs.
//
// Deps: jsdom resolvable via require (e.g. NODE_PATH=/tmp/jsdomcheck/node_modules).
// Run (the artifact must be built first):
//   bash scripts/build-admin-ui.sh && node scripts/uismoke.mjs

import { existsSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { toList } from "../admin_ui/build/dev/javascript/prelude.mjs";
import * as score from "../admin_ui/build/dev/javascript/admin_ui/admin_ui/score.mjs";
import * as dial from "../admin_ui/build/dev/javascript/admin_ui/admin_ui/dial.mjs";

const require = createRequire(import.meta.url);
let JSDOM;
try {
  ({ JSDOM } = require("jsdom"));
} catch {
  ({ JSDOM } = createRequire("/tmp/jsdomcheck/package.json")("jsdom"));
}

// ---- artifact ---------------------------------------------------------------
// ADMIN_ARTIFACT lets a reverted build be smoked (proof the contract bites);
// the default is the shipped artifact.
const artifact_url = process.env.ADMIN_ARTIFACT || new URL("../priv/admin.html", import.meta.url);

if (!existsSync(artifact_url)) {
  throw new Error(
    "artifact missing: priv/admin.html is a build product — run scripts/build-admin-ui.sh first",
  );
}
const html = readFileSync(artifact_url, "utf8");
const script = html.match(/<script type="module">([\s\S]*?)<\/script>/);
if (!script) throw new Error("artifact: module script not found");
const bundle = script[1];
if (/\bimport\s|\bexport\s/.test(bundle)) {
  throw new Error("artifact: bundle carries ESM syntax — cannot eval as classic script");
}

// ---- the served fixture (what the preview endpoint answers) -----------------
// Big radii on purpose: every dial term AND every extra is large enough that
// the board draws it as a circle (r > 1.2px), so the op count is the chain
// length and the "same terms list" claim is countable, not inferred.
const CENTROID = [50.0, 50.0];
const DIAL_WORDS = ["phase", "radius", "k", "fixed"];
const DIAL_START = [
  { k: 1, radius: 20.0, phase: 0.0 },
  { k: -2, radius: 7.0, phase: 30.0 },
  { k: 3, radius: 4.0, phase: 45.0 },
  { k: -4, radius: 3.0, phase: 90.0 }, // fixed: no dial, always true
];
const EXTRAS = [
  { k: 5, radius: 6.0, phase: 10.0 },
  { k: -7, radius: 5.0, phase: 120.0 },
  { k: 9, radius: 4.0, phase: 200.0 },
];

const to_term = (t) => new score.Term(t.k, t.radius, t.phase);
const START = DIAL_START.map(to_term); // the same terms the fixture spells
const EXTRAS_TERMS = EXTRAS.map(to_term);
const MAX_R = dial.max_radius(toList(START));

// the target IS the full synthesis (dial + extras), so the honest score at the
// fixture's start is 100.0 and the dial-only number is visibly lower
const TARGET = Array.from(
  score.synth_trace(CENTROID, toList([...START, ...EXTRAS_TERMS])),
  (p) => [p[0], p[1]],
);
const target_list = toList(TARGET);
const NORMALIZER = score.rms_polar(target_list, CENTROID[0], CENTROID[1]);

// the rule the app must use: dial terms, then the extras chained
const synthesis = (terms) =>
  score.synthesis_match(CENTROID, toList(terms), toList(EXTRAS_TERMS), target_list, NORMALIZER);
const dial_only = (terms) => score.match_pct(CENTROID, toList(terms), target_list, NORMALIZER);

const FIXTURE = {
  name: "the smoke",
  showDate: "2026-10-25",
  centroid: CENTROID,
  dials: DIAL_WORDS,
  dial: DIAL_START,
  extras: EXTRAS,
  target: TARGET,
  // keep = start at truth, so the first displayed score is the honest 100.0
  patches: [{ kind: "keep" }, { kind: "keep" }, { kind: "keep" }, { kind: "keep" }],
};

// The served fixture keeps every dial at truth, so its two readings coincide.
// The PANEL's fixture carries a real perturbation, so the toggle's two readings
// differ in the DOM (a toggle that silently did nothing would still pass a
// keep-only fixture). The start is computed by the compiled `dial.initial` —
// the same call the app makes — so the expected strings are the app's words.
const PANEL_PATCHES = [
  { kind: "phase", deg: 90 },
  { kind: "radius", pct: 40 },
  { kind: "k", k: -1 },
  { kind: "keep" },
];
const PANEL_FIXTURE = { ...FIXTURE, patches: PANEL_PATCHES };

// the arrangement and the patch vocabulary, as the app holds them
const KIND_CTORS = {
  phase: dial.KindPhase,
  radius: dial.KindRadius,
  k: dial.KindK,
  fixed: dial.KindFixed,
};
const KINDS = DIAL_WORDS.map((word) => new KIND_CTORS[word]());
const PATCH_CTORS = {
  phase: (p) => new dial.PhaseDeg(p.deg),
  radius: (p) => new dial.RPct(p.pct),
  k: (p) => new dial.KSet(p.k),
  keep: () => new dial.Keep(),
};
const PANEL_START_TERMS = Array.from(
  dial.initial(
    toList(START),
    toList(KINDS),
    toList(PANEL_PATCHES.map((p) => PATCH_CTORS[p.kind](p))),
  ),
);

const ROWS = [
  {
    id: 7,
    name: "the quaver",
    showDate: "2026-10-24",
    attempts: 12,
    solves: 5,
    solvePct: "41.7",
    medianMoves: 23.0,
  },
  {
    id: 8,
    name: "the star",
    showDate: "2026-10-25",
    attempts: 3,
    solves: 0,
    solvePct: "0.0",
    medianMoves: null,
  },
];

// ---- stubs installed before the bundle runs ---------------------------------
let raf_q = [];
let raf_handle = 0;
let NOW = 1000.0;

function make_ctx() {
  const ops = { arc: 0, moveTo: 0, lineTo: 0, stroke: 0, fill: 0, clearRect: 0, nan: 0 };
  const finite = (x, y) => {
    if (!Number.isFinite(x) || !Number.isFinite(y)) ops.nan++;
  };
  return {
    ops,
    setLineDash: () => {},
    setTransform: () => {},
    clearRect: () => {
      ops.clearRect++;
    },
    beginPath: () => {},
    closePath: () => {},
    save: () => {},
    restore: () => {},
    get lineWidth() {
      return 1;
    },
    set lineWidth(_) {},
    get strokeStyle() {
      return "";
    },
    set strokeStyle(_) {},
    get fillStyle() {
      return "";
    },
    set fillStyle(_) {},
    get globalAlpha() {
      return 1;
    },
    set globalAlpha(_) {},
    moveTo: (x, y) => {
      ops.moveTo++;
      finite(x, y);
    },
    lineTo: (x, y) => {
      ops.lineTo++;
      finite(x, y);
    },
    arc: (x, y, _r) => {
      ops.arc++;
      finite(x, y);
    },
    stroke: () => {
      ops.stroke++;
    },
    fill: () => {
      ops.fill++;
    },
  };
}

// jsdom has no real API surface for the app's network: answer by path+method.
// `saves` is the queue of answers for POST/PUT /api/admin/puzzles (a 409 then a
// 201 is the duplicate-date-then-fixed flow the editor must survive); `previews`
// is the same queue for POST /api/admin/preview (a 500 mid-drawing is the panel's
// stale test), and `previewFixture` is the fixture every unqueued preview gets.
function install_fetch(
  window,
  {
    rows = ROWS,
    saves = [],
    previews = [],
    previewFixture = FIXTURE,
    onSave = null,
  } = {},
) {
  const calls = [];
  window.__calls = calls;
  let list_calls = 0;
  let save_calls = 0;
  let preview_calls = 0;
  let saved_ok = false;
  const answer = (status, body) => ({
    ok: status >= 200 && status < 300,
    status,
    text: () => Promise.resolve(typeof body === "string" ? body : JSON.stringify(body)),
  });
  window.fetch = (url, init = {}) => {
    const method = (init.method || "GET").toUpperCase();
    const path = String(url).replace(/^https?:\/\/[^/]+/, "");
    calls.push({ path, method, body: init.body === undefined ? null : init.body });
    if (path === "/api/admin/preview" && method === "POST") {
      const plan = previews[preview_calls] ?? {
        status: 200,
        body: { status: "ok", fixture: previewFixture },
      };
      preview_calls++;
      return Promise.resolve(answer(plan.status, plan.body));
    }
    if (/^\/api\/admin\/puzzles(\/\d+)?$/.test(path) && method !== "GET") {
      const plan = saves[save_calls] ?? { status: 201, body: { status: "ok" } };
      save_calls++;
      if (plan.status < 300) saved_ok = true;
      if (onSave) onSave(path, method, init.body);
      return Promise.resolve(answer(plan.status, plan.body));
    }
    list_calls++;
    // the calendar grows once the save landed: the menu's re-read must show it
    const list = saved_ok
      ? [...rows, { ...ROWS[0], id: 9, name: "the smoke", showDate: "2026-10-26" }]
      : rows;
    return Promise.resolve(answer(200, { status: "ok", puzzles: list }));
  };
}

function boot_dom(opts = {}) {
  raf_q = [];
  NOW = 1000.0;
  const dom = new JSDOM(html, {
    url: "https://admin.test/",
    runScripts: "dangerously",
    pretendToBeVisual: false,
    beforeParse(window) {
      install_fetch(window, opts);
      window.devicePixelRatio = 2;
      // the manual frame queue: the app's own loops (draw retry, comet) run
      // only when tick() drains it, so every assertion is frame-exact
      window.requestAnimationFrame = (cb) => {
        raf_handle++;
        raf_q.push(cb);
        return raf_handle;
      };
      window.cancelAnimationFrame = () => {};
      window.matchMedia = (q) => ({
        matches: /prefers-color-scheme:\s*light/.test(q),
        addEventListener() {},
        removeEventListener() {},
      });
      // both canvases share ONE stable recording ctx per element
      window.HTMLCanvasElement.prototype.getContext = function () {
        if (!this.__ctx) this.__ctx = make_ctx();
        return this.__ctx;
      };
      // jsdom has no layout engine: give every canvas its real CSS box
      window.HTMLCanvasElement.prototype.getBoundingClientRect = () => ({
        width: 300,
        height: 300,
        left: 0,
        top: 0,
      });
      // the panel fills its Path2D; jsdom ships none
      window.Path2D = class Path2D {
        constructor(path) {
          this.path = path;
        }
      };
    },
  });
  dom.window.eval(bundle); // lustre.start: init effects run, then the first render
  return dom;
}

function tick(ms = 34, n = 1) {
  for (let i = 0; i < n; i++) {
    NOW += ms;
    const q = raf_q;
    raf_q = [];
    for (const cb of q) cb(NOW);
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// Run frames until `predicate` holds; returns how many frames it took (-1 if it
// never did). The app's effects, the view flush and its own rAF retries are all
// frame-paced, so "it happened" is a frame count, not a magic sleep.
function frames_until(predicate, max = 20) {
  for (let i = 0; i < max; i++) {
    if (predicate()) return i;
    tick();
  }
  return predicate() ? max : -1;
}
// A fetch resolves on a microtask, but Lustre FLUSHES its re-render on the next
// frame — so "the answer arrived" and "the DOM says so" are two different
// moments, and every awaited request needs both.
async function settle(frames = 6) {
  await sleep(5);
  tick(frames);
}

// ---- assertion harness -------------------------------------------------------
let passed = 0;
let failed = 0;
function check(name, ok, detail = "") {
  if (ok) {
    passed++;
    console.log("  ok  " + name);
  } else {
    failed++;
    console.log("FAIL  " + name + (detail ? " — " + detail : ""));
  }
}
const text = (el) => (el ? el.textContent.trim() : null);
const doc = (dom) => dom.window.document;

function click(el) {
  if (!el) throw new Error("click: element missing");
  el.dispatchEvent(new el.ownerDocument.defaultView.MouseEvent("click", { bubbles: true }));
}
// a tap on the drawing panel: pointerdown at a pixel (the rect is 300×300 at
// 0,0, so sketch units = px / 3)
function tap(dom, px, py) {
  const el = doc(dom).getElementById("draw-canvas");
  if (!el) throw new Error("tap: no draw canvas");
  const ev = new dom.window.MouseEvent("pointerdown", {
    bubbles: true,
    cancelable: true,
    clientX: px,
    clientY: py,
  });
  el.dispatchEvent(ev);
  tick(); // the paint effect is followed by the retry chain, frame-paced
}
const by_text = (dom, selector, label) =>
  [...doc(dom).querySelectorAll(selector)].find((el) => text(el) === label) || null;
const button = (dom, label) => by_text(dom, "button", label);
const canvas_ops = (dom, id) => {
  const el = doc(dom).getElementById(id);
  return el && el.__ctx ? el.__ctx.ops : null;
};

// the play view's rows skip fixed slots: slot index -> visible row
const movable_slots = DIAL_WORDS.map((w, i) => (w === "fixed" ? null : i)).filter(
  (i) => i !== null,
);
const play_rows = (dom) => [...doc(dom).querySelectorAll(".panel.dials .row")];
function step_button(dom, slot, dir) {
  const row = play_rows(dom)[movable_slots.indexOf(slot)];
  if (!row) return null;
  const btns = row.querySelectorAll("button.btn");
  return dir < 0 ? btns[0] : btns[1];
}
const score_text = (dom) => {
  const el = doc(dom).querySelector(".score b");
  return el ? text(el) : null;
};
const score_solved = (dom) => {
  const el = doc(dom).querySelector(".score");
  return el ? el.classList.contains("solved") : false;
};
const moves_text = (dom) => {
  const el = doc(dom).querySelector(".score .mv");
  return el ? text(el) : null;
};
const derived_entries = (dom) =>
  [...doc(dom).querySelectorAll(".derived li")].map((el) => text(el));

// ==== S1 · boot: the calendar ================================================
console.log("S1 · boot — the menu reads the calendar");
{
  const dom = boot_dom();
  await settle(); // the list lands, then the frame flush renders it
  const rows = [...doc(dom).querySelectorAll(".rows tbody tr")];
  check("menu renders one row per puzzle", rows.length === 2, "rows: " + rows.length);
  check(
    "a row carries the puzzle's own numbers (Q23)",
    text(rows[0].querySelector(".name")) === "the quaver" &&
      text(rows[0].querySelectorAll("td")[2]) === "12" &&
      text(rows[0].querySelectorAll("td")[4]) === "41.7",
    rows[0] ? rows[0].textContent.replace(/\s+/g, " ").trim() : "missing",
  );
  check(
    "an unsolved row shows the em-dash median",
    text(rows[1].querySelectorAll("td")[5]) === "—",
    text(rows[1].querySelectorAll("td")[5]),
  );
  check(
    "no drawing canvas on the menu",
    doc(dom).getElementById("draw-canvas") === null,
  );
  dom.window.close();
}

// ==== S2 · new puzzle: the panel paints on the first tap ====================
console.log("S2 · authoring — [new puzzle] mounts a canvas that paints");
{
  const dom = boot_dom();
  await settle();
  click(button(dom, "new puzzle"));
  tick();
  const canvas = doc(dom).getElementById("draw-canvas");
  check("[new puzzle] mounts the draw canvas", canvas !== null);
  // op counts are cumulative per canvas element, so every assertion reads a
  // DELTA: one paint == one clearRect, and one arc per dot in that paint
  const snapshot = () => {
    const ops = canvas_ops(dom, "draw-canvas");
    return ops === null ? { arc: 0, fill: 0, clearRect: 0, nan: 0 } : { ...ops };
  };
  const painted = (from) => {
    const now = snapshot();
    return { ...now, d_arc: now.arc - from.arc, d_fill: now.fill - from.fill, d_clear: now.clearRect - from.clearRect };
  };
  check(
    "the empty drawing paints nothing",
    snapshot().arc === 0 && snapshot().clearRect >= 1,
    JSON.stringify(snapshot()),
  );
  check(
    "the hint counts zero dots",
    text(doc(dom).querySelector(".authoring .hint")).startsWith("0 dots"),
    text(doc(dom).querySelector(".authoring .hint")),
  );

  let from = snapshot();
  tap(dom, 60, 60);
  let delta = painted(from);
  check("the FIRST tap paints a dot", delta.d_arc === 1, JSON.stringify(delta));
  check("that paint cleared the panel first", delta.d_clear === 1, JSON.stringify(delta));
  // one paint fills twice: the closed outline through the dots, then the dot
  check("the dot and its outline are filled", delta.d_fill === 2, JSON.stringify(delta));
  check("no NaN coordinates reach the canvas", delta.nan === 0, "nan: " + delta.nan);
  check(
    "the hint counts one dot",
    text(doc(dom).querySelector(".authoring .hint")).startsWith("1 dots"),
    text(doc(dom).querySelector(".authoring .hint")),
  );

  from = snapshot();
  tap(dom, 150, 90);
  tap(dom, 120, 210);
  delta = painted(from);
  // three dots total: the second paint draws 2, the third 3
  check("the second and third taps repaint the whole drawing", delta.d_arc === 5, JSON.stringify(delta));
  check(
    "three dots unlock save and the full board",
    !button(dom, "save puzzle").disabled &&
      !button(dom, "open full board").disabled,
  );

  // undo / clear repaint, they do not just forget
  from = snapshot();
  click(button(dom, "undo"));
  tick();
  delta = painted(from);
  check("undo repaints the two remaining dots", delta.d_arc === 2 && delta.d_clear === 1, JSON.stringify(delta));
  from = snapshot();
  click(button(dom, "clear"));
  tick();
  delta = painted(from);
  check(
    "clear repaints an empty panel (a paint, just no dots)",
    delta.d_arc === 0 && delta.d_clear === 1,
    JSON.stringify(delta),
  );
  check("clear re-locks the tools", button(dom, "save puzzle").disabled);
  dom.window.close();
}

// ==== S3 · test play: the score and the comet score the same list ===========
console.log("S3 · test play — one terms list for the picture and the number");
{
  const dom = boot_dom();
  await settle();
  click(button(dom, "new puzzle"));
  tick();
  tap(dom, 60, 60);
  tap(dom, 150, 90);
  tap(dom, 120, 210);
  // the settled affordance: the only way in is the panel's link
  click(button(dom, "open full board"));
  await settle(); // the preview POST lands, the play view renders

  const board = doc(dom).getElementById("play-board");
  check("test play mounts the board", board !== null);
  const calls = dom.window.__calls;
  check(
    "test play previews the drawing instead of saving it",
    calls.some((c) => c.method === "POST" && c.path === "/api/admin/preview") &&
      !calls.some((c) => c.method === "POST" && c.path === "/api/admin/puzzles"),
  );

  // the honest score: dial terms CHAINED WITH the fixture's extras
  const start = START;
  const shown = score_text(dom);
  check(
    "the score is the full synthesis (dial + extras)",
    shown === dial.fmt1(synthesis(start)) + "%",
    "shown " + shown + " vs synthesis " + dial.fmt1(synthesis(start)) + "%",
  );
  // ...and it is NOT the dial-only number: that is the bug this pins
  check(
    "the score is not the dial-only number",
    dial.fmt1(dial_only(start)) + "%" !== shown,
    "dial-only would print " + dial.fmt1(dial_only(start)),
  );
  check("a solved start says solved", score_solved(dom));

  // the picture: one circle per chain term, all 7 large enough to draw, plus
  // the pen dot — i.e. the canvas is chaining the SAME 4 + 3 list
  const chain_len = DIAL_START.length + EXTRAS.length;
  const drew_at = frames_until(
    () => {
      const o = canvas_ops(dom, "play-board");
      return o !== null && o.arc > 0;
    },
  );
  check("the board starts drawing", drew_at >= 0, "frames: " + drew_at);
  const ops = canvas_ops(dom, "play-board");
  // exactly one frame's worth: one circle per chain term (all 7 are large
  // enough to draw) plus the pen dot — the canvas chains the SAME 4 + 3 list
  check(
    "the comet chains the dial terms AND the extras (" + chain_len + " circles + pen)",
    ops.arc === chain_len + 1,
    "arc ops: " + ops.arc + " (chain " + chain_len + ")",
  );
  check("the board draws only finite coordinates", ops.nan === 0, "nan: " + ops.nan);

  // the derived truths: one bullet per MOVABLE slot, in the dial row's words
  check(
    "the derived readout lists the 3 movable slots",
    derived_entries(dom).length === 3,
    JSON.stringify(derived_entries(dom)),
  );
  check(
    "each bullet names its dial and its slot's value",
    JSON.stringify(derived_entries(dom)) ===
      JSON.stringify([
        "term 1 · phase dial — set φ 0°",
        "term 2 · radius dial — set r 35%",
        "term 3 · k dial — set k +3",
      ]),
    JSON.stringify(derived_entries(dom)),
  );

  // a dial step re-scores the same list
  click(step_button(dom, 1, 1));
  tick();
  const stepped = start.slice();
  stepped[1] = dial.step(new dial.KindRadius(), start[1], 1, MAX_R);
  check(
    "a dial step re-scores the full synthesis",
    score_text(dom) === dial.fmt1(synthesis(stepped)) + "%",
    "shown " + score_text(dom) + " vs synthesis " + dial.fmt1(synthesis(stepped)) + "%",
  );
  check("the step counts a move", /1 change/.test(moves_text(dom) || ""), moves_text(dom));
  dom.window.close();
}

// ==== S4 · back to authoring repaints without a tap (the regression) =======
console.log("S4 · back to authoring — the drawing is still there");
{
  const dom = boot_dom();
  await settle();
  click(button(dom, "new puzzle"));
  tick();
  tap(dom, 60, 60);
  tap(dom, 150, 90);
  tap(dom, 120, 210);
  const before = doc(dom).getElementById("draw-canvas");
  // three taps, each repainting the whole drawing: 1 + 2 + 3 arcs in total
  const before_arcs = canvas_ops(dom, "draw-canvas").arc;
  check("the drawing paints before leaving", before_arcs === 6, "arc ops: " + before_arcs);

  click(button(dom, "open full board"));
  await settle();
  check("test play took over", doc(dom).getElementById("play-board") !== null);
  click(button(dom, "back to the drawing"));
  // the paint lands now (sync) or on the retry's next frame — never on a tap
  const painted_at = frames_until(() => {
    const el = doc(dom).getElementById("draw-canvas");
    return el !== null && el.__ctx !== undefined && el.__ctx.ops.arc > 0;
  });
  check("the repaint lands on its own", painted_at >= 0, "frames: " + painted_at);

  const after = doc(dom).getElementById("draw-canvas");
  const ops = canvas_ops(dom, "draw-canvas"); // null: never painted a thing
  check("the draw canvas is back", after !== null);
  if (after === before) {
    check(
      "the same canvas element was repainted (no tap needed)",
      ops !== null && ops.arc > before_arcs,
      "arc ops " + before_arcs + " -> " + (ops && ops.arc),
    );
  } else {
    check(
      "the new canvas element painted the existing dots (no tap needed)",
      ops !== null && ops.arc === 3,
      "arc ops: " + (ops && ops.arc),
    );
  }
  check(
    "the hint still counts the drawing's dots",
    text(doc(dom).querySelector(".authoring .hint")).startsWith("3 dots"),
    text(doc(dom).querySelector(".authoring .hint")),
  );
  check(
    "the play loop stopped with its canvas",
    doc(dom).getElementById("play-board") === null,
  );
  dom.window.close();
}

// ==== S5 · save: a 409, then a 201 ==========================================
console.log("S5 · save — the server's refusal is shown, then the save lands");
{
  const posted = [];
  const dom = boot_dom({
    saves: [
      { status: 409, body: { status: "error", errors: ["DuplicateShowDate"] } },
      { status: 201, body: { status: "ok" } },
    ],
    onSave: (path, method, body) => posted.push({ path, method, body }),
  });
  await settle();
  click(button(dom, "new puzzle"));
  tick();
  tap(dom, 60, 60);
  tap(dom, 150, 90);
  tap(dom, 120, 210);

  click(button(dom, "save puzzle"));
  await settle();
  const error = doc(dom).querySelector(".error");
  check(
    "a 409 shows the server's reason in words",
    text(error) === "that date is taken",
    text(error),
  );
  check(
    "the refused save stays in the editor with the drawing intact",
    doc(dom).getElementById("draw-canvas") !== null &&
      (text(doc(dom).querySelector(".authoring .hint")) || "").startsWith("3 dots"),
  );
  check("the POST carried the drawing", posted.length === 1 && /"dots":\[/.test(posted[0].body));

  click(button(dom, "save puzzle"));
  await settle();
  const flash = doc(dom).querySelector(".flash");
  check("a 201 lands back on the calendar and says so", text(flash) === "saved", text(flash));
  const rows = [...doc(dom).querySelectorAll(".rows tbody tr")];
  check(
    "the calendar was re-read and shows the new puzzle",
    rows.length === 3 && text(rows[2].querySelector(".name")) === "the smoke",
    "rows: " + rows.length,
  );
  check("the second save was a POST too", posted.length === 2 && posted[1].method === "POST");
  dom.window.close();
}

// ==== S6 · the live panel: two columns, one debounced preview ==============
console.log("S6 · live panel — the drawing previews itself");
{
  // the first answer lands (the panel has something to show), the second is
  // refused (the panel must keep what it has and say so), the rest land
  const dom = boot_dom({
    previewFixture: PANEL_FIXTURE,
    previews: [
      { status: 200, body: { status: "ok", fixture: PANEL_FIXTURE } },
      { status: 500, body: { status: "error", errors: ["BadDrawing"] } },
    ],
  });
  await settle();
  click(button(dom, "new puzzle"));
  tick();

  const studio = doc(dom).querySelector(".studio");
  const cols = studio ? dom.window.getComputedStyle(studio).gridTemplateColumns : "missing";
  // jsdom resolves the stylesheet (width 1024), so 900px+ is the wide case
  check(
    "on a wide viewport the drawing and the panel are two columns",
    cols === "1fr 1fr",
    "grid-template-columns: " + JSON.stringify(cols),
  );
  check(
    "both boards are mounted at once",
    doc(dom).getElementById("draw-canvas") !== null &&
      doc(dom).getElementById("preview-board") !== null,
  );

  const preview_calls = () =>
    dom.window.__calls.filter((c) => c.method === "POST" && c.path === "/api/admin/preview")
      .length;
  const rows = () => [...doc(dom).querySelectorAll(".preview-dials .row")];
  const values = () => rows().map((row) => text(row.querySelector(".val")));
  const stale_visible = () => {
    const el = doc(dom).querySelector(".preview-stale");
    return el !== null && !el.classList.contains("hidden");
  };
  const truth_vals = movable_slots.map((slot) =>
    dial.slot_value(KINDS[slot], START[slot], MAX_R),
  );
  const start_vals = movable_slots.map((slot) =>
    dial.slot_value(KINDS[slot], PANEL_START_TERMS[slot], MAX_R),
  );

  // three taps inside one debounce window: ONE request, and not before the
  // window closes (the seam is the module's single timer slot + the fire msg)
  const panel_before = canvas_ops(dom, "preview-board") ?? { arc: 0, clearRect: 0 };
  tap(dom, 60, 60);
  tap(dom, 150, 90);
  tap(dom, 120, 210);
  check("a burst of taps does not POST before the window closes", preview_calls() === 0, "calls: " + preview_calls());
  await sleep(150);
  check(
    "half a window later it still has not POSTed",
    preview_calls() === 0,
    "calls: " + preview_calls(),
  );
  await sleep(250);
  await settle();
  check(
    "three taps inside one window sent exactly ONE preview",
    preview_calls() === 1,
    "calls: " + preview_calls(),
  );

  const panel_after = canvas_ops(dom, "preview-board");
  check(
    "the panel repaints after the last dot settles",
    panel_after !== null &&
      panel_after.arc > panel_before.arc &&
      panel_after.clearRect > panel_before.clearRect,
    JSON.stringify(panel_before) + " -> " + JSON.stringify(panel_after),
  );
  check("the panel's board drew finite coordinates", panel_after !== null && panel_after.nan === 0);
  check(
    "the panel's rows are the movable slots only",
    rows().length === 3,
    "rows: " + rows().length,
  );
  check(
    "the panel's rows are read-only (no steppers)",
    doc(dom).querySelectorAll(".preview-dials .row button").length === 0,
  );
  check(
    "the panel opens on the dial truth",
    JSON.stringify(values()) === JSON.stringify(truth_vals),
    JSON.stringify(values()) + " vs truth " + JSON.stringify(truth_vals),
  );
  check("the truth view is the lit toggle", button(dom, "solved view").classList.contains("on"));
  check("nothing is stale after a good preview", !stale_visible());

  // the toggle re-reads the fixture ALREADY in hand: no second request
  const calls_before_toggle = preview_calls();
  click(button(dom, "player start"));
  tick();
  check(
    "the toggle switches the rows to the player's patched start",
    JSON.stringify(values()) === JSON.stringify(start_vals),
    JSON.stringify(values()) + " vs start " + JSON.stringify(start_vals),
  );
  check(
    "the two readings really differ (the fixture perturbs its dials)",
    JSON.stringify(start_vals) !== JSON.stringify(truth_vals),
    JSON.stringify(start_vals) + " == " + JSON.stringify(truth_vals),
  );
  check("the start view is the lit toggle", button(dom, "player start").classList.contains("on"));
  check(
    "the toggle repaints without asking the server",
    preview_calls() === calls_before_toggle,
    "calls: " + calls_before_toggle + " -> " + preview_calls(),
  );

  // a refused preview: the hint appears, the last fixture keeps drawing
  const panel_el = doc(dom).getElementById("preview-board");
  tap(dom, 40, 40);
  await sleep(360);
  await settle();
  check("a refused preview says 'preview stale'", stale_visible());
  check(
    "the refused preview kept the last fixture's rows",
    JSON.stringify(values()) === JSON.stringify(start_vals),
    JSON.stringify(values()) + " vs kept " + JSON.stringify(start_vals),
  );
  check(
    "the panel never blanked (same canvas, still mounted)",
    panel_el !== null && doc(dom).getElementById("preview-board") === panel_el,
  );
  check("the stale panel still shows its board", canvas_ops(dom, "preview-board").arc > 0);

  // ...and the next good answer clears the hint
  tap(dom, 80, 80);
  await sleep(360);
  await settle();
  check("the next good preview clears the stale hint", !stale_visible());

  // 'open full board' keeps its own flow: the panel's pending clock is voided,
  // so a tap just before it cannot leak a SECOND preview request
  const before_open = preview_calls();
  tap(dom, 200, 200);
  click(button(dom, "open full board"));
  await settle();
  await sleep(360);
  await settle();
  check(
    "opening the full board voids the panel's timer (one request, not two)",
    preview_calls() === before_open + 1,
    "calls: " + before_open + " -> " + preview_calls(),
  );
  check("the full board took over", doc(dom).getElementById("play-board") !== null);
  dom.window.close();
}

// ---- verdict ----------------------------------------------------------------
console.log(
  "\n" + passed + " passed, " + failed + " failed" + (failed ? " — ARTIFACT CONTRACT BROKEN" : ""),
);
process.exit(failed ? 1 : 0);
