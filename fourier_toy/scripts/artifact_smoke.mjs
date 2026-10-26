// App-level smoke for the single-file dist artifact: loads dist/index.html
// into jsdom, evals the EXACT shipped bundle (jsdom can't run type="module"
// scripts, but the esbuild bundle is self-contained with no export syntax, so
// it evaluates identically as a classic script), and drives the real Lustre
// runtime end to end — the FINAL v2 interface: ONE puzzle (the quaver), no
// routing: the app boots straight into the board.
//
// PLAN-dial-columns.md §4 Phase 4. The board's stepper ROWS are gone: under
// the canvas sit three purely-visual dial COLUMNS (one per dialed term, chain
// order), each `[glyph ↑][canvas col-N][glyph ↓]` with NO text at all. This
// smoke pins:
//   - the shipped CSS (no rows/readouts, ordinal ink vars, glyph sizing, the
//     touch-action / user-select guards kept on `button`);
//   - the DOM contract (3 columns, 6 icon-only glyph buttons with the exact
//     aria-labels, the reset chip's skip-back glyph);
//   - dial behavior through the glyphs (wrap, edges at 0/200% and ±16, score
//     vs the compiled core on every step, hold-to-repeat, solve/reset, theme);
//   - the daily flows on attempt schema v2 (old-format served documents are
//     normalized; a stale v1 attempt boots fresh; abandon/solve POSTs;
//     offline/500/malformed → the quaver fallback with zero POSTs).
//
// Determinism: window.requestAnimationFrame is replaced with a manual queue
// (drained by tick()); canvas 2D contexts are replaced with op-recording stubs.
// The stubs record ONE frame per clearRect (arcs/lines/strokes with the stroke
// style), so the smoke can read a column's ring radius and the phase column's
// start-marker angle — the visual stand-in for the retired text readouts.
// Element identity, per-canvas op counts and drawn geometry are the assertions;
// pixels are not.
//
// Ground truth for every displayed Match % comes from the compiled pure core
// (build/dev/.../puzzle.mjs + shapes.mjs) — the same code the app runs.
//
// Deps: jsdom resolvable via require (e.g. NODE_PATH=/tmp/jsdomcheck/node_modules).
// Run: node scripts/artifact_smoke.mjs

import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { toList } from "../build/dev/javascript/prelude.mjs";
import * as shapes from "../build/dev/javascript/fourier_toy/fourier_toy/shapes.mjs";
import * as puzzle from "../build/dev/javascript/fourier_toy/fourier_toy/puzzle.mjs";

const require = createRequire(import.meta.url);
let JSDOM;
try {
  ({ JSDOM } = require("jsdom"));
} catch {
  ({ JSDOM } = createRequire("/tmp/jsdomcheck/package.json")("jsdom"));
}

// ---- artifact ---------------------------------------------------------------
const html = readFileSync(new URL("../dist/index.html", import.meta.url), "utf8");
const m = html.match(/<script type="module">([\s\S]*?)<\/script>/);
if (!m) throw new Error("artifact: module script not found");
const bundle = m[1];
if (/\bimport\s|\bexport\s/.test(bundle)) {
  throw new Error("artifact: bundle carries ESM syntax — cannot eval as classic script");
}

// ---- stubs installed before the bundle runs ---------------------------------
let raf_q = [];
let raf_handle = 0;
let NOW = 1000.0;

// The board is the real 300×300 CSS box; each column canvas is 128×104 (the
// FFI's circle space = min(w,h)/2 = 52, matching the shipped 104px CSS height).
// A frame's draws are grouped at its clearRect, mirroring the live loop's
// "clear, then paint" order — so the LAST frame is the current picture.
const BOARD_RECT = { width: 300, height: 300 };
const COL_RECT = { width: 128, height: 104 };
const COL_SPACE = Math.min(COL_RECT.width, COL_RECT.height) / 2; // 52
const COL_IDS = ["col-0", "col-1", "col-2"];

function make_ctx() {
  const ops = { arc: 0, moveTo: 0, lineTo: 0, stroke: 0, nan: 0 };
  const frames = [];
  const st = { style: "", width: 1, alpha: 1, x: 0, y: 0, path: null };
  const frame = () => (frames.length ? frames[frames.length - 1] : null);
  return {
    ops,
    frames,
    setLineDash: () => {},
    setTransform: () => {},
    clearRect: () => {
      frames.push({ arcs: [], lines: [], strokes: [] });
      if (frames.length > 64) frames.shift();
    },
    beginPath: () => {
      st.path = { arcs: [], lines: [] };
    },
    closePath: () => {},
    moveTo: (x, y) => {
      ops.moveTo++;
      if (!Number.isFinite(x) || !Number.isFinite(y)) ops.nan++;
      st.x = x;
      st.y = y;
    },
    lineTo: (x, y) => {
      ops.lineTo++;
      if (!Number.isFinite(x) || !Number.isFinite(y)) ops.nan++;
      const f = frame();
      if (f) f.lines.push([st.x, st.y, x, y]);
      if (st.path) st.path.lines.push([st.x, st.y, x, y]);
      st.x = x;
      st.y = y;
    },
    arc: (x, y, r) => {
      ops.arc++;
      if (!Number.isFinite(x) || !Number.isFinite(y)) ops.nan++;
      const f = frame();
      if (f) f.arcs.push([x, y, r]);
      if (st.path) st.path.arcs.push([x, y, r]);
    },
    stroke: () => {
      ops.stroke++;
      const f = frame();
      if (f) {
        f.strokes.push({
          style: st.style,
          width: st.width,
          alpha: st.alpha,
          arcs: st.path ? st.path.arcs.slice() : [],
          lines: st.path ? st.path.lines.slice() : [],
        });
      }
      st.path = null;
    },
    get lineWidth() {
      return st.width;
    },
    set lineWidth(v) {
      st.width = v;
    },
    get strokeStyle() {
      return st.style;
    },
    set strokeStyle(v) {
      st.style = v;
    },
    get globalAlpha() {
      return st.alpha;
    },
    set globalAlpha(v) {
      st.alpha = v;
    },
  };
}

// The network half of the daily puzzle (PLAN-daily-puzzles.md §1). jsdom has no
// fetch, so the smoke supplies one: `fetchMode` picks the answer to
// GET /api/puzzle/today ("none" is the default — the empty calendar every
// pre-daily scenario boots into), and every call is logged so the scenarios can
// count and read the POSTs. POSTs answer 200 unless `postFails`.
function install_fetch(window, { fetchMode = "none", fetchBody = null, postFails = false }) {
  const calls = [];
  window.__calls = calls;
  window.fetch = (url, init = {}) => {
    const method = (init.method || "GET").toUpperCase();
    calls.push({ url: String(url), method, body: init.body === undefined ? null : init.body });
    if (method !== "GET") {
      if (postFails) return Promise.reject(new Error("offline"));
      return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve("{}") });
    }
    if (fetchMode === "reject") return Promise.reject(new Error("offline"));
    if (fetchMode === "http500") {
      return Promise.resolve({ ok: false, status: 500, text: () => Promise.resolve("") });
    }
    const body = fetchMode === "ok" ? fetchBody : JSON.stringify({ status: "none", fallback: true });
    return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve(body) });
  };
}

