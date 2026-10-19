import gleam/float
import gleam/list
import gleeunit/should
import resample

fn gap(a: #(Float, Float), b: #(Float, Float)) -> Float {
  let dx = a.0 -. b.0
  let dy = a.1 -. b.1
  float.sqrt({ dx *. dx } +. { dy *. dy })
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

pub fn square_resample_length_test() {
  let square = [#(0.0, 0.0), #(1.0, 0.0), #(1.0, 1.0), #(0.0, 1.0)]
  let samples = resample.resample_closed(square, 16)
  should.equal(list.length(samples), 16)
}

pub fn triangle_even_spacing_test() {
  // Perimeter 3 + 4 + 5 = 12; 12 samples -> every gap is 1.0
  let triangle = [#(0.0, 0.0), #(3.0, 0.0), #(0.0, 4.0)]
  let gaps = all_gaps(resample.resample_closed(triangle, 12))
  should.be_true(
    list.all(gaps, fn(g) {
      let dev = float.abs(g -. 1.0)
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

pub fn perimeter_preserved_test() {
  let lshape = [#(0.0, 0.0), #(4.0, 0.0), #(4.0, 1.0), #(1.0, 1.0), #(1.0, 3.0)]
  // perimeter = 4 + 1 + 3 + 2 + 3 + 2 = 15
  let samples = resample.resample_closed(lshape, 30)
  let perimeter = list.fold(all_gaps(samples), 0.0, fn(acc, g) { acc +. g })
  should.be_close(perimeter, 15.0, 0.000_001)
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