//// Puzzle configuration and dial state machine (pure, fully tested).
////
//// A Setup names one experiment: the shape, the dial kind per slot, and the
//// deterministic starting perturbation — phase +90°, radius ~72% of max, k −2
//// on the kind-3 slot, the same offsets scaled per shape so cross-puzzle feels
//// compare.
////
//// Exactly THREE dialed terms, one column each, kinds ∈ {phase, radius, k}.
//// There is no fixed slot: a shape's 4th+ terms are baked into its `extras`
//// (wire.gleam normalizes an old served "fixed" slot into an extra before it
//// reaches this module), so a dial state is always three terms long.
////
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

/// The 3-lock: a board dials exactly three terms (three columns, one each).
pub const dial_count = 3

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
  }
}

/// Apply the setup's starting patches to the shape's dial truth.
/// One patch per dialed slot, in chain order; unpatched values stay at truth.
/// The board dials exactly three terms, so it opens with exactly three patches.
pub fn initial(shape: Shape, patches: List(Patch)) -> List(TermState) {
  let assert True = list.length(patches) == dial_count
  let assert True = list.length(shape.dial) == dial_count
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

// ---------- the one shipped experiment ----------
// The roster is private and holds the shipped quaver alone; step-logic coverage
// lives in the direct kind tests.

/// The one shipped puzzle — the interface is single-puzzle.
pub fn quaver_setup() -> Setup {
  Setup(
    id: "quaver",
    title: "quaver",
    desc: "match the eighth note — term 1 phase · term 2 radius · term 3 k",
    shape: "quaver",
    dials: [DialP, DialR, DialK],
    patches: [PhaseDeg(355.0), RPct(73.0), KSet(-5)],
  )
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
// The dial columns carry NO text (the board is the precision instrument), so
// there are no per-dial readouts. The score bar is not a dial and keeps its
// one-decimal match display.

/// One-decimal match display, matching the JS prototype's toFixed(1).
pub fn fmt1(m: Float) -> String {
  float.to_string(int.to_float(float.round(m *. 10.0)) /. 10.0)
}