function boot_dom({
  stored = null,
  systemDark = false,
  seed = null,
  fetchMode = "none",
  fetchBody = null,
  postFails = false,
} = {}) {
  raf_q = [];
  NOW = 1000.0;
  const dom = new JSDOM(html, {
    url: "https://toy.test/", // no hash — the app boots straight into the board
    runScripts: "dangerously",
    pretendToBeVisual: false,
    beforeParse(window) {
      install_fetch(window, { fetchMode, fetchBody, postFails });
      window.devicePixelRatio = 2;
      window.requestAnimationFrame = (cb) => {
        raf_handle++;
        raf_q.push(cb);
        return raf_handle;
      };
      window.cancelAnimationFrame = () => {};
      // jsdom's matchMedia is inert — the boot reads the system preference
      // at init, so the stub must exist before the bundle runs
      window.matchMedia = (q) => ({
        matches: systemDark && /prefers-color-scheme:\s*dark/.test(q),
        addEventListener() {},
        removeEventListener() {},
      });
      // seed the stored theme choice (sibling's f-sketch-theme convention)
      if (stored) {
        try {
          window.localStorage.setItem("f-toy-theme", stored);
        } catch (e) {}
      }
      // seed a stored attempt / identity (the daily puzzle's keys)
      if (seed) {
        for (const [key, value] of Object.entries(seed)) {
          try {
            window.localStorage.setItem(key, value);
          } catch (e) {}
        }
      }
      // ONE stable recording ctx per canvas element
      window.HTMLCanvasElement.prototype.getContext = function () {
        if (!this.__ctx) this.__ctx = make_ctx();
        return this.__ctx;
      };
      // jsdom has no layout engine (rects are all zeros): give the board its
      // real CSS size and the columns their 104px-tall circle space, so
      // fit()/sub-pixel skips behave as in a browser
      window.HTMLCanvasElement.prototype.getBoundingClientRect = function () {
        const isCol = COL_IDS.includes(this.id || "");
        return { ...(isCol ? COL_RECT : BOARD_RECT), left: 0, top: 0 };
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

// ---- ground truth (the compiled pure core — same code the app runs) --------
const setup = puzzle.quaver_setup();
const shape = puzzle.shape_of(setup.shape);
const initial_state = () => puzzle.initial(shape, setup.patches);
function step_slot(state, slot, dir) {
  const kinds = Array.from(setup.dials);
  // mirror update(): index-wise step, rebuilt as a real Gleam cons list
  return toList(
    Array.from(state, (s, i) =>
      i === slot ? puzzle.step(kinds[i], s, dir, shape.dial_max_r) : s,
    ),
  );
}
const match_of = (state) => shapes.match_pct(shape, state);
const core_score = (state) => puzzle.fmt1(match_of(state)) + "%";
const mod360 = (x) => ((x % 360) + 360) % 360;

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
const close = (a, b, tol = 1.0) =>
  a !== null && b !== null && Number.isFinite(a) && Math.abs(a - b) <= tol;
const angle_close = (a, b, tol = 0.75) =>
  a !== null && Math.abs(((a - b + 540) % 360) - 180) <= tol;

// ---- helpers over the live DOM ----------------------------------------------
function board_canvas(dom) {
  return dom.window.document.getElementById("toy-board");
}
function canvas_ops(dom) {
  const el = board_canvas(dom);
  return el && el.__ctx ? el.__ctx.ops : null;
}
function score_val(dom) {
  const el = dom.window.document.querySelector(".score b");
  return el ? text(el) : null;
}
function counter(dom) {
  const el = dom.window.document.querySelector(".score .mv");
  return el ? el.textContent.replace(/\s+/g, " ").trim() : null;
}
function counter_n(d) {
  const n = parseInt((counter(d) || "").replace(/[^0-9]/g, ""), 10);
  return Number.isFinite(n) ? n : null;
}
function cols(dom) {
  return [...dom.window.document.querySelectorAll(".cols .col")];
}
function glyph(dom, label) {
  return dom.window.document.querySelector(`button[aria-label="${label}"]`);
}
function click_label(dom, label) {
  const b = glyph(dom, label);
  if (b) b.click();
  return b;
}
/// The last painted frame of one canvas (null before it ever painted).
function last_frame(dom, id) {
  const el = dom.window.document.getElementById(id);
  const ctx = el && el.__ctx;
  if (!ctx || !ctx.frames.length) return null;
  return ctx.frames[ctx.frames.length - 1];
}
/// The phase column's start-marker dot: the first small arc of col-0 (the ring
/// is the big arc before it; the pen dot comes later, after the arm).
function marker_deg(dom) {
  const f = last_frame(dom, "col-0");
  if (!f) return null;
  for (const s of f.strokes) {
    for (const a of s.arcs) {
      if (a[2] < 5) {
        const deg = (Math.atan2(a[1] - COL_RECT.height / 2, a[0] - COL_RECT.width / 2) * 180) / Math.PI;
        return mod360(deg);
      }
    }
  }
  return null;
}
/// A column's ring radius: the first stroke's first arc (the ring is drawn
/// first). At r = 0 the radius column draws nothing, so the frame has no
/// strokes and this is null.
function ring_radius(dom, i) {
  const f = last_frame(dom, "col-" + i);
  if (!f || !f.strokes.length) return null;
  const s = f.strokes[0];
  return s.arcs.length ? s.arcs[0][2] : null;
}
/// The ring's ink (the column's ordinal colour).
function col_ink(dom, i) {
  const f = last_frame(dom, "col-" + i);
  return f && f.strokes.length ? f.strokes[0].style : null;
}
/// The set of stroke colours the board painted in its last frame.
function board_inks(dom) {
  const f = last_frame(dom, "toy-board");
  return f ? new Set(f.strokes.map((s) => s.style)) : new Set();
}

// The six glyph buttons' exact labels (PLAN-dial-columns §1 decision 8).
const GLYPH_LABELS = [
  "increase phase",
  "decrease phase",
  "increase radius",
  "decrease radius",
  "increase k",
  "decrease k",
];

// ==== S0 · shipped CSS contract =================================================
console.log("S0 · artifact CSS — dial columns, ordinal ink, input guards kept");
{
  const buttonRule = html.match(/\nbutton \{[^}]*\}/);
  check(
    "glyph buttons carry touch-action: manipulation (no double-tap zoom; pinch kept)",
    buttonRule !== null && /touch-action:\s*manipulation/.test(buttonRule[0]),
    "button rule: " + (buttonRule ? buttonRule[0].slice(0, 80) + "…" : "missing"),
  );
  check(
    "glyph buttons opt out of text selection (long-press = hold-repeat, not loupe)",
    buttonRule !== null &&
      /-webkit-user-select:\s*none/.test(buttonRule[0]) &&
      /(^|[^-])user-select:\s*none/.test(buttonRule[0]) &&
      /-webkit-touch-callout:\s*none/.test(buttonRule[0]),
    "button rule: " + (buttonRule ? buttonRule[0] : "missing"),
  );
  check(
    "viewport stays user-scalable (pinch-zoom accessibility preserved)",
    !/user-scalable\s*=\s*no/i.test(html) && !/maximum-scale\s*=\s*1\b/i.test(html),
    "viewport meta limits zoom",
  );

  const colsRule = html.match(/\n\.cols \{[^}]*\}/);
  check(
    "the dial columns are a 3 × 1fr grid (.cols)",
    colsRule !== null &&
      /display:\s*grid/.test(colsRule[0]) &&
      /grid-template-columns:\s*repeat\(3,\s*1fr\)/.test(colsRule[0]),
    "cols rule: " + (colsRule ? colsRule[0].replace(/\s+/g, " ") : "missing"),
  );
  const colRule = html.match(/\n\.col \{[^}]*\}/);
  check(
    "each column is a vertical stack ([glyph][canvas][glyph])",
    colRule !== null &&
      /display:\s*flex/.test(colRule[0]) &&
      /flex-direction:\s*column/.test(colRule[0]),
    "col rule: " + (colRule ? colRule[0].replace(/\s+/g, " ") : "missing"),
  );
  const canvasRule = html.match(/\n\.col canvas \{[^}]*\}/);
  check(
    "the column canvas is sized to the circle space (104px tall, full width)",
    canvasRule !== null && /height:\s*104px/.test(canvasRule[0]) && /width:\s*100%/.test(canvasRule[0]),
    "col canvas rule: " + (canvasRule ? canvasRule[0].replace(/\s+/g, " ") : "missing"),
  );

  // Ordinal ink: one colour per CHAIN POSITION (not per dial kind), the same
  // hexes the FFI palette uses in both themes.
  const lightBlock = html.match(/:root \{[^}]*\}/s);
  const darkBlock = html.match(/body\[data-theme="dark"\] \{[^}]*\}/s);
  const light = lightBlock ? lightBlock[0] : "";
  const dark = darkBlock ? darkBlock[0] : "";
  check(
    "light ordinal ink = --ord-0/1/2 (#c8321e/#8a6d00/#1f5fae)",
    /--ord-0:\s*#c8321e/.test(light) &&
      /--ord-1:\s*#8a6d00/.test(light) &&
      /--ord-2:\s*#1f5fae/.test(light),
    light.replace(/\s+/g, " ").slice(0, 160),
  );
  check(
    "dark ordinal ink = --ord-0/1/2 (#e05a4a/#ffd93d/#5aa0e8)",
    /--ord-0:\s*#e05a4a/.test(dark) &&
      /--ord-1:\s*#ffd93d/.test(dark) &&
      /--ord-2:\s*#5aa0e8/.test(dark),
    dark.replace(/\s+/g, " ").slice(0, 160),
  );
  check(
    "the retired kind vars are gone (colour answers 'which wheel', not 'what does it do')",
    !/--term-phase|--term-radius|--term-k|--term-fixed/.test(html),
  );
  const ordRule = (n) => {
    const r = html.match(new RegExp("\\.col:nth-child\\(" + n + "\\) \\{[^}]*\\}"));
    return r !== null && new RegExp("color:\\s*var\\(--ord-" + (n - 1) + "\\)").test(r[0]);
  };
  check(
    "each column wears its ordinal ink (nth-child n → var(--ord-n-1))",
    ordRule(1) && ordRule(2) && ordRule(3),
  );
  check(
    "the glyph svg inherits the column ink (stroke: currentColor, fill: none, ~20px)",
    /\.glyph \.icon \{[^}]*width:\s*20px[^}]*height:\s*20px/s.test(html) &&
      /\.glyph \.icon[^{]*\{[^}]*stroke:\s*currentColor/s.test(html) &&
      /\.glyph \.icon[^{]*\{[^}]*fill:\s*none/s.test(html) &&
      /\.glyph[^{]*\{[^}]*color:\s*inherit/s.test(html),
  );

  // Glyph buttons read as BUTTONS: they keep the global chrome (the retired
  // +/− steppers' line border, 10px radius, card fill) and only override what
  // icon-only needs. Stripping the chrome back to bare icons is the regression.
  const glyphRule = html.match(/\n\.glyph \{[^}]*\}/);
  check(
    "glyph buttons wear the button chrome (line border, 10px radius, card fill — not stripped)",
    buttonRule !== null &&
      glyphRule !== null &&
      /border:\s*1\.5px solid var\(--line\)/.test(buttonRule[0]) &&
      /border-radius:\s*10px/.test(buttonRule[0]) &&
      /background:\s*var\(--card\)/.test(buttonRule[0]) &&
      !/border:\s*0(?![.\d])/.test(glyphRule[0]) &&
      !/border-radius:\s*0(?![.\d])/.test(glyphRule[0]) &&
      !/background:\s*none/.test(glyphRule[0]),
    "glyph rule: " +
      (glyphRule ? glyphRule[0].replace(/\s+/g, " ") : "missing") +
      " · button rule: " +
      (buttonRule ? buttonRule[0].replace(/\s+/g, " ").slice(0, 120) : "missing"),
  );
  check(
    "glyph buttons take the global :active fill (no background:none override)",
    !/\.glyph:active[^{]*\{[^}]*background:\s*none/.test(html),
  );

  // The rows and their readouts are gone from the stylesheet.
  check(
    "the retired row/readout/kind CSS is gone",
    !/\n\.rows \{/.test(html) &&
      !/\n\.row \{/.test(html) &&
      !/\n\.val \{/.test(html) &&
      !/\n\.id \{/.test(html) &&
      !/\.kind-(phase|radius|k|fixed)/.test(html),
  );
}

// ==== S1 · boot straight into the quaver board + the column DOM contract =====
console.log("S1 · cold load — quaver board, three text-free dial columns, icon glyphs");
const dom = boot_dom();
let state = initial_state();
tick(); // boot retry binds the canvases (init effects ran pre-render)
tick(34, 5); // draw frames
{
  const doc = dom.window.document;
  const ops = canvas_ops(dom);
  check("canvas booted and painted", ops && ops.arc >= 5, "arcs " + (ops && ops.arc));
  check("no NaN coordinates", ops && ops.nan === 0, "nan " + (ops && ops.nan));
  check(
    "board backing store sized (600 = 300css × dpr2)",
    board_canvas(dom).width === 600,
    String(board_canvas(dom).width),
  );

  // -- the column DOM contract ------------------------------------------------
  const colEls = cols(dom);
  check("exactly three dial columns under the board", colEls.length === 3, "cols " + colEls.length);
  const anatomy =
    colEls.length === 3 &&
    [0, 1, 2].every((i) => {
      const c = colEls[i];
      return (
        c &&
        c.children.length === 3 &&
        c.children[0].tagName === "BUTTON" &&
        c.children[1].tagName === "CANVAS" &&
        c.children[1].id === "col-" + i &&
        c.children[2].tagName === "BUTTON"
      );
    });
  check(
    "each column is [glyph ↑][canvas col-N][glyph ↓]",
    anatomy,
    colEls.map((c) => [...c.children].map((e) => e.tagName + (e.id ? "#" + e.id : "")).join(" ")).join(" | "),
  );
  check(
    "the columns sit under the board canvas",
    (() => {
      const b = board_canvas(dom);
      const wrap = doc.querySelector(".cols");
      if (!b || !wrap) return false;
      return Boolean(b.compareDocumentPosition(wrap) & dom.window.Node.DOCUMENT_POSITION_FOLLOWING);
    })(),
  );
  check(
    "columns carry NO text (no labels, readouts, notes, 'term N')",
    colEls.length === 3 && colEls.map((c) => c.textContent.trim()).join("") === "",
    JSON.stringify(colEls.map((c) => c.textContent)),
  );
  check(
    "the retired row/readout nodes are gone",
    doc.querySelectorAll(".row, .val, .id, .sub").length === 0,
    "nodes " + doc.querySelectorAll(".row, .val, .id, .sub").length,
  );
  check(
    "no 'term N' string anywhere in the app",
    !/\bterm\s*[1-9]/i.test(doc.getElementById("app").textContent || ""),
    JSON.stringify((doc.getElementById("app").textContent || "").slice(0, 120)),
  );
  check(
    "no kind-* classes anywhere (ordinal identity, not kind identity)",
    doc.querySelector("[class*='kind-']") === null,
  );

  // -- the glyph buttons ------------------------------------------------------
  const buttons = [...doc.querySelectorAll(".cols button")];
  const labels = buttons.map((b) => b.getAttribute("aria-label")).sort();
  const expected = [...GLYPH_LABELS].sort();
  check(
    "exactly six glyph buttons with the exact aria-labels",
    buttons.length === 6 && JSON.stringify(labels) === JSON.stringify(expected),
    buttons.length + ": " + JSON.stringify(labels),
  );
  const iconOnly =
    buttons.length === 6 &&
    buttons.every((b) => b.querySelectorAll("svg").length === 1 && b.textContent.trim() === "");
  check("every glyph button is icon-only (one inline svg, no text)", iconOnly);
  const upDown =
    colEls.length === 3 &&
    ["phase", "radius", "k"].every((kind, i) => {
      const c = colEls[i];
      return (
        c.children[0] &&
        c.children[0].getAttribute("aria-label") === "increase " + kind &&
        c.children[2] &&
        c.children[2].getAttribute("aria-label") === "decrease " + kind
      );
    });
  check("up = +, down = −, kind from the slot's DialKind (not the ordinal)", upDown);

  // Glyph identity: motion-matching feather strokes (no platform emoji).
  const svg_of = (label) => glyph(dom, label) && glyph(dom, label).querySelector("svg");
  const has = (label, sel, re) => {
    const svg = svg_of(label);
    if (!svg) return false;
    return [...svg.querySelectorAll(sel)].some((n) => re.test(n.getAttribute("points") || n.getAttribute("d") || ""));
  };
  check(
    "phase ↑ is rotate-cw (the phase pair is Q6-ruled: up = +5° = clockwise)",
    has("increase phase", "polyline", /^23 4 23 10 17 10$/) && has("increase phase", "path", /M20\.49 15/),
    text(svg_of("increase phase")),
  );
  check(
    "phase ↓ is rotate-ccw",
    has("decrease phase", "polyline", /^1 4 1 10 7 10$/) && has("decrease phase", "path", /M3\.51 15/),
  );
  check(
    "radius ↑ is expand (maximize-2)",
    has("increase radius", "polyline", /^15 3 21 3 21 9$/) && has("increase radius", "polyline", /^9 21 3 21 3 15$/),
  );
  check(
    "radius ↓ is contract (minimize-2)",
    has("decrease radius", "polyline", /^4 14 10 14 10 20$/) && has("decrease radius", "polyline", /^20 10 14 10 14 4$/),
  );
  check(
    "k ↑ is fast-forward (two right-pointing triangles)",
    has("increase k", "polygon", /^13 19 22 12 13 5 13 19$/) && has("increase k", "polygon", /^2 19 11 12 2 5 2 19$/),
  );
  check(
    "k ↓ is rewind (two left-pointing triangles)",
    has("decrease k", "polygon", /^11 19 2 12 11 5 11 19$/) && has("decrease k", "polygon", /^22 19 13 12 22 5 22 19$/),
  );

  // -- the columns painted, from the live state --------------------------------
  const painted = [0, 1, 2].every((i) => {
    const f = last_frame(dom, "col-" + i);
    return f && f.strokes.length > 0;
  });
  check("all three column canvases painted", painted);
  const c0 = doc.getElementById("col-0");
  check(
    "column canvases fitted like the board (256×208 = 128×104 × dpr2)",
    c0 !== null && c0.width === 256 && c0.height === 208,
    c0 ? c0.width + "×" + c0.height : "missing",
  );
  check(
    "the phase column's start marker sits at the 355° start (φ is the dial)",
    angle_close(marker_deg(dom), 355),
    "marker " + marker_deg(dom),
  );
  const startRing = (73 / 100) * (1 / 2) * COL_SPACE; // r / (2·dial_max_r) × space
  check(
    "the radius column's ring is the 73% start",
    close(ring_radius(dom, 1), startRing, 0.6),
    ring_radius(dom, 1) + " vs " + startRing.toFixed(2),
  );
  check(
    "the columns paint in ordinal ink (red/yellow/blue for slots 1/2/3)",
    col_ink(dom, 0) === "#c8321e" && col_ink(dom, 1) === "#8a6d00" && col_ink(dom, 2) === "#1f5fae",
    [col_ink(dom, 0), col_ink(dom, 1), col_ink(dom, 2)].join(" · "),
  );

  // -- the bar: score, reset (skip-back), theme --------------------------------
  const expect = puzzle.fmt1(match_of(state));
  check(
    "score shows the core-computed initial match",
    score_val(dom) === expect + "%",
    "dom " + score_val(dom) + " vs core " + expect + "%",
  );
  check(
    "title is the single puzzle (quaver)",
    text(dom.window.document.querySelector("h2.pt")) === "quaver",
    text(dom.window.document.querySelector("h2.pt")),
  );
  check("counter starts at zero (· 0 changes)", counter(dom) === "· 0 changes", JSON.stringify(counter(dom)));
  check(
    "no routing chrome: no home cards, no back link",
    dom.window.document.querySelector("a.card") === null && dom.window.document.querySelector("a.back") === null,
  );

  const themeBtn = doc.querySelector("button.theme");
  const resetBtn = doc.querySelector("button.reset");
  check(
    "bar: unboxed score (b), icon chips — reset (skip-back, aria) + theme",
    doc.querySelector(".score b") !== null &&
      themeBtn &&
      themeBtn.getAttribute("aria-label") === "dark mode" &&
      themeBtn.querySelector("svg.icon") !== null &&
      resetBtn !== null &&
      resetBtn.getAttribute("aria-label") === "reset to start" &&
      resetBtn.querySelector("svg.icon") !== null,
    "reset: " + (resetBtn ? resetBtn.getAttribute("aria-label") : "missing") +
      ", theme aria: " + (themeBtn ? themeBtn.getAttribute("aria-label") : "missing"),
  );
  const resetSvg = resetBtn && resetBtn.querySelector("svg");
  const resetPoly = resetSvg && resetSvg.querySelector("polygon");
  const resetLine = resetSvg && resetSvg.querySelector("line");
  check(
    "reset chip is skip-back-to-start (bar + triangle), not rotate-ccw",
    resetPoly !== null &&
      resetPoly !== undefined &&
      resetPoly.getAttribute("points") === "19 20 9 12 19 4 19 20" &&
      resetLine !== null &&
      resetLine !== undefined &&
      resetLine.getAttribute("x1") === "5" &&
      resetLine.getAttribute("y1") === "19" &&
      resetLine.getAttribute("x2") === "5" &&
      resetLine.getAttribute("y2") === "5" &&
      !(resetSvg.querySelector("polyline") &&
        resetSvg.querySelector("polyline").getAttribute("points") === "1 4 1 10 7 10"),
    resetSvg ? resetSvg.outerHTML.slice(0, 120) : "missing",
  );
  check(
    "the score bar keeps its text (Match %, · N changes, solved ✓)",
    text(doc.querySelector(".score")) !== null &&
      /Match/.test(doc.querySelector(".score").textContent) &&
      /changes/.test(doc.querySelector(".score").textContent) &&
      text(doc.querySelector(".score .ok")) === "solved ✓",
    text(doc.querySelector(".score")),
  );
}

// ==== S2 · dial behavior — wrap, ground-truth steps, edge disables =============
console.log("S2 · dial behavior — wrap, ground-truth steps, edge disables");
{
  const doc = dom.window.document;
  // phase wrap: a full lap of +5° steps returns to the start, never disabling
  let clicked = 0;
  for (let i = 0; i < 72; i++) {
    if (!click_label(dom, "increase phase")) break;
    state = step_slot(state, 0, 1);
    clicked++;
    tick();
  }
  const upPhase = glyph(dom, "increase phase");
  const downPhase = glyph(dom, "decrease phase");
  check(
    "phase steps a full wrap (72 × +5° = one lap) without ever disabling",
    clicked === 72 && upPhase && downPhase && !upPhase.disabled && !downPhase.disabled,
    "clicks " + clicked + ", up disabled " + (upPhase && upPhase.disabled) + ", down disabled " + (downPhase && downPhase.disabled),
  );
  check(
    "the wrap lands back on the 355° start marker",
    angle_close(marker_deg(dom), 355),
    "marker " + marker_deg(dom),
  );
  check(
    "the score tracks the core after the wrap",
    clicked === 72 && score_val(dom) === core_score(state),
    "dom " + score_val(dom) + " vs core " + core_score(state),
  );
  check("every step counted (· 72 changes)", counter(dom) === "· 72 changes", JSON.stringify(counter(dom)));

  // BEFORE any solve, reset starts a fresh attempt: the counter zeroes.
  doc.querySelector("button.reset").click();
  state = initial_state();
  tick(34, 2);
  check(
    "reset before any solve zeroes the counter",
    counter(dom) === "· 0 changes",
    JSON.stringify(counter(dom)),
  );
  check(
    "reset restores the phase start marker (355°)",
    angle_close(marker_deg(dom), 355),
    "marker " + marker_deg(dom),
  );

  // radius floor: 73% needs 37 × −2% steps to reach 0% (and disable contract)
  let btn = glyph(dom, "decrease radius");
  let clicks = 0;
  while (btn && !btn.disabled && clicks < 200) {
    btn.click();
    state = step_slot(state, 1, -1);
    clicks++;
    tick();
    btn = glyph(dom, "decrease radius");
  }
  check(
    "radius floors at 0% after 37 × −2% steps and disables contract",
    clicks === 37 && btn && btn.disabled,
    "clicks " + clicks + ", disabled " + (btn && btn.disabled),
  );
  const emptyFrame = last_frame(dom, "col-1");
  check(
    "the empty radius column draws nothing (0% = no ring, no arm, no pen)",
    emptyFrame !== null && emptyFrame.strokes.length === 0,
    "strokes " + (emptyFrame ? emptyFrame.strokes.length : "no frame"),
  );
  const upRadius = glyph(dom, "increase radius");
  check("radius expand stays enabled at the floor", upRadius !== null && !upRadius.disabled);
  click_label(dom, "increase radius");
  state = step_slot(state, 1, 1);
  tick();
  check("a 2% radius step draws a ring again", ring_radius(dom, 1) !== null && ring_radius(dom, 1) > 0, String(ring_radius(dom, 1)));
  check(
    "the counter tracks every radius step (37 + 1 = 38)",
    counter(dom) === "· 38 changes",
    JSON.stringify(counter(dom)),
  );

  // radius ceiling: from the 73% start, 64 × +2% reaches the 200% clamp
  doc.querySelector("button.reset").click();
  state = initial_state();
  tick(34, 2);
  btn = glyph(dom, "increase radius");
  clicks = 0;
  while (btn && !btn.disabled && clicks < 200) {
    btn.click();
    state = step_slot(state, 1, 1);
    clicks++;
    tick();
    btn = glyph(dom, "increase radius");
  }
  check(
    "radius expands to the 200% ceiling after 64 × +2% steps and disables expand",
    clicks === 64 && btn && btn.disabled,
    "clicks " + clicks + ", disabled " + (btn && btn.disabled),
  );
  check(
    "the ceiling ring fills the circle space exactly (200% = the space)",
    close(ring_radius(dom, 1), COL_SPACE, 0.6),
    ring_radius(dom, 1) + " vs " + COL_SPACE,
  );
  const downRadius = glyph(dom, "decrease radius");
  check("radius contract stays enabled at the ceiling", downRadius !== null && !downRadius.disabled);

  // k clamps: fast-forward from −5 reaches +16 in 21 steps, rewind −16 in 11
  doc.querySelector("button.reset").click();
  state = initial_state();
  tick(34, 2);
  btn = glyph(dom, "increase k");
  clicks = 0;
  while (btn && !btn.disabled && clicks < 100) {
    btn.click();
    state = step_slot(state, 2, 1);
    clicks++;
    tick();
    btn = glyph(dom, "increase k");
  }
  check(
    "k clamps at +16 after 21 steps (from −5) and disables fast-forward",
    clicks === 21 && btn && btn.disabled,
    "clicks " + clicks + ", disabled " + (btn && btn.disabled),
  );
  check(
    "the score tracks the core at k +16",
    clicks === 21 && score_val(dom) === core_score(state),
    "clicks " + clicks + ", dom " + score_val(dom) + " vs core " + core_score(state),
  );

  doc.querySelector("button.reset").click();
  state = initial_state();
  tick(34, 2);
  btn = glyph(dom, "decrease k");
  clicks = 0;
  while (btn && !btn.disabled && clicks < 100) {
    btn.click();
    state = step_slot(state, 2, -1);
    clicks++;
    tick();
    btn = glyph(dom, "decrease k");
  }
  check(
    "k clamps at −16 after 11 steps (from −5) and disables rewind",
    clicks === 11 && btn && btn.disabled,
    "clicks " + clicks + ", disabled " + (btn && btn.disabled),
  );
  check(
    "the score tracks the core at k −16",
    clicks === 11 && score_val(dom) === core_score(state),
    "clicks " + clicks + ", dom " + score_val(dom) + " vs core " + core_score(state),
  );
}

// ==== S3 · hold-to-repeat on the glyph buttons =================================
console.log("S3 · hold-to-repeat — glyph buttons auto-step, tap steps once");
{
  const doc = dom.window.document;
  doc.querySelector("button.reset").click();
  state = initial_state();
  tick(34, 2);
  const fire = (name, el) =>
    el.dispatchEvent(new dom.window.Event(name, { bubbles: true }));
  const c0 = counter_n(dom);
  const btn = glyph(dom, "decrease phase");
  let held = false;
  let n = 0;
  if (btn) {
    held = true;
    fire("pointerdown", btn);
    await sleep(700);
    fire("pointerup", btn);
    tick(34, 3); // flush the RAF-pending renders the repeats scheduled
    const c1 = counter_n(dom);
    n = c1 !== null && c0 !== null ? c1 - c0 : 0;
  }
  check("hold auto-repeats the glyph (≥ 2 steps in 700ms)", held && n >= 2, "n=" + n);
  for (let i = 0; i < n; i++) state = step_slot(state, 0, -1);
  check(
    "each repeat tick counts as a change",
    held && counter_n(dom) === c0 + n,
    c0 + " + " + n + " vs " + counter_n(dom),
  );
  check(
    "the score matches the core after n repeat steps",
    held && n >= 2 && score_val(dom) === core_score(state),
    "dom " + score_val(dom) + " vs core " + core_score(state),
  );
  check(
    "the phase marker matches the core after the repeats",
    angle_close(marker_deg(dom), Array.from(state)[0].phase_deg),
    "marker " + marker_deg(dom) + " vs " + Array.from(state)[0].phase_deg,
  );

  // the natural release-click after a repeated hold must be swallowed
  if (btn) {
    fire("click", btn);
    tick();
  }
  check(
    "release click after a hold is swallowed (no double-step)",
    held && counter_n(dom) === c0 + n,
    c0 + " + " + n + " vs " + counter_n(dom),
  );
  // a QUICK TAP (down+up inside the repeat threshold) steps exactly once
  if (btn) {
    fire("pointerdown", btn);
    fire("pointerup", btn);
    fire("click", btn);
    tick(34, 2);
  }
  state = step_slot(state, 0, -1);
  check(
    "quick tap steps exactly once",
    held && counter_n(dom) === c0 + n + 1 && score_val(dom) === core_score(state),
    counter_n(dom) + " vs " + (c0 + n + 1) + ", score " + score_val(dom) + " vs " + core_score(state),
  );
}

// ==== S4 · dial-home solve path — from wherever the dials now stand ============
console.log("S4 · dial-home solve path — every dialable at (or nearest to) truth ⇒ solved");
let moves_at_solve = null;
{
  const doc = dom.window.document;
  const truth = Array.from(shape.dial);
  const cur = Array.from(state);
  let walked = true;
  // phase: shortest direction around the dial, from the CURRENT phase
  const up = ((truth[0].phase_deg - cur[0].phase_deg + 360) % 360) / 5;
  const down = ((cur[0].phase_deg - truth[0].phase_deg + 360) % 360) / 5;
  const pdir = up <= down ? 1 : -1;
  for (let i = 0; i < Math.min(up, down); i++) {
    if (!click_label(dom, pdir > 0 ? "increase phase" : "decrease phase")) {
      walked = false;
      break;
    }
    state = step_slot(state, 0, pdir);
    tick();
  }
  // radius: nearest reachable step to truth (unit = 2% of max)
  const unit = 0.02 * shape.dial_max_r;
  const r_delta = truth[1].r - cur[1].r;
  const rdir = r_delta >= 0 ? 1 : -1;
  const rsteps = Math.round(Math.abs(r_delta) / unit);
  for (let i = 0; i < rsteps && walked; i++) {
    if (!click_label(dom, rdir > 0 ? "increase radius" : "decrease radius")) {
      walked = false;
      break;
    }
    state = step_slot(state, 1, rdir);
    tick();
  }
  // k: straight to truth
  const kdir = truth[2].k >= cur[2].k ? 1 : -1;
  const ksteps = Math.abs(truth[2].k - cur[2].k);
  for (let i = 0; i < ksteps && walked; i++) {
    if (!click_label(dom, kdir > 0 ? "increase k" : "decrease k")) {
      walked = false;
      break;
    }
    state = step_slot(state, 2, kdir);
    tick();
  }
  tick(34, 3);
  check(
    "the dial-home walk reaches the core's state",
    walked && score_val(dom) === core_score(state),
    "dom " + score_val(dom) + " vs core " + core_score(state),
  );
  check(
    "solved badge appears at ≥ 95%",
    doc.querySelector(".score.solved") !== null,
    "score " + score_val(dom),
  );

  // the counter freezes at the FIRST solve: further steps stop counting,
  // and it stays frozen even after dialing back into unsolved territory
  moves_at_solve = counter_n(dom);
  const extraStep = click_label(dom, "increase phase"); // +5° past truth
  state = step_slot(state, 0, 1);
  tick(34, 2);
  check(
    "counter frozen at the first solve (extra step doesn't count)",
    extraStep !== null && counter_n(dom) === moves_at_solve,
    moves_at_solve + " → " + counter_n(dom),
  );
  const awayStep = click_label(dom, "decrease k"); // k off truth — definitely unsolved now
  state = step_slot(state, 2, -1);
  tick(34, 2);
  check(
    "counter stays frozen after dialing away",
    awayStep !== null && counter_n(dom) === moves_at_solve,
    moves_at_solve + " → " + counter_n(dom),
  );
  check(
    "badge drops when unsolved again",
    extraStep !== null && awayStep !== null && !doc.querySelector(".score.solved"),
  );
  check(
    "the score still tracks the core after the post-solve steps",
    walked && score_val(dom) === core_score(state),
    "dom " + score_val(dom) + " vs core " + core_score(state),
  );
}

// ==== S5 · reset — dials back to start, the solved record survives ==========
console.log("S5 · reset — dials to start; the number you solved in is the number you keep");
{
  const doc = dom.window.document;
  doc.querySelector("button.reset").click();
  state = initial_state();
  tick(34, 2);
  check(
    "reset restores the initial match",
    moves_at_solve > 0 && score_val(dom) === core_score(state),
    "dom " + score_val(dom) + " vs core " + core_score(state),
  );
  check(
    "reset restores the start marker (355°)",
    angle_close(marker_deg(dom), 355),
    "marker " + marker_deg(dom),
  );
  check(
    "badge gone after reset (unsolved again)",
    moves_at_solve > 0 && !doc.querySelector(".score.solved"),
  );
  check(
    "the solved record survives reset (counter unchanged)",
    moves_at_solve > 0 && counter_n(dom) === moves_at_solve,
    moves_at_solve + " vs " + counter_n(dom),
  );
  // play after a solved reset does NOT re-count — the record is final
  const kStep = click_label(dom, "increase k"); // k −5 → −4
  state = step_slot(state, 2, 1);
  tick();
  check(
    "steps after a solved reset don't count (record is final)",
    moves_at_solve > 0 && kStep !== null && counter_n(dom) === moves_at_solve,
    moves_at_solve + " vs " + counter_n(dom),
  );
  check(
    "but the dial still steps (score follows the core for k −4)",
    kStep !== null && score_val(dom) === core_score(state),
    "dom " + score_val(dom) + " vs core " + core_score(state),
  );
}

// ==== S6 · theme toggle ========================================================
console.log("S6 · theme toggle mirrors onto the body and the columns");
{
  const doc = dom.window.document;
  const themeBtn = () => doc.querySelector("button.theme");
  const lightInks = [col_ink(dom, 0), col_ink(dom, 1), col_ink(dom, 2)];
  check(
    "the columns start in the light ordinal palette",
    lightInks[0] === "#c8321e" && lightInks[1] === "#8a6d00" && lightInks[2] === "#1f5fae",
    lightInks.join(" · "),
  );
  themeBtn().click();
  tick(34, 2);
  check("body flips to dark", doc.body.getAttribute("data-theme") === "dark");
  check(
    "choice saved to localStorage (f-toy-theme: dark)",
    dom.window.localStorage.getItem("f-toy-theme") === "dark",
    JSON.stringify(dom.window.localStorage.getItem("f-toy-theme")),
  );
  check(
    "chip flips to the sun (aria-label light mode, icon swaps)",
    themeBtn().getAttribute("aria-label") === "light mode" &&
      themeBtn().querySelectorAll("svg.icon line").length > 0,
  );
  const darkInks = [col_ink(dom, 0), col_ink(dom, 1), col_ink(dom, 2)];
  check(
    "the columns follow to the dark ordinal palette",
    darkInks[0] === "#e05a4a" && darkInks[1] === "#ffd93d" && darkInks[2] === "#5aa0e8",
    darkInks.join(" · "),
  );
  const boardDark = board_inks(dom);
  check(
    "the board's term circles re-ink to the same dark ordinal palette",
    boardDark.has("#e05a4a") && boardDark.has("#ffd93d") && boardDark.has("#5aa0e8"),
    [...boardDark].join(","),
  );
  themeBtn().click();
  tick(34, 2);
  check("body flips back to light", doc.body.getAttribute("data-theme") === "light");
  check(
    "choice updated in localStorage (f-toy-theme: light)",
    dom.window.localStorage.getItem("f-toy-theme") === "light",
    JSON.stringify(dom.window.localStorage.getItem("f-toy-theme")),
  );
  const backInks = [col_ink(dom, 0), col_ink(dom, 1), col_ink(dom, 2)];
  check(
    "the columns return to the light ordinal palette",
    backInks[0] === "#c8321e" && backInks[1] === "#8a6d00" && backInks[2] === "#1f5fae",
    backInks.join(" · "),
  );
}

// ==== S7 · theme persistence ==================================================
console.log("S7 · theme persistence — stored choice beats system preference");
{
  const chipOf = (d) => d.window.document.querySelector("button.theme");
  const bodyTheme = (d) => d.window.document.body.getAttribute("data-theme");

  const storedDark = boot_dom({ stored: "dark", systemDark: false });
  tick();
  check(
    "stored dark boots dark (stored beats system light)",
    bodyTheme(storedDark) === "dark" && chipOf(storedDark).getAttribute("aria-label") === "light mode",
    "body " + bodyTheme(storedDark),
  );

  const storedLightSysDark = boot_dom({ stored: "light", systemDark: true });
  tick();
  check(
    "stored light boots light (stored beats system dark)",
    bodyTheme(storedLightSysDark) === "light" && chipOf(storedLightSysDark).getAttribute("aria-label") === "dark mode",
    "body " + bodyTheme(storedLightSysDark),
  );

  const noStoredSysDark = boot_dom({ systemDark: true });
  tick();
  check(
    "no stored choice: system preference applies (dark)",
    bodyTheme(noStoredSysDark) === "dark",
    "body " + bodyTheme(noStoredSysDark),
  );
}


// ==== S8 · the daily puzzle: fetch → board → store → telemetry ==============
// PLAN-daily-puzzles.md §1. The served document is an OLD-FORMAT one (four
// dial kinds, the fourth "fixed"): the board normalizes it to the three
// dialable terms plus the fixed term as an extra (PLAN-dial-columns §3), so
// the served shape's synthesis is the quaver's own — the dial-home walk below
// really solves. The name, date and start differ, so the board proves it took
// the fetched puzzle over. The wiring under test is the toy's, not the
// derivation's — the derivation has its own gold tests in toy_admin.
console.log("S8 · daily puzzle — fetch, resume (schema v2), solve POST, abandon, new day");

const DAILY_NAME = "the quaver, published";
const DAILY_DATE = "2026-10-26";
const OLD_DATE = "2026-10-25";

// patch constructors, as the app's core would build them ([phase, radius%, k])
const patches_of = (list) =>
  toList([
    puzzle.Patch$PhaseDeg(list[0]),
    puzzle.Patch$RPct(list[1]),
    puzzle.Patch$KSet(list[2]),
  ]);
const daily_start_patches = patches_of([90.0, 50.0, 2]);

const term_row = (t) => ({ k: t.k, radius: t.r, phase: t.phase_deg });
const Q_EXTRAS = Array.from(shape.extras);
const daily_doc = () => ({
  status: "ok",
  puzzle: {
    name: DAILY_NAME,
    showDate: DAILY_DATE,
    dots: [
      [10, 50],
      [90, 50],
    ],
    centroid: [shape.centroid[0], shape.centroid[1]],
    // the deployed backend's arrangement: phase, radius, k, then the retired
    // fixed slot (its term and its "keep" patch are normalized away)
    dials: ["phase", "radius", "k", "fixed"],
    dial: [...Array.from(shape.dial, term_row), term_row(Q_EXTRAS[0])],
    extras: Q_EXTRAS.slice(1).map(term_row),
    patches: [
      { kind: "phase", deg: 90.0 },
      { kind: "radius", pct: 50.0 },
      { kind: "k", k: 2 },
      { kind: "keep" },
    ],
    target: Array.from(shape.target, (p) => [p[0], p[1]]),
  },
});
const daily_json = () => JSON.stringify(daily_doc());

// the app derives these client-side (shapes.from_parts over the normalized
// document) — the ground truth for the daily board's score is the same
// derivation; normalizing the served doc restores the quaver's own term set
const daily_shape = shapes.from_parts(
  DAILY_NAME,
  shape.centroid,
  shape.dial,
  shape.extras,
  shape.target,
);
const daily_initial = () => puzzle.initial(daily_shape, daily_start_patches);

// the walk S8d performs through the UI, computed on the core: phase the
// shortest way round, radius to its nearest step, then k — [[slot, dir], ...]
function walk_moves(shape_, kinds, start) {
  const cur = Array.from(start);
  const truth = Array.from(shape_.dial);
  const moves = [];
  const push = (slot, dir) => {
    cur[slot] = puzzle.step(kinds[slot], cur[slot], dir, shape_.dial_max_r);
    moves.push([slot, dir]);
  };
  const up = ((truth[0].phase_deg - cur[0].phase_deg + 360) % 360) / 5;
  const down = ((cur[0].phase_deg - truth[0].phase_deg + 360) % 360) / 5;
  const pdir = up <= down ? 1 : -1;
  for (let i = 0; i < Math.min(up, down); i++) push(0, pdir);
  const unit = 0.02 * shape_.dial_max_r;
  const rdir = truth[1].r - cur[1].r >= 0 ? 1 : -1;
  const rsteps = Math.round(Math.abs(truth[1].r - cur[1].r) / unit); // snapshot too
  for (let i = 0; i < rsteps; i++) push(1, rdir);
  const kdir = truth[2].k >= cur[2].k ? 1 : -1;
  const ksteps = Math.abs(truth[2].k - cur[2].k); // snapshot: push() mutates cur
  for (let i = 0; i < ksteps; i++) push(2, kdir);
  return { state: cur, moves };
}
const DAILY_KINDS = [
  puzzle.DialKind$DialP$const,
  puzzle.DialKind$DialR$const,
  puzzle.DialKind$DialK$const,
];
const daily_walk = walk_moves(daily_shape, DAILY_KINDS, daily_initial());
const daily_walk_state = () => toList(daily_walk.state);
const GLYPH = [
  ["increase phase", "decrease phase"],
  ["increase radius", "decrease radius"],
  ["increase k", "decrease k"],
];
const click_move = (dom, slot, dir) => click_label(dom, GLYPH[slot][dir > 0 ? 0 : 1]);

// the stored attempt, in the app's own schema v2 (`j-att`, see attempt.gleam)
const attempt_json = (fields) =>
  JSON.stringify({
    v: 2,
    date: fields.date,
    state: (fields.state || Array.from(daily_initial())).map((s) => ({
      k: s.k,
      r: s.r,
      phase: s.phase_deg,
    })),
    moves: fields.moves || [],
    count: fields.count,
    solved: !!fields.solved,
    reported: !!fields.reported,
  });

// a pre-change (v1) attempt: four terms, the retired schema — stale by the
// sanctioned version bump, so the board must start fresh, never crash
const STALE_V1 = JSON.stringify({
  v: 1,
  date: DAILY_DATE,
  state: [
    { k: -1, r: 17.97, phase: 90 },
    { k: 1, r: 8.985, phase: 305 },
    { k: 2, r: 4.68, phase: 260 },
    { k: -14, r: 0.5, phase: 270 },
  ],
  moves: [[0, 1]],
  count: 1,
  solved: false,
  reported: false,
});

const posts = (d) => d.window.__calls.filter((c) => c.method === "POST");
const gets = (d) => d.window.__calls.filter((c) => c.method === "GET");
const stored_attempt = (d) => {
  const raw = d.window.localStorage.getItem("j-att");
  return raw === null ? null : JSON.parse(raw);
};
const h2_text = (d) => text(d.window.document.querySelector("h2.pt"));
const when_text = (d) => text(d.window.document.querySelector("h2.pt .when"));
const uuid_now = (d) => d.window.localStorage.getItem("j-uid");

// ==== S8a · nothing published — the quaver, and NO telemetry ================
{
  const d = boot_dom(); // default fetchMode: {"status":"none"}
  check(
    "first paint is the quaver (before the fetch settles)",
    h2_text(d) === "quaver",
    h2_text(d),
  );
  await sleep(0); // let the fetch settle
  tick();
  check("no puzzle today: the board stays the quaver", h2_text(d) === "quaver", h2_text(d));
  check("no date tag on the fallback", when_text(d) === "", JSON.stringify(when_text(d)));
  check(
    "the quaver fallback boots into three dial columns",
    cols(d).length === 3,
    "cols " + cols(d).length,
  );
  check(
    "the fallback's score is the core's from the first paint",
    score_val(d) === core_score(initial_state()),
    "dom " + score_val(d) + " vs core " + core_score(initial_state()),
  );
  check(
    "the fallback tells no telemetry (no POST at all)",
    posts(d).length === 0,
    JSON.stringify(posts(d)),
  );
  check(
    "the fallback stores no attempt ('j-att' untouched)",
    stored_attempt(d) === null,
    JSON.stringify(stored_attempt(d)),
  );
  const get = gets(d)[0];
  check(
    "the fetch asked for today in the visitor's own tz (minutes to ADD)",
    get && /^\/api\/puzzle\/today\?tz=-?\d+$/.test(get.url),
    get ? get.url : "no GET",
  );
  check(
    "the anonymous identity is created anyway (site-wide, Q16)",
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(
      uuid_now(d) || "",
    ),
    String(uuid_now(d)),
  );
}

// ==== S8b · a fetched (old-format) puzzle takes the board over =============
let daily_dom = null;
{
  const d = boot_dom({ fetchMode: "ok", fetchBody: daily_json() });
  check(
    "the quaver paints first even with a puzzle waiting",
    h2_text(d) === "quaver",
    h2_text(d),
  );
  await sleep(0);
  tick(34, 2);
  daily_dom = d;
  check("the served puzzle's name is the title", h2_text(d).startsWith(DAILY_NAME), h2_text(d));
  check("the show date rides beside the name", when_text(d).includes(DAILY_DATE), when_text(d));
  check(
    "the served (old-format) document normalizes into three dial columns",
    cols(d).length === 3,
    "cols " + cols(d).length,
  );
  check(
    "the phase marker sits where the served 90° patch puts it",
    angle_close(marker_deg(d), 90),
    "marker " + marker_deg(d),
  );
  const servedRing = (50 / 100) * (1 / 2) * COL_SPACE;
  check(
    "the radius ring carries the served 50% start",
    close(ring_radius(d, 1), servedRing, 0.6),
    ring_radius(d, 1) + " vs " + servedRing.toFixed(2),
  );
  check(
    "the score is the core's match for the served start",
    score_val(d) === core_score(daily_initial()),
    "dom " + score_val(d) + " vs core " + core_score(daily_initial()),
  );
  check("a fresh attempt starts at zero", counter(d) === "· 0 changes", JSON.stringify(counter(d)));
  check("no POST at boot (nothing solved, nothing abandoned)", posts(d).length === 0);
  const stored = stored_attempt(d);
  check(
    "today's attempt is stored in schema v2 (date, zeroed counter, unsolved)",
    stored &&
      stored.v === 2 &&
      stored.date === DAILY_DATE &&
      stored.count === 0 &&
      stored.solved === false &&
      stored.reported === false &&
      stored.moves.length === 0,
    JSON.stringify(stored && { v: stored.v, date: stored.date, count: stored.count }),
  );
  const start = Array.from(daily_initial());
  check(
    "the stored dial state is the served start (three terms)",
    stored &&
      Array.isArray(stored.state) &&
      stored.state.length === 3 &&
      stored.state.every(
        (row, i) => row.k === start[i].k && row.r === start[i].r && row.phase === start[i].phase_deg,
      ),
    JSON.stringify(stored && stored.state),
  );
  check("the board repainted for the new shape", canvas_ops(d).arc >= 5, "arcs " + canvas_ops(d).arc);
  check(
    "the columns repainted for the new shape",
    [0, 1, 2].every((i) => {
      const f = last_frame(d, "col-" + i);
      return f && f.strokes.length > 0;
    }),
  );
}

// ==== S8c · resume: a same-day v2 stored attempt ============================
{
  const seed_state = Array.from(daily_initial());

  seed_state[0] = puzzle.step(DAILY_KINDS[0], seed_state[0], 1, daily_shape.dial_max_r);
  seed_state[0] = puzzle.step(DAILY_KINDS[0], seed_state[0], 1, daily_shape.dial_max_r);
  seed_state[0] = puzzle.step(DAILY_KINDS[0], seed_state[0], 1, daily_shape.dial_max_r);
  const d = boot_dom({
    fetchMode: "ok",
    fetchBody: daily_json(),
    seed: {
      "j-att": attempt_json({
        date: DAILY_DATE,
        state: seed_state,
        moves: [
          [0, 1],
          [0, 1],
          [0, 1],
        ],
        count: 3,
      }),
    },
  });
  await sleep(0);
  tick(34, 2);
  check(
    "the stored v2 attempt resumes (90° + 3 steps = a 105° marker)",
    angle_close(marker_deg(d), 105),
    "marker " + marker_deg(d),
  );
  check("the stored counter is restored", counter(d) === "· 3 changes", JSON.stringify(counter(d)));
  check(
    "the restored score is the core's match for that state",
    score_val(d) === core_score(toList(seed_state)),
    "dom " + score_val(d) + " vs core " + core_score(toList(seed_state)),
  );
  check("resuming posts nothing", posts(d).length === 0, JSON.stringify(posts(d)));
  const stored = stored_attempt(d);
  check(
    "the stored attempt is left alone (v2, count 3, still unsolved)",
    stored && stored.v === 2 && stored.count === 3 && stored.solved === false,
    JSON.stringify(stored && { v: stored.v, count: stored.count, solved: stored.solved }),
  );
}

// ==== S8c2 · a stale v1 (4-term) stored attempt boots FRESH =================
{
  const d = boot_dom({
    fetchMode: "ok",
    fetchBody: daily_json(),
    seed: { "j-att": STALE_V1 },
  });
  await sleep(0);
  tick(34, 2);
  check(
    "a stale v1 (4-term) attempt boots fresh: today's puzzle, counter 0, no crash",
    h2_text(d).startsWith(DAILY_NAME) && counter(d) === "· 0 changes",
    h2_text(d) + " / " + counter(d),
  );
  check(
    "the stale document is replaced by a v2 fresh attempt (three terms)",
    (() => {
      const stored = stored_attempt(d);
      return stored && stored.v === 2 && stored.count === 0 && Array.isArray(stored.state) && stored.state.length === 3;
    })(),
    JSON.stringify(stored_attempt(d)),
  );
  check(
    "the stale attempt's start is the served start (90° marker)",
    angle_close(marker_deg(d), 90),
    "marker " + marker_deg(d),
  );
  check("a stale attempt posts nothing", posts(d).length === 0, JSON.stringify(posts(d)));
}

// ==== S8d · the solve moment posts ONCE =====================================
{
  const d = daily_dom;
  const uuid = uuid_now(d);
  for (const [slot, dir] of daily_walk.moves) {
    if (!click_move(d, slot, dir)) break;
    tick();
  }
  tick(34, 2);
  check(
    "the walk solves the board (badge shown)",
    d.window.document.querySelector(".score.solved") !== null,
    "score " + score_val(d),
  );
  check(
    "the walk reaches the core's solved state",
    score_val(d) === core_score(daily_walk_state()),
    "dom " + score_val(d) + " vs core " + core_score(daily_walk_state()),
  );
  const count = counter_n(d);
  let solve_calls = posts(d).filter((c) => c.url === "/api/solve");
  check("exactly one solve POST", solve_calls.length === 1, "got " + solve_calls.length);
  const body = solve_calls.length ? JSON.parse(solve_calls[0].body) : {};
  check(
    "the solve body carries the identity, the date and the moves played",
    body.uuid === uuid && body.puzzleDate === DAILY_DATE && Array.isArray(body.moves),
    JSON.stringify({ uuid: body.uuid === uuid, date: body.puzzleDate, moves: body.moves && body.moves.length }),
  );
  check(
    "the reported move list matches the frozen counter",
    body.moves && body.moves.length === count && body.moves[0].slot !== undefined && "dir" in body.moves[0],
    "moves " + (body.moves && body.moves.length) + " vs counter " + count,
  );
  // the solve POST is in flight: the record says solved-but-unreported until
  // the answer lands (a solve that never confirms is re-sent next boot)
  const inflight = stored_attempt(d);
  check(
    "while the solve POST is in flight the attempt is stored unsent (v2)",
    inflight && inflight.v === 2 && inflight.solved === true && inflight.reported === false && inflight.count === count,
    JSON.stringify(inflight && { v: inflight.v, solved: inflight.solved, reported: inflight.reported, count: inflight.count }),
  );
  await sleep(0); // the stubbed POST settles on a microtask
  tick();
  const stored = stored_attempt(d);
  check(
    "the confirmed solve is stored as solved + reported (nothing left to re-send)",
    stored && stored.solved === true && stored.reported === true && stored.count === count,
    JSON.stringify(stored && { solved: stored.solved, reported: stored.reported, count: stored.count }),
  );
  // further steps are free: the record is final and nothing is re-posted
  click_move(d, 0, 1);
  tick(34, 2);
  solve_calls = posts(d).filter((c) => c.url === "/api/solve");
  check("stepping after the solve re-posts nothing", solve_calls.length === 1, "got " + solve_calls.length);
  check(
    "and the counter stays frozen",
    counter_n(d) === count,
    count + " → " + counter_n(d),
  );
}

// ==== S8e · reset before a solve abandons the attempt =======================
{
  const d = boot_dom({ fetchMode: "ok", fetchBody: daily_json() });
  await sleep(0);
  tick(34, 2);
  const uuid = uuid_now(d);
  for (let i = 0; i < 4; i++) {
    click_move(d, 0, 1);
    tick();
  }
  check("four steps counted", counter(d) === "· 4 changes", JSON.stringify(counter(d)));
  check("no solve POST while unsolved", posts(d).filter((c) => c.url === "/api/solve").length === 0);
  d.window.document.querySelector("button.reset").click();
  tick(34, 2);
  const abandons = posts(d).filter((c) => c.url === "/api/attempts/abandon");
  check("reset abandons the played attempt (one POST)", abandons.length === 1, "got " + abandons.length);
  const body = abandons.length ? JSON.parse(abandons[0].body) : {};
  check(
    "the abandon body carries the OLD count and today's date",
    body.uuid === uuid && body.puzzleDate === DAILY_DATE && body.moves === 4,
    JSON.stringify({ date: body.puzzleDate, moves: body.moves }),
  );
  check("the counter zeroes on reset", counter(d) === "· 0 changes", JSON.stringify(counter(d)));
  check(
    "the dials go back to the served start (90° marker)",
    angle_close(marker_deg(d), 90),
    "marker " + marker_deg(d),
  );
  const stored = stored_attempt(d);
  check(
    "a fresh v2 attempt replaces it (same date, count 0)",
    stored && stored.v === 2 && stored.date === DAILY_DATE && stored.count === 0 && stored.moves.length === 0,
    JSON.stringify(stored && { v: stored.v, date: stored.date, count: stored.count, moves: stored.moves.length }),
  );
  // resetting an untouched attempt is not an abandonment
  d.window.document.querySelector("button.reset").click();
  tick(34, 2);
  check(
    "a reset with nothing played abandons nothing",
    posts(d).filter((c) => c.url === "/api/attempts/abandon").length === 1,
    "got " + posts(d).filter((c) => c.url === "/api/attempts/abandon").length,
  );
}

// ==== S8f · a new day retires yesterday's attempt ===========================
{
  const old_state = Array.from(daily_initial());
  for (let i = 0; i < 7; i++) {
    old_state[0] = puzzle.step(DAILY_KINDS[0], old_state[0], 1, daily_shape.dial_max_r);
  }
  const d = boot_dom({
    fetchMode: "ok",
    fetchBody: daily_json(),
    seed: {
      "j-att": attempt_json({
        date: OLD_DATE,
        state: old_state,
        moves: Array.from({ length: 7 }, () => [0, 1]),
        count: 7,
      }),
    },
  });
  await sleep(0);
  tick(34, 2);
  const abandons = posts(d).filter((c) => c.url === "/api/attempts/abandon");
  check(
    "yesterday's unsolved attempt is abandoned when today opens",
    abandons.length === 1,
    "got " + abandons.length,
  );
  const body = abandons.length ? JSON.parse(abandons[0].body) : {};
  check(
    "the abandon names the OLD date and its 7 moves",
    body.puzzleDate === OLD_DATE && body.moves === 7,
    JSON.stringify({ date: body.puzzleDate, moves: body.moves }),
  );
  const stored = stored_attempt(d);
  check(
    "today's v2 attempt takes its place",
    stored && stored.v === 2 && stored.date === DAILY_DATE && stored.count === 0,
    JSON.stringify(stored && { v: stored.v, date: stored.date, count: stored.count }),
  );
  check(
    "the board shows today's start, not yesterday's dials (90° marker, 0 changes)",
    angle_close(marker_deg(d), 90) && counter(d) === "· 0 changes",
    marker_deg(d) + " · " + counter(d),
  );
}

// ==== S8g · a solved day reloads solved — and re-reports only if it must ===
{
  const solved_state = daily_walk.state;
  const solved_count = daily_walk.moves.length;
  const d = boot_dom({
    fetchMode: "ok",
    fetchBody: daily_json(),
    seed: {
      "j-att": attempt_json({
        date: DAILY_DATE,
        state: solved_state,
        moves: daily_walk.moves,
        count: solved_count,
        solved: true,
        reported: true,
      }),
    },
  });
  await sleep(0);
  tick(34, 2);
  check(
    "the solved badge is restored on reload",
    d.window.document.querySelector(".score.solved") !== null,
    "score " + score_val(d),
  );
  check(
    "the solved-in number is restored",
    counter_n(d) === solved_count,
    solved_count + " vs " + counter_n(d),
  );
  check(
    "an already-reported solve posts nothing",
    posts(d).length === 0,
    JSON.stringify(posts(d)),
  );
  const stored = stored_attempt(d);
  check(
    "the stored record survives the reload untouched (v2)",
    stored && stored.v === 2 && stored.solved === true && stored.reported === true && stored.count === solved_count,
    JSON.stringify(stored && { v: stored.v, solved: stored.solved, reported: stored.reported, count: stored.count }),
  );

  // a solve whose POST never landed is re-sent on the next boot (the backend's
  // solve REPLACES the row, so a duplicate costs nothing)
  const unsent = boot_dom({
    fetchMode: "ok",
    fetchBody: daily_json(),
    seed: {
      "j-att": attempt_json({
        date: DAILY_DATE,
        state: solved_state,
        moves: daily_walk.moves,
        count: solved_count,
        solved: true,
        reported: false,
      }),
    },
  });
  await sleep(0);
  tick(34, 2);
  const resends = posts(unsent).filter((c) => c.url === "/api/solve");
  check("an unreported solve is re-sent exactly once", resends.length === 1, "got " + resends.length);
  const body = resends.length ? JSON.parse(resends[0].body) : {};
  check(
    "the re-sent solve carries the stored moves and date",
    body.puzzleDate === DAILY_DATE && body.moves && body.moves.length === solved_count,
    JSON.stringify({ date: body.puzzleDate, moves: body.moves && body.moves.length }),
  );
  const after = stored_attempt(unsent);
  check("the re-send marks the attempt reported", after && after.reported === true, JSON.stringify(after && after.reported));
}

// ==== S8h · network trouble is the fallback, not an error ===================
{
  for (const [label, opts] of [
    ["a rejected request (offline)", { fetchMode: "reject" }],
    ["a 500 from the API", { fetchMode: "http500" }],
    ["a document this decoder cannot use", { fetchMode: "ok", fetchBody: "<html>tunnel</html>" }],
  ]) {
    const d = boot_dom(opts);
    await sleep(0);
    tick(34, 2);
    check(
      label + ": the quaver stays (three columns), nothing is posted",
      h2_text(d) === "quaver" && cols(d).length === 3 && posts(d).length === 0,
      h2_text(d) + " / cols " + cols(d).length + " / posts " + posts(d).length,
    );
  }
  // a POST that fails changes nothing visible: the attempt stays unreported
  const d = boot_dom({ fetchMode: "ok", fetchBody: daily_json(), postFails: true });
  await sleep(0);
  tick(34, 2);
  for (const [slot, dir] of daily_walk.moves) {
    if (!click_move(d, slot, dir)) break;
    tick();
  }
  tick(34, 2);
  const stored = stored_attempt(d);
  check(
    "an unsent solve is stored as solved-but-unreported (the next boot retries)",
    stored && stored.v === 2 && stored.solved === true && stored.reported === false,
    JSON.stringify(stored && { v: stored.v, solved: stored.solved, reported: stored.reported }),
  );
  check(
    "the badge still shows (the player solved it, whatever the network did)",
    d.window.document.querySelector(".score.solved") !== null,
  );
}

console.log("");
console.log(passed + "/" + (passed + failed) + " checks passed");
if (failed > 0) process.exit(1);
