//// Fixture shapes for the dial experiments, and the geometry/metric math.
////
//// Every number is computed through fourier_sketch's own pipeline — nothing
//// hand-copied. Each shape carries:
////   - a centroid (the k=0 term's position — fixed in every synthesis),
////   - `dial`: the top-3 terms by amplitude (the puzzle's movable truth — the
////     dial-columns board has exactly three dials), with phases snapped to
////     the 5° dial grid so the dial lands exactly,
////   - `extras`: every remaining row from the shape's spectrum (the former
////     4th dial term included), held FIXED and baked identically into the
////     target and the current synthesis (the star/flower carry 1; the
////     fish/quaver carry 26). The synthesis term set is unchanged: top-4 =
////     top-3 + extras[0], so no metric value moves with the split.
////   - `target`: the 512-point trace the comparison runs against,
////   - `rms_polar`: the target's RMS polar radius (the metric normalizer).
////
//// Parameterization convention (see docs/PROGRESS.md):
////   star:   dot preset -> arc-length resample -> DFT (polygons: no smear)
////   flower: parametric rose, THETA-uniform DFT (arc-length smears smooth
////           shapes' spectra — measured), phase-snapped, target rebuilt.
////   fish/quaver: defined by their export-CSV term tables; the synthesis IS
////           the target by definition. Phases in the source tables are
////           radians, passed through norm_deg; dialable rows also snap5.

import complex
import dft
import gleam/float
import gleam/int
import gleam/list
import gleam/order
import resample
import sketch
import terms.{type Term}
import util.{indices, pi}

const n_samples = 512

pub const solved_at = 95.0

pub type Shape {
  Shape(
    name: String,
    centroid: #(Float, Float),
    dial: List(TermState),
    extras: List(TermState),
    dial_max_r: Float,
    rms_polar: Float,
    target: List(#(Float, Float)),
  )
}

/// One synthesis term in dial-facing units: k signed, radius in sketch
/// units, phase in degrees 0..360.
pub type TermState {
  TermState(k: Int, r: Float, phase_deg: Float)
}

// ---------- angle helpers ----------

/// Round to 6 decimals — precision parity with the archived JS fixtures
/// (the JS generator applied Number(toFixed(6)) to DFT-derived values).
fn round6(x: Float) -> Float {
  int.to_float(float.round(x *. 1_000_000.0)) /. 1_000_000.0
}

fn norm_deg(rad: Float) -> Float {
  let deg = rad /. pi *. 180.0
  case deg <. 0.0 {
    True -> deg +. 360.0
    False -> deg
  }
}

/// Snap degrees to the 5° dial grid (0..360).
fn snap5(deg: Float) -> Float {
  let snapped = int.to_float(float.round(deg /. 5.0)) *. 5.0
  mod360(snapped)
}

/// The shared wrap for degree arithmetic — puzzle.phase_step imports it.
pub fn mod360(x: Float) -> Float {
  case x <. 0.0, x >=. 360.0 {
    True, _ -> mod360(x +. 360.0)
    False, True -> mod360(x -. 360.0)
    False, False -> x
  }
}

// ---------- synthesis + metric ----------

/// Tip of the epicycle chain at period time t in 0..1: centroid + sum of
/// terms. The k=0 centroid rides in every synthesis.
pub fn position_at(
  centroid: #(Float, Float),
  terms: List(TermState),
  t: Float,
) -> #(Float, Float) {
  let #(cx, cy) = centroid
  let #(ox, oy) =
    list.fold(terms, #(0.0, 0.0), fn(acc, term) {
      let #(ax, ay) = acc
      let a =
        2.0 *. pi *. int.to_float(term.k) *. t +. term.phase_deg *. pi /. 180.0
      #(ax +. term.r *. js_cos(a), ay +. term.r *. js_sin(a))
    })
  #(cx +. ox, cy +. oy)
}

@external(javascript, "./math_ffi.mjs", "cos")
fn js_cos(x: Float) -> Float

@external(javascript, "./math_ffi.mjs", "sin")
fn js_sin(x: Float) -> Float

/// Full trace of a synthesis, N uniform samples (t = 1/N .. 1).
pub fn synth_trace(
  centroid: #(Float, Float),
  terms: List(TermState),
) -> List(#(Float, Float)) {
  list.map(indices(n_samples), fn(i) {
    position_at(centroid, terms, int.to_float(i) /. int.to_float(n_samples))
  })
}

