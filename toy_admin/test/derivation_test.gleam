//// Fixture derivation (PLAN-daily-puzzles.md §3 Q2): dots -> 512-pt
//// arc-length resample -> DFT -> dial truth (top-4 by amplitude) + fixed
//// extras + the 512-point target trace.
////
//// GOLD TEST: the sketch's star preset through this pipeline must reproduce
//// the recorded dialect-truth numbers of the toy's pipeline
//// (fourier_toy/shapes.gleam star fixture), radius tolerance 0.01 in sketch
//// units (0..100 space).
////
//// There is a SECOND gold here, for the starting patches (§1's deterministic
//// start): the quaver's own drawing through this pipeline must produce
//// EXACTLY the patches the shipped toy boots with (fourier_toy/puzzle.gleam
//// p9: PhaseDeg(355.0), RPct(73.0), KSet(-5), Keep). The quaver's term table
//// is copied below from fourier_toy/shapes.gleam because toy_admin cannot
//// depend on the toy (it is a Lustre/JS package; this server is
//// Erlang-native) — the parity assertion is what keeps the copy honest.

import gleam/float
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

pub fn can_derive_needs_three_dots_test() {
  // The core's <3-dot gate, named for the admin route: a drawing with fewer
  // than three dots cannot be saved as a puzzle.
  should.equal(False, derivation.can_derive([]))
  should.equal(False, derivation.can_derive([#(0.0, 0.0)]))
  should.equal(False, derivation.can_derive([#(0.0, 0.0), #(1.0, 1.0)]))
  should.equal(
    True,
    derivation.can_derive([#(0.0, 0.0), #(1.0, 1.0), #(2.0, 0.0)]),
  )
}

pub fn is_degenerate_detects_the_gated_fixture_test() {
  // The admin's save check reuses this rather than counting dots twice: the
  // derived fixture is degenerate exactly when nothing could be rendered.
  let degenerate =
    derivation.derive_fixture([#(0.0, 0.0), #(1.0, 1.0)], "n", "2026-10-25")
  should.be_true(derivation.is_degenerate(degenerate))
  should.be_true(
    derivation.is_degenerate(derivation.derive_fixture([], "n", "2026-10-25")),
  )

  let real = derivation.derive_fixture(sketch.star(), "star", "2026-10-25")
  should.equal(False, derivation.is_degenerate(real))
}

// ---------- the starting patches (PLAN §1: the deterministic start) ----------

pub fn quaver_equivalent_drawing_reproduces_the_toys_start_test() {
  // GOLD (byte parity): the shipped quaver's own shape, expressed as a drawing
  // and run through THIS pipeline, must produce exactly the patches the toy
  // boots with. Any drift in the vocabulary (90°, 73%, k−2, the 5° snap) shows
  // up here as a mismatch of the whole list — that is the point of the test.
  let fixture = derivation.derive_fixture(quaver_dots(), "eighth", "2026-11-02")
  // sanity: the drawing really is the quaver (dial truth by amplitude order)
  should.equal([-1, 1, -3, 3], list.map(fixture.dial, fn(row) { row.k }))
  should.equal(
    [
      derivation.PhaseDeg(355.0),
      derivation.RPct(73.0),
      derivation.KSet(-5),
      derivation.Keep,
    ],
    fixture.patches,
  )
}

pub fn standard_start_is_the_documented_vocabulary_test() {
  // The star's four truth phases all sit at 270°, so the quarter-turn start
  // lands exactly on 0°; radius is 73% of the biggest dialable radius, k is
  // the truth shifted by −2, and the fixed slot keeps its (correct) truth.
  let fixture = derivation.derive_fixture(sketch.star(), "star", "2026-10-25")
  let assert [_, _, d2, _] = fixture.dial
  let assert [
    derivation.PhaseDeg(deg),
    derivation.RPct(pct),
    derivation.KSet(k),
    derivation.Keep,
  ] = fixture.patches
  be_close(deg, 0.0, 0.000_001)
  be_close(pct, 73.0, 0.000_001)
  should.equal(d2.k - 2, k)
}

pub fn start_phase_snaps_to_the_dial_grid_test() {
  // The dial steps in 5°: a start off the grid could never be stepped onto.
  // 262.4° truth + 90° = 352.4° -> the nearest grid point, 350°.
  let patches =
    derivation.standard_patches([
      derivation.Dial(k: 1, radius: 5.0, phase_deg: 262.4),
      derivation.Dial(k: 2, radius: 4.0, phase_deg: 12.0),
      derivation.Dial(k: 3, radius: 3.0, phase_deg: 0.0),
      derivation.Dial(k: 4, radius: 2.0, phase_deg: 90.0),
    ])
  should.equal(
    [
      derivation.PhaseDeg(350.0),
      derivation.RPct(73.0),
      derivation.KSet(1),
      derivation.Keep,
    ],
    patches,
  )
}

pub fn start_k_shift_stays_inside_the_dial_test() {
  // −2 normally; near the floor k_min = −16 a −2 would leave the dial, so the
  // perturbation flips direction instead of clamping onto a value the player
  // could not step off symmetrically.
  let k_patch = fn(k: Int) {
    case
      derivation.standard_patches([
        derivation.Dial(k: 1, radius: 5.0, phase_deg: 0.0),
        derivation.Dial(k: 2, radius: 4.0, phase_deg: 0.0),
        derivation.Dial(k: k, radius: 3.0, phase_deg: 0.0),
        derivation.Dial(k: 4, radius: 2.0, phase_deg: 0.0),
      ])
    {
      [_, _, derivation.KSet(patched), _] -> patched
      _ -> 999
    }
  }
  should.equal(4, k_patch(6))
  should.equal(-5, k_patch(-3))
  should.equal(-16, k_patch(-14))
  should.equal(-13, k_patch(-15))
  should.equal(-14, k_patch(-16))
}

pub fn degenerate_fixture_has_no_start_test() {
  // Nothing to start: no spectrum, no dial, no patches. The admin refuses to
  // save such a drawing, so this never reaches a player.
  let fixture =
    derivation.derive_fixture([#(10.0, 10.0), #(20.0, 20.0)], "x", "2026-10-25")
  should.equal([], fixture.patches)
}

// ---- the quaver's drawing, built from the toy's own term table -------------
// Copied from fourier_toy/src/fourier_toy/shapes.gleam quaver(): centroid
// #(58.3·cos 0.81, 58.3·sin 0.81), the same 29 (k, radius, phase-in-radians)
// rows, the same pipeline (first four = dial, phases snapped to 5°, the rest
// fixed extras, the target IS the synthesis). The test above pins the copy's
// honesty.

fn quaver_dots() -> List(#(Float, Float)) {
  let centroid = #(58.3 *. cos(0.81), 58.3 *. sin(0.81))
  let rows = quaver_table()
  let assert [d0, d1, d2, d3, ..extras] = rows
  let dial = [d0, d1, d2, d3]
  let chain = list.append(list.map(dial, fn(row) { snap5_row(row) }), extras)
  indices(derivation.sample_count)
  |> list.map(fn(i) {
    synthesis(
      centroid,
      chain,
      int.to_float(i) /. int.to_float(derivation.sample_count),
    )
  })
}

fn quaver_table() -> List(derivation.Dial) {
  [
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
  ]
  |> list.map(fn(row) {
    let #(k, radius, phase_rad) = row
    derivation.Dial(k: k, radius: radius, phase_deg: norm_deg(phase_rad))
  })
}

fn snap5_row(row: derivation.Dial) -> derivation.Dial {
  derivation.Dial(k: row.k, radius: row.radius, phase_deg: snap5(row.phase_deg))
}

/// Radians -> degrees 0..360 (the toy's norm_deg).
fn norm_deg(rad: Float) -> Float {
  let deg = rad /. pi *. 180.0
  case deg <. 0.0 {
    True -> deg +. 360.0
    False -> deg
  }
}

/// Snap to the 5° dial grid, 0..360 (the toy's shapes.snap5).
fn snap5(deg: Float) -> Float {
  mod360(int.to_float(float.round(deg /. 5.0)) *. 5.0)
}

fn mod360(x: Float) -> Float {
  case x <. 0.0, x >=. 360.0 {
    True, _ -> mod360(x +. 360.0)
    False, True -> mod360(x -. 360.0)
    False, False -> x
  }
}
