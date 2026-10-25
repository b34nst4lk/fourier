//// Puzzle configuration and dial state machine (pure, fully tested).
////
//// A Setup names one experiment: the shape, the dial kind per slot, and the
//// deterministic starting perturbation (see the JS prototype's vocabulary —
//// phase +90°, radius ~72% of max, k −2 on the kind-3 slot; same offsets
//// scaled per shape so cross-puzzle feels compare).
//// Dials: k ±1 clamped to ±16; phase ±5° wrapping 0..360; radius ±2% of the
//// shape's biggest dialable radius, clamped to 0..200%.

import fourier_toy/shapes.{type Shape, type TermState, mod360}
import gleam/float
import gleam/int
import gleam/list

pub type DialKind {
  DialP
  DialR
  DialK
  DialFixed
}

/// One starting perturbation for a slot; unpatched fields stay at truth.
pub type Patch {
  PhaseDeg(Float)
  RPct(Float)
  KSet(Int)
  Keep
}

pub type Setup {
  Setup(
    id: String,
    title: String,
    desc: String,
    shape: String,
    dials: List(DialKind),
    patches: List(Patch),
  )
}

const k_min = -16

const k_max = 16

pub fn k_step(s: TermState, dir: Int) -> TermState {
  let k = s.k + dir
  case k < k_min || k > k_max {
    True -> s
    False -> shapes.TermState(k, s.r, s.phase_deg)
  }
}

pub fn phase_step(s: TermState, dir: Int) -> TermState {
  shapes.TermState(s.k, s.r, mod360(s.phase_deg +. int.to_float(dir * 5)))
}

pub fn radius_step(s: TermState, dir: Int, max_r: Float) -> TermState {
  let unit = 0.02 *. max_r
  let r = s.r +. int.to_float(dir) *. unit
  let capped = case r <. 0.0 {
    True -> 0.0
    False ->
      case r >. 2.0 *. max_r {
        True -> 2.0 *. max_r
        False -> r
      }
  }
  shapes.TermState(s.k, capped, s.phase_deg)
}

/// Apply one step to a slot governed by `kind`.
pub fn step(kind: DialKind, s: TermState, dir: Int, max_r: Float) -> TermState {
  case kind {
    DialP -> phase_step(s, dir)
    DialR -> radius_step(s, dir, max_r)
    DialK -> k_step(s, dir)
    DialFixed -> s
  }
}

/// Apply the setup's starting patches to the shape's dial truth.
/// One patch per dial slot, in order; unpatched values stay at truth.
pub fn initial(shape: Shape, patches: List(Patch)) -> List(TermState) {
  let assert True = list.length(patches) == 4
  list.map2(shape.dial, patches, fn(truth, patch) {
    case patch {
      PhaseDeg(deg) -> shapes.TermState(truth.k, truth.r, deg)
      RPct(pct) ->
        shapes.TermState(
          truth.k,
          0.01 *. pct *. shape.dial_max_r,
          truth.phase_deg,
        )
      KSet(k) -> shapes.TermState(k, truth.r, truth.phase_deg)
      Keep -> truth
    }
  })
}

// ---------- experiment configs (P6..P10, ported from the JS prototype) ----------
// The roster stays private: it is the data table behind quaver_setup(),
// not product API — the shipped toy exposes exactly one puzzle.

fn setups() -> List(Setup) {
  [
    Setup(
      "p6",
      "P6 · star · one dial each, k on term 3",
      "term 1 phase · term 2 radius · term 3 k · term 4 fixed",
      "star",
      [DialP, DialR, DialK, DialFixed],
      [PhaseDeg(0.0), RPct(72.0), KSet(8), Keep],
    ),
    Setup(
      "p7",
      "P7 · flower · one dial each, k on term 3",
      "term 1 phase · term 2 radius · term 3 k · term 4 fixed",
      "flower",
      [DialP, DialR, DialK, DialFixed],
      [PhaseDeg(90.0), RPct(72.0), KSet(5), Keep],
    ),
    Setup(
      "p8",
      "P8 · fish · one dial each, k on term 3",
      "term 1 phase · term 2 radius · term 3 k · term 4 fixed",
      "fish",
      [DialP, DialR, DialK, DialFixed],
      [PhaseDeg(345.0), RPct(72.0), KSet(-4), Keep],
    ),
    Setup(
      "p9",
      "quaver",
      "match the eighth note — term 1 phase · term 2 radius · term 3 k",
      "quaver",
      [DialP, DialR, DialK, DialFixed],
      [PhaseDeg(355.0), RPct(73.0), KSet(-5), Keep],
    ),
    Setup(
      "p10",
      "P10 · flower · all four dialed",
      "two radius dials: a fat one on term 2 (38%), a micro trim on term 4 (5%)",
      "flower",
      [DialP, DialR, DialK, DialR],
      [PhaseDeg(90.0), RPct(72.0), KSet(5), RPct(16.0)],
    ),
  ]
}