/// RMS pointwise distance between two equal-length traces.
pub fn rms_pointwise(
  a: List(#(Float, Float)),
  b: List(#(Float, Float)),
) -> Float {
  let acc =
    list.zip(a, b)
    |> list.fold(0.0, fn(sum, pair) {
      let #(p, q) = pair
      let dx = p.0 -. q.0
      let dy = p.1 -. q.1
      sum +. dx *. dx +. dy *. dy
    })
  let assert Ok(rms) = float.square_root(acc /. int.to_float(n_samples))
  rms
}

/// Match percentage for a dial state against a shape: 1 − RMS/the target's
/// RMS polar radius, displayed clamped at 0.
pub fn match_pct(shape: Shape, dial: List(TermState)) -> Float {
  let current = synth_trace(shape.centroid, list.append(dial, shape.extras))
  let rms = rms_pointwise(current, shape.target)
  let raw = { 1.0 -. rms /. shape.rms_polar } *. 100.0
  case raw <. 0.0 {
    True -> 0.0
    False -> raw
  }
}

pub fn solved(shape: Shape, dial: List(TermState)) -> Bool {
  match_pct(shape, dial) >=. solved_at
}

// ---------- star: dot preset through the arc-length pipeline ----------

pub fn star() -> Shape {
  let dots = sketch.star()
  let target = resample.resample_closed(dots, n_samples)
  let #(cx, cy) = centroid_of(target)
  let dial =
    terms.compute(dots, n_samples, n_samples)
    |> list.filter(fn(t: Term) { t.k != 0 })
    |> list.map(fn(t: Term) {
      TermState(t.k, round6(t.radius), round6(norm_deg(t.phase)))
    })
    |> list.sort(fn(a, b) {
      case a.r >. b.r {
        True -> order.Lt
        False -> order.Gt
      }
    })
    |> list.take(4)
  // the star's truth phases come out on-grid already (all 270°): no snapping
  let #(dial, extras) = split_dial(dial)
  Shape(
    name: "star",
    centroid: #(cx, cy),
    dial: dial,
    extras: extras,
    dial_max_r: max_r(dial),
    rms_polar: rms_polar_of(target, cx, cy),
    target: target,
  )
}

// ---------- flower: parametric rose, theta-uniform, phase-snapped rebuild ----

pub fn flower() -> Shape {
  let f = 26.0
  let samples =
    indices(n_samples)
    |> list.map(fn(i) {
      let t = int.to_float(i) /. int.to_float(n_samples) *. 2.0 *. pi
      let r =
        f
        *. {
          0.55 +. 0.42 *. js_cos(6.0 *. t +. 0.6) +. 0.06 *. js_cos(12.0 *. t)
        }
      #(50.0 +. r *. js_cos(t), 50.0 +. r *. js_sin(t))
    })
  let dial =
    dft.forward(samples)
    |> list.map(fn(term) {
      let #(k, c) = term
      #(k, complex.magnitude(c), complex.argument(c))
    })
    |> list.filter(fn(row) { row.0 != 0 })
    |> list.sort(fn(a, b) {
      case a.1 >. b.1 {
        True -> order.Lt
        False -> order.Gt
      }
    })
    |> list.take(4)
    |> list.map(fn(row) {
      TermState(row.0, round6(row.1), snap5(norm_deg(row.2)))
    })
  let #(dial, extras) = split_dial(dial)
  // top-3 + the baked 4th term = the same synthesis as before the split
  let target = synth_trace(#(50.0, 50.0), list.append(dial, extras))
  Shape(
    name: "flower",
    centroid: #(50.0, 50.0),
    dial: dial,
    extras: extras,
    dial_max_r: max_r(dial),
    rms_polar: rms_polar_of(target, 50.0, 50.0),
    target: target,
  )
}

// ---------- table shapes: fish and quaver (export CSVs) ----------

fn table_shape(
  name: String,
  c0: #(Float, Float),
  table: List(#(Int, Float, Float)),
) -> Shape {
  let rows =
    list.map(table, fn(row) {
      let #(k, r, phase_rad) = row
      TermState(k, r, norm_deg(phase_rad))
    })
  // the dialed slots are the top three rows; the former 4th dial term joins
  // the extras (still phase-snapped, exactly as it was when it was dialed) so
  // the synthesis — and every metric derived from it — is untouched
  let assert [d0, d1, d2, d3, ..rest] = rows
  let dial = [d0, d1, d2]
  let dial_snapped =
    list.map(dial, fn(t) { TermState(t.k, t.r, snap5(t.phase_deg)) })
  let extras = [TermState(d3.k, d3.r, snap5(d3.phase_deg)), ..rest]
  let target = synth_trace(c0, list.append(dial_snapped, extras))
  Shape(
    name: name,
    centroid: c0,
    dial: dial_snapped,
    extras: extras,
    dial_max_r: max_r(dial_snapped),
    rms_polar: rms_polar_of(target, c0.0, c0.1),
    target: target,
  )
}

/// Fish: the user's export CSV.
pub fn fish() -> Shape {
  table_shape("fish", #(67.05 *. js_cos(0.7), 67.05 *. js_sin(0.7)), [
    #(-1, 26.07, -1.85),
    #(1, 16.27, 1.61),
    #(-2, 7.51, -0.34),
    #(2, 4.9, -3.13),
    #(3, 2.79, -1.45),
    #(-4, 1.84, 2.32),
    #(4, 1.12, 0.28),
    #(5, 0.78, 2.06),
    #(-6, 0.77, -1.07),
    #(-5, 0.63, 0.65),
    #(-8, 0.27, 1.94),
    #(6, 0.23, -2.36),
    #(-7, 0.22, -2.74),
    #(10, 0.21, 1.26),
    #(9, 0.2, -0.67),
    #(12, 0.17, -1.58),
    #(-3, 0.15, -0.46),
    #(11, 0.14, 2.66),
    #(-13, 0.14, 2.69),
    #(-12, 0.14, -1.7),
    #(17, 0.12, -2.51),
    #(8, 0.12, -2.08),
    #(-15, 0.11, -0.96),
    #(13, 0.11, -0.17),
    #(19, 0.1, 0.86),
    #(-14, 0.09, 1.18),
    #(-11, 0.09, -0.23),
    #(-22, 0.08, 3.07),
    #(-20, 0.07, 0.26),
  ])
}

/// Quaver (eighth note): the user's export CSV.
pub fn quaver() -> Shape {
  table_shape("quaver", #(58.3 *. js_cos(0.81), 58.3 *. js_sin(0.81)), [
    #(-1, 17.97, -1.69),
    #(1, 11.3, -0.93),
    #(-3, 4.68, -1.78),
    #(3, 2.83, -2.88),
    #(2, 2.48, -2.74),
    #(4, 1.4, -1.37),
    #(-5, 1.33, 2.94),
    #(5, 1.03, -1.04),
    #(-2, 0.83, 1.0),
    #(-7, 0.61, -0.49),
    #(-6, 0.61, -0.46),
    #(-4, 0.52, 1.14),
    #(-8, 0.41, -2.32),
    #(7, 0.38, 2.46),
    #(-9, 0.37, -2.42),
    #(9, 0.33, -1.68),
    #(8, 0.31, -1.76),
    #(-13, 0.14, -1.69),
    #(-11, 0.13, 0.11),
    #(16, 0.12, -1.69),
    #(12, 0.12, -1.35),
    #(-12, 0.1, -2.12),
    #(-16, 0.09, -2.7),
    #(-20, 0.09, -2.08),
    #(20, 0.08, -2.35),
    #(13, 0.06, -2.01),
    #(10, 0.06, -1.73),
    #(14, 0.06, 2.43),
    #(17, 0.06, -1.42),
  ])
}

// ---------- fetched shapes ----------

/// A shape assembled from a served puzzle's own numbers (wire.gleam): the
/// client-side half of `table_shape`. A fetched puzzle carries its dial truth,
/// its extras, its centroid and its 512-point target — what it cannot carry
/// without restating the shape is the metric's two scalars, so they are
/// derived here exactly as the built-in shapes derive them:
/// `dial_max_r` is the biggest DIALABLE radius (the radius dial's unit, and its
/// 200% ceiling) and `rms_polar` is the target's polar RMS about the centroid.
/// Same function, same numbers — a served puzzle and a built-in one behave
/// identically.
pub fn from_parts(
  name name: String,
  centroid centroid: #(Float, Float),
  dial dial: List(TermState),
  extras extras: List(TermState),
  target target: List(#(Float, Float)),
) -> Shape {
  Shape(
    name: name,
    centroid: centroid,
    dial: dial,
    extras: extras,
    dial_max_r: max_r(dial),
    rms_polar: rms_polar_of(target, centroid.0, centroid.1),
    target: target,
  )
}

// ---------- small helpers ----------

/// The dial-columns split: a shape DIALS its top three terms; every row after
/// them (the former 4th dial term included) is baked into `extras`. The
/// synthesis set does not change — top-4 = top-3 + extras[0].
fn split_dial(rows: List(TermState)) -> #(List(TermState), List(TermState)) {
  let assert [d0, d1, d2, ..extras] = rows
  #([d0, d1, d2], extras)
}

fn centroid_of(pts: List(#(Float, Float))) -> #(Float, Float) {
  let #(sx, sy, count) =
    list.fold(pts, #(0.0, 0.0, 0.0), fn(acc, p) {
      let #(x, y, c) = acc
      #(x +. p.0, y +. p.1, c +. 1.0)
    })
  #(sx /. count, sy /. count)
}

fn rms_polar_of(pts: List(#(Float, Float)), cx: Float, cy: Float) -> Float {
  let acc =
    list.fold(pts, 0.0, fn(sum, p) {
      let dx = p.0 -. cx
      let dy = p.1 -. cy
      sum +. dx *. dx +. dy *. dy
    })
  // Per point, not per the sample constant: built-in shapes always synthesise
  // n_samples points (so this is the same number), but a fetched puzzle brings
  // its own target and the mean square must follow its length.
  let count = int.to_float(list.length(pts))
  let assert True = count >. 0.0
  let assert Ok(rms) = float.square_root(acc /. count)
  rms
}

fn max_r(dial: List(TermState)) -> Float {
  list.fold(dial, 0.0, fn(acc, t) {
    case t.r >. acc {
      True -> t.r
      False -> acc
    }
  })
}
