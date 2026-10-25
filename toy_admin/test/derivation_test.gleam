//// Fixture derivation (PLAN-daily-puzzles.md §3 Q2): dots -> 512-pt
//// arc-length resample -> DFT -> dial truth (top-4 by amplitude) + fixed
//// extras + the 512-point target trace.
////
//// GOLD TEST: the sketch's star preset through this pipeline must reproduce
//// the recorded dialect-truth numbers of the toy's pipeline
//// (fourier_toy/shapes.gleam star fixture), radius tolerance 0.01 in sketch
//// units (0..100 space).

import gleam/int
import gleam/list
import gleeunit/should
import helpers.{be_close}
import sketch
import toy_admin/derivation
import util.{indices}

const pi = 3.141_592_653_589_793

pub fn star_dial_truth_gold_test() {
  let fixture = derivation.derive_fixture(sketch.star(), "star", "2026-10-25")
  should.equal(4, list.length(fixture.dial))
  let expected = [#(1, 27.57), #(-4, 6.59), #(6, 2.93), #(-14, 0.54)]
  list.zip(fixture.dial, expected)
  |> list.each(fn(pair) {
    let #(dial, #(k, radius)) = pair
    should.equal(k, dial.k)
    be_close(dial.radius, radius, 0.01)
  })
}

pub fn star_centroid_gold_test() {
  let fixture = derivation.derive_fixture(sketch.star(), "star", "2026-10-25")
  be_close(fixture.centroid.0, 50.0, 0.01)
  be_close(fixture.centroid.1, 50.0, 0.01)
}

pub fn star_phases_are_in_dial_degrees_test() {
  // The dial-facing unit is degrees 0..360 (the toy's TermState convention),
  // never radians: the star's four dominant terms all sit at 270°.
  let fixture = derivation.derive_fixture(sketch.star(), "star", "2026-10-25")
  list.each(fixture.dial, fn(dial) {
    should.be_true(dial.phase_deg >=. 0.0)
    should.be_true(dial.phase_deg <. 360.0)
    be_close(dial.phase_deg, 270.0, 0.01)
  })
}

pub fn target_trace_is_512_points_test() {
  let fixture = derivation.derive_fixture(sketch.star(), "star", "2026-10-25")
  should.equal(derivation.sample_count, list.length(fixture.target))
}

pub fn target_trace_starts_at_the_first_dot_test() {
  // Arc-length resampling starts at the first dot (resample.gleam contract).
  let dots = sketch.star()
  let first = case dots {
    [dot, ..] -> dot
    [] -> #(0.0, 0.0)
  }
  let fixture = derivation.derive_fixture(dots, "star", "2026-10-25")
  let start = case fixture.target {
    [point, ..] -> point
    [] -> #(-1.0, -1.0)
  }
  be_close(start.0, first.0, 0.000_001)
  be_close(start.1, first.1, 0.000_001)
}

pub fn k_zero_is_the_centroid_not_a_dial_test() {
  // The DC term's magnitude is the *vector* 50+50i (radius ~70.7) for the
  // star — bigger than every dial term. It must never occupy a dial slot.
  let fixture = derivation.derive_fixture(sketch.star(), "star", "2026-10-25")
  list.each(fixture.dial, fn(dial) { should.not_equal(0, dial.k) })
  list.each(fixture.extras, fn(extra) { should.not_equal(0, extra.k) })
}

pub fn extras_are_the_rest_of_the_spectrum_test() {
  let fixture = derivation.derive_fixture(sketch.star(), "star", "2026-10-25")
  // 512 DFT terms: one DC (the centroid) + 4 dials + the fixed extras.
  should.equal(derivation.sample_count - 1 - 4, list.length(fixture.extras))
}

pub fn extras_never_duplicate_a_dial_test() {
  let fixture = derivation.derive_fixture(sketch.star(), "star", "2026-10-25")
  let dial_ks = list.map(fixture.dial, fn(dial) { dial.k })
  list.each(fixture.extras, fn(extra) {
    should.be_false(list.contains(dial_ks, extra.k))
  })
}

pub fn dial_and_extras_reconstruct_the_target_test() {
  // The split is lossless: centroid + dial + extras at period time t equals
  // the target trace point. If a term ever goes missing from both lists this
  // test drifts away from the trace.
  let dots = sketch.star()
  let fixture = derivation.derive_fixture(dots, "star", "2026-10-25")
  let all = list.append(fixture.dial, fixture.extras)
  indices(derivation.sample_count)
  |> list.each(fn(i) {
    let t = int.to_float(i) /. int.to_float(derivation.sample_count)
    let synth = synthesis(fixture.centroid, all, t)
    let target = case list.drop(fixture.target, i) {
      [point, ..] -> point
      [] -> #(0.0, 0.0)
    }
    be_close(synth.0, target.0, 0.000_001)
    be_close(synth.1, target.1, 0.000_001)
  })
}

fn synthesis(
  centroid: #(Float, Float),
  dials: List(derivation.Dial),
  t: Float,
) -> #(Float, Float) {
  let #(cx, cy) = centroid
  list.fold(dials, #(cx, cy), fn(acc, dial) {
    let angle =
      2.0 *. pi *. int.to_float(dial.k) *. t +. dial.phase_deg /. 180.0 *. pi
    #(acc.0 +. dial.radius *. cos(angle), acc.1 +. dial.radius *. sin(angle))
  })
}

@external(erlang, "math", "cos")
fn cos(x: Float) -> Float

@external(erlang, "math", "sin")
fn sin(x: Float) -> Float

pub fn fixture_carries_name_and_show_date_test() {
  let fixture = derivation.derive_fixture(sketch.star(), "star", "2026-10-25")
  should.equal("star", fixture.name)
  should.equal("2026-10-25", fixture.show_date)
}

pub fn standard_dial_arrangement_test() {
  // Q19: the fixture carries its own dial list. v1 always emits the standard
  // pattern (phase / radius / k / fixed, in amplitude order).
  let fixture = derivation.derive_fixture(sketch.star(), "star", "2026-10-25")
  should.equal(
    [
      derivation.DialPhase,
      derivation.DialRadius,
      derivation.DialK,
      derivation.DialFixed,
    ],
    fixture.dials,
  )
}

pub fn degenerate_dot_count_yields_an_empty_fixture_test() {
  // Below the core's 3-dot gate (terms.compute) there is no spectrum: emit
  // empty lists instead of crashing. The admin refuses to save such a puzzle.
  let fixture =
    derivation.derive_fixture([#(10.0, 10.0), #(20.0, 20.0)], "x", "2026-10-25")
  should.equal([], fixture.dial)
  should.equal([], fixture.extras)
  should.equal([], fixture.target)
  should.equal(#(0.0, 0.0), fixture.centroid)
}
