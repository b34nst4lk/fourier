//// The match metric, client-side (PLAN-daily-puzzles.md §3 Q20, phase 4b).
////
//// PORTED from fourier_toy/shapes.gleam — `position_at`, `synth_trace`,
//// `rms_pointwise`, `rms_polar`, `match_pct`. The toy computes the player's
//// score in the browser; the admin's test-play must score the SAME way, so the
//// editor numbers and the player numbers agree. Keep the port line-for-line:
////   - 512 samples (n_samples), t = i/512 for i in 0..511 (NOT 1/512..1: the
////     toy's `indices(n_samples)` maps i -> i/512, and the target trace it
////     compares against was built by the same convention);
////   - phase in DEGREES on the wire, radians in the synthesis;
////   - the k=0 centroid rides separately (it is not a term);
////   - extras are chained AFTER the dial terms, as real rotating epicycles —
////     not a constant offset (the fish/quaver depend on it);
////   - match = 1 − rms/target_rms_polar, in percent, clamped at 0.
////
//// What is deliberately NOT ported: the dial state machine (fourier_toy/
//// puzzle.gleam) lives in dial.gleam, and `Shape` is not ported at all — the
//// admin derives everything from the fixture's own JSON (centroid, dial,
//// extras, target), so there is no second copy of the shapes' tables here.
////
//// The normalizer (`rms_polar`) is a property of the TARGET trace, and the
//// served fixture does not carry it as a field. Rather than add a wire field
//// nobody else reads, the admin recomputes it from the target it was given —
//// the same 512-point pass, on data that just arrived. `fixture_rms_polar` in
//// wire.gleam is that adapter.

import gleam/float
import gleam/int
import gleam/list
import gleam/result

/// The DFT size / trace resolution the toys use (fourier_toy: n_samples).
/// Also the number of samples the match is measured over.
pub const sample_count = 512

/// The badge threshold (fourier_toy: solved_at). A puzzle is "solved" at 95%.
pub const solved_at = 95.0

/// A point in sketch space (0..100), as the fixture's target and centroid are.
pub type Point =
  #(Float, Float)

/// One synthesis row in dial-facing units: k signed, radius in sketch units,
/// phase in degrees 0..360.
pub type Term {
  Term(k: Int, radius: Float, phase_deg: Float)
}

@external(javascript, "./math_ffi.mjs", "cos")
fn js_cos(x: Float) -> Float

@external(javascript, "./math_ffi.mjs", "sin")
fn js_sin(x: Float) -> Float

/// Tip of the epicycle chain at period time t in 0..1 — the toy's
/// `shapes.position_at`: centroid + every term's own rotation.
pub fn position_at(centroid: Point, terms: List(Term), t: Float) -> Point {
  let #(cx, cy) = centroid
  let #(ox, oy) =
    list.fold(terms, #(0.0, 0.0), fn(acc, term) {
      let #(ax, ay) = acc
      let angle =
        2.0 *. pi *. int.to_float(term.k) *. t +. term.phase_deg *. pi /. 180.0
      #(ax +. term.radius *. js_cos(angle), ay +. term.radius *. js_sin(angle))
    })
  #(cx +. ox, cy +. oy)
}

/// The toy's `shapes.synth_trace`: sample_count uniform samples of the chain.
pub fn synth_trace(centroid: Point, terms: List(Term)) -> List(Point) {
  list.map(indices(), fn(i) {
    position_at(centroid, terms, int.to_float(i) /. int.to_float(sample_count))
  })
}

fn indices() -> List(Int) {
  count_up(0, sample_count, [])
}

/// 0, 1, ... n-1 — the toy's `util.indices`. Stdlib 1.x has no `list.range`,
/// and the module is shared with the browser bundle, so it stays a fold.
fn count_up(from: Int, to: Int, acc: List(Int)) -> List(Int) {
  case from >= to {
    True -> list.reverse(acc)
    False -> count_up(from + 1, to, [from, ..acc])
  }
}

/// RMS pointwise distance between two traces (same length, by construction).
pub fn rms_pointwise(a: List(Point), b: List(Point)) -> Float {
  let sum =
    list.zip(a, b)
    |> list.fold(0.0, fn(acc, pair) {
      let #(p, q) = pair
      let dx = p.0 -. q.0
      let dy = p.1 -. q.1
      acc +. dx *. dx +. dy *. dy
    })
  float.square_root(sum /. int.to_float(sample_count))
  |> result.unwrap(0.0)
}

/// The target trace's RMS radius about the centroid — the metric's normalizer.
pub fn rms_polar(points: List(Point), cx: Float, cy: Float) -> Float {
  let sum =
    list.fold(points, 0.0, fn(acc, p) {
      let dx = p.0 -. cx
      let dy = p.1 -. cy
      acc +. dx *. dx +. dy *. dy
    })
  float.square_root(sum /. int.to_float(sample_count))
  |> result.unwrap(0.0)
}

/// The match percentage of a dial state against the fixture's target:
/// 1 − rms/normalizer, in percent, clamped at 0 (a wild guess can be worse than
/// nothing — the toy shows 0, not a negative score).
pub fn match_pct(
  centroid: Point,
  terms terms: List(Term),
  target target: List(Point),
  normalizer normalizer: Float,
) -> Float {
  let current = synth_trace(centroid, terms)
  let rms = rms_pointwise(current, target)
  let raw = { 1.0 -. rms /. normalizer } *. 100.0
  case raw <. 0.0 {
    True -> 0.0
    False -> raw
  }
}

pub fn solved(match: Float) -> Bool {
  match >=. solved_at
}

const pi = 3.141592653589793
