import gleam/float
import gleam/int
import gleam/list
import gleeunit/should
import resample

fn gap(a: #(Float, Float), b: #(Float, Float)) -> Float {
  dist(a, b)
}

fn dist(a: #(Float, Float), b: #(Float, Float)) -> Float {
  let dx = { a.0 -. b.0 }
  let dy = { a.1 -. b.1 }
  sq({ dx *. dx } +. { dy *. dy })
}

fn sq(x: Float) -> Float {
  case float.square_root(x) {
    Ok(v) -> v
    Error(_) -> 0.0
  }
}

fn ok_or_first(
  r: Result(#(Float, Float), Nil),
  fallback: #(Float, Float),
) -> #(Float, Float) {
  case r {
    Ok(p) -> p
    Error(_) -> fallback
  }
}

/// Gaps between consecutive samples, including the wrap-around
/// gap from the last sample back to the first (closed path).
fn all_gaps(samples: List(#(Float, Float))) -> List(Float) {
  let first = ok_or_first(list.first(samples), #(0.0, 0.0))
  list.zip(samples, list.drop(list.append(samples, [first]), 1))
  |> list.map(fn(pair) { gap(pair.0, pair.1) })
}

fn closed_edges(dots: List(#(Float, Float))) -> List(#(#(Float, Float), #(Float, Float))) {
  let closed = case list.first(dots) {
    Ok(first) -> list.append(dots, [first])
    Error(_) -> dots
  }
  list.zip(closed, list.drop(closed, 1))
}

fn polygon_perimeter(dots: List(#(Float, Float))) -> Float {
  closed_edges(dots)
  |> list.fold(0.0, fn(acc, e) { acc +. dist(e.0, e.1) })
}

fn clamp01(x: Float) -> Float {
  case x <. 0.0 {
    True -> 0.0
    False ->
      case x >. 1.0 {
        True -> 1.0
        False -> x
      }
  }
}

fn point_segment_dist(
  p: #(Float, Float),
  a: #(Float, Float),
  b: #(Float, Float),
) -> Float {
  let abx = { b.0 -. a.0 }
  let aby = { b.1 -. a.1 }
  let apx = { p.0 -. a.0 }
  let apy = { p.1 -. a.1 }
  let len2 = { abx *. abx } +. { aby *. aby }
  let t = case len2 >. 0.0 {
    False -> 0.0
    True -> clamp01({ { apx *. abx } +. { apy *. aby } } /. len2)
  }
  dist(p, #({ a.0 +. { t *. abx } }, { a.1 +. { t *. aby } }))
}

fn dist_to_closed_polygon(
  p: #(Float, Float),
  dots: List(#(Float, Float)),
) -> Float {
  closed_edges(dots)
  |> list.fold(1.0e9, fn(acc, e) {
    let d = point_segment_dist(p, e.0, e.1)
    case d <. acc {
      True -> d
      False -> acc
    }
  })
}

pub fn square_resample_length_test() {
  let square = [#(0.0, 0.0), #(1.0, 0.0), #(1.0, 1.0), #(0.0, 1.0)]
  let samples = resample.resample_closed(square, 16)
  should.equal(list.length(samples), 16)
}

pub fn triangle_even_spacing_test() {
  // Perimeter 12, 12 samples, step 1.0. NOTE: this fixture's corners all
  // coincide with sample positions, so chord deficits are zero and every
  // gap is exactly one step. For non-aligned shapes see the chord tests.
  let triangle = [#(0.0, 0.0), #(3.0, 0.0), #(0.0, 4.0)]
  let gaps = all_gaps(resample.resample_closed(triangle, 12))
  should.be_true(
    list.all(gaps, fn(g) {
      let dev = float.absolute_value(g -. 1.0)
      dev <. 0.000_001
    }),
  )
}

pub fn corner_hits_test() {
  // Square perimeter 4; 16 samples -> spacing 0.25.
  // Sample 4 lands exactly on corner (1,0); sample 8 on (1,1).
  let square = [#(0.0, 0.0), #(1.0, 0.0), #(1.0, 1.0), #(0.0, 1.0)]
  let samples = resample.resample_closed(square, 16)
  should.equal(list.first(list.drop(samples, 4)), Ok(#(1.0, 0.0)))
  should.equal(list.first(list.drop(samples, 8)), Ok(#(1.0, 1.0)))
}

pub fn starts_at_first_dot_test() {
  let square = [#(0.0, 0.0), #(1.0, 0.0), #(1.0, 1.0), #(0.0, 1.0)]
  let samples = resample.resample_closed(square, 16)
  should.equal(list.first(samples), Ok(#(0.0, 0.0)))
}

pub fn samples_lie_on_polygon_test() {
  // L-shape: sample positions may straddle corners, so gaps are chords —
  // the sound invariant is that every sample lies ON the polygon.
  let lshape = [
    #(0.0, 0.0),
    #(4.0, 0.0),
    #(4.0, 1.0),
    #(1.0, 1.0),
    #(1.0, 3.0),
  ]
  let samples = resample.resample_closed(lshape, 30)
  should.be_true(
    list.all(samples, fn(p) {
      dist_to_closed_polygon(p, lshape) <. 0.000_001
    }),
  )
}

pub fn chords_never_exceed_step_test() {
  // Chord between consecutive samples is never longer than one step,
  // and the chord polyline is never longer than the polygon it walks.
  let lshape = [
    #(0.0, 0.0),
    #(4.0, 0.0),
    #(4.0, 1.0),
    #(1.0, 1.0),
    #(1.0, 3.0),
  ]
  let n = 30
  let samples = resample.resample_closed(lshape, n)
  let step = polygon_perimeter(lshape) /. int.to_float(n)
  let gaps = all_gaps(samples)
  should.be_true(list.all(gaps, fn(g) { g <=. { step +. 0.000_001 } }))
  let total = list.fold(gaps, 0.0, fn(acc, g) { acc +. g })
  should.be_true(
    total <=. { polygon_perimeter(lshape) +. 0.000_001 },
  )
}

pub fn identical_dots_do_not_crash_test() {
  let degenerate = [#(2.0, 3.0), #(2.0, 3.0), #(2.0, 3.0), #(2.0, 3.0)]
  let samples = resample.resample_closed(degenerate, 32)
  should.equal(list.length(samples), 32)
  should.be_true(
    list.all(samples, fn(p) { { p.0 == 2.0 } && { p.1 == 3.0 } }),
  )
}

pub fn single_dot_test() {
  let samples = resample.resample_closed([#(5.0, 5.0)], 8)
  should.equal(list.length(samples), 8)
  should.be_true(list.all(samples, fn(p) { { p.0 == 5.0 } && { p.1 == 5.0 } }))
}
pub fn negative_coordinates_test() {
  let dots = [#(-5.0, -5.0), #(5.0, -5.0), #(5.0, 5.0)]
  let samples = resample.resample_closed(dots, 12)
  should.equal(list.length(samples), 12)
  should.equal(list.first(samples), Ok(#(-5.0, -5.0)))
  should.be_true(
    list.all(samples, fn(p) {
      dist_to_closed_polygon(p, dots) <. 0.000_001
    }),
  )
}