fn find(id: String) -> Result(Setup, Nil) {
  list.fold(setups(), Error(Nil), fn(acc, setup) {
    case acc {
      Ok(_) -> acc
      Error(Nil) ->
        case setup.id == id {
          True -> Ok(setup)
          False -> Error(Nil)
        }
    }
  })
}

/// The one shipped puzzle — the final v2 interface is single-puzzle.
pub fn quaver_setup() -> Setup {
  let assert Ok(setup) = find("p9")
  setup
}

pub fn shape_of(key: String) -> Shape {
  case key {
    "star" -> shapes.star()
    "flower" -> shapes.flower()
    "fish" -> shapes.fish()
    "quaver" -> shapes.quaver()
    _ -> shapes.star()
  }
}

// ---------- display formatting ----------

pub fn fmt_k(k: Int) -> String {
  case k < 0 {
    True -> "−" <> int.to_string(int.absolute_value(k))
    False -> "+" <> int.to_string(k)
  }
}

fn pct(r: Float, max_r: Float) -> String {
  int.to_string(float.round(r /. max_r *. 100.0)) <> "%"
}

fn deg(d: Float) -> String {
  int.to_string(float.round(d)) <> "°"
}

/// The current value shown in a dial row's readout.
pub fn slot_value(kind: DialKind, s: TermState, max_r: Float) -> String {
  case kind {
    DialP -> deg(s.phase_deg)
    DialR -> pct(s.r, max_r)
    DialK -> "k " <> fmt_k(s.k)
    DialFixed -> "not a dial"
  }
}

/// What the row's small print says about this slot's locked terms.
pub fn locked_note(kind: DialKind, s: TermState, max_r: Float) -> String {
  case kind {
    DialP -> "locked: r " <> pct(s.r, max_r) <> " · k " <> fmt_k(s.k)
    DialR -> "locked: k " <> fmt_k(s.k) <> " · φ " <> deg(s.phase_deg)
    DialK -> "locked: r " <> pct(s.r, max_r) <> " · φ " <> deg(s.phase_deg)
    DialFixed ->
      "fixed, correct: k "
      <> fmt_k(s.k)
      <> " · r "
      <> pct(s.r, max_r)
      <> " · φ "
      <> deg(s.phase_deg)
  }
}

// ---------- the canvas ink contract (colour follows the KIND) ----------
// The arrangement is DATA: v1 ships P/R/K/Fixed, and the fixed slot is a slot
// like any other. So the ink follows the dial KIND, not the slot index — a
// rearranged puzzle still inks its phase dial red, its radius dial yellow and
// its k dial blue. Two surfaces key on these:
//   - fourier_toy_ffi.mjs PALETTES, whose term colours are switched on
//     kind_code (the numbers below are a wire contract with that switch);
//   - index.html's per-row classes, which carry the readout colour.

pub fn kind_code(kind: DialKind) -> Int {
  case kind {
    DialP -> 0
    DialR -> 1
    DialK -> 2
    DialFixed -> 3
  }
}

/// The dial row's colour class (index.html `.kind-*`).
pub fn kind_class(kind: DialKind) -> String {
  case kind {
    DialP -> "kind-phase"
    DialR -> "kind-radius"
    DialK -> "kind-k"
    DialFixed -> "kind-fixed"
  }
}

/// One-decimal match display, matching the JS prototype's toFixed(1).
pub fn fmt1(m: Float) -> String {
  float.to_string(int.to_float(float.round(m *. 10.0)) /. 10.0)
}
