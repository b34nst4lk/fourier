//// Fixture derivation (PLAN-daily-puzzles.md §3 Q2): dots -> 512-pt
//// arc-length resample -> DFT -> dial truth (top-4 by amplitude) + fixed
//// extras + the 512-point target trace.
////
//// GOLD TEST: the sketch's star preset through this pipeline must reproduce
//// the recorded dialect-truth numbers of the toy's pipeline
//// (fourier_toy/shapes.gleam star fixture), radius tolerance 0.01 in sketch
//// units (0..100 space).
////
//// There was a SECOND gold here, for the starting patches: the quaver's own
//// drawing had to produce EXACTLY the patches the shipped toy boots with
//// (fourier_toy/puzzle.gleam p9: PhaseDeg(355.0), RPct(73.0), KSet(-5),
//// Keep). PLAN-varied-starts retired that: a served daily draws its own start
//// per puzzle (no cross-day recipe is learnable), so the backend no longer
//// reproduces the quaver's fixed start — the toy's quaver FALLBACK still
//// boots with it, because it is not part of the daily sequence. The quaver's
//// term table stays below, now as one of the DRAW probes: it still must run
//// through the whole pipeline and get the same varied draw as any drawing.
//// (The copy is from fourier_toy/shapes.gleam because toy_admin cannot depend
//// on the toy — it is a Lustre/JS package; this server is Erlang-native.)

import gleam/float
import gleam/int
import gleam/list
import gleeunit/should
import helpers.{be_close}
import sketch
import toy_admin/derivation
import toy_admin/fixture_json
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

// ---------- the varied draw (PLAN-varied-starts §1/§2) ----------------------
//
// The start is drawn per puzzle at save time: a pure hash over the dial truth
// picks a phase turn (45°..315°, on the 5° grid) and a nonzero k shift
// (±1..3, flipping at the k_min wall). Radius stays anchored at 73%, the fixed
// slot stays Keep. Expected values below are the plan's acceptance criteria.

pub fn quaver_drawing_derives_and_draws_a_varied_start_test() {
  // The quaver's own shape still runs the whole pipeline: its dial truth is
  // unchanged (the drawing is), and its start is now the same drawn start as
  // any other drawing's. This is what replaced the byte-parity gold: the toy's
  // quaver FALLBACK keeps its fixed p9 start, the served dailies no longer do.
  let fixture = derivation.derive_fixture(quaver_dots(), "eighth", "2026-11-02")
  // sanity: the drawing really is the quaver (dial truth by amplitude order)
  should.equal([-1, 1, -3, 3], list.map(fixture.dial, fn(row) { row.k }))
  should.equal(derivation.varied_patches(fixture.dial), fixture.patches)
  let assert [_, _, k_slot, _] = fixture.dial
  let assert [
    derivation.PhaseDeg(deg),
    derivation.RPct(pct),
    derivation.KSet(k),
    derivation.Keep,
  ] = fixture.patches
  should.equal(73.0, pct)
  should.not_equal(k_slot.k, k)
  should.be_true(deg >=. 0.0 && deg <. 360.0)
  should.be_true(on_grid(deg))
}

pub fn varied_patches_is_deterministic_test() {
  // §1 decision 5: the draw is a pure function of the puzzle. The same drawing
  // draws the same four patches on every call, so a re-save is reproducible
  // and no RNG state (nor OTP entropy) is anywhere in the pipeline.
  let dial = derived_dial(sketch.star())
  should.equal(4, list.length(derivation.varied_patches(dial)))
  should.equal(derivation.varied_patches(dial), derivation.varied_patches(dial))
  // The date is a label, not an input: two fixtures from the same dots agree.
  let early = derivation.derive_fixture(sketch.star(), "star", "2026-10-28")
  let later = derivation.derive_fixture(sketch.star(), "star", "2027-03-01")
  should.equal(early.patches, later.patches)
}

pub fn varied_phase_offset_is_far_and_on_grid_test() {
  // §1 decision 2: the turn is drawn on the 5° dial grid with magnitude in
  // [45°, 315°] — at least a 45° step from truth either direction (315° is
  // −45°), never a whole turn.
  list.each(probes(), fn(probe) {
    let #(label, dial) = probe
    let truth = slot_phase(dial)
    let offset = derivation.phase_offset_deg(derivation.dial_seed(dial))
    expect(
      offset >= 45,
      label <> ": phase offset below 45°, got " <> int.to_string(offset),
    )
    expect(
      offset <= 315,
      label <> ": phase offset above 315°, got " <> int.to_string(offset),
    )
    expect(
      offset % 5 == 0,
      label <> ": phase offset off the 5° grid, got " <> int.to_string(offset),
    )
    // The start IS that turn applied to truth, snapped onto the dial grid.
    let patch = start_phase(dial)
    should.equal(derivation.snap5(mod360(truth +. int.to_float(offset))), patch)
    expect(on_grid(patch), label <> ": start phase off the 5° grid")
    // The observed turn (after the snap's ±2.5° rounding) is still far.
    let turned = mod360(patch -. truth)
    expect(
      turned >=. 42.5 && turned <=. 317.5,
      label <> ": start phase is not a far turn from truth",
    )
  })
}

pub fn varied_k_shift_is_small_and_nonzero_test() {
  // §1 decision 3: the k shift is drawn nonzero from {−3, −2, −1, +1, +2, +3}.
  // The k dial always moves — and never by so much that the player has to hunt
  // for it — and the shift that was DRAWN is the one applied (flip included).
  list.each(probes(), fn(probe) {
    let #(label, dial) = probe
    let shift = derivation.drawn_k_shift(derivation.dial_seed(dial))
    expect(shift != 0, label <> ": the drawn k shift is zero")
    expect(
      list.contains(derivation.k_shifts, shift),
      label <> ": drawn k shift outside ±1..3: " <> int.to_string(shift),
    )
    let truth_k = slot_k(dial)
    let patched = start_k(dial)
    expect(patched != truth_k, label <> ": the patched k equals the truth")
    let expected = case truth_k + shift < derivation.k_min {
      True -> truth_k - shift
      False -> truth_k + shift
    }
    should.equal(expected, patched)
  })
}

pub fn k_wall_flip_generalizes_test() {
  // §1 decision 3's wall: at truth k = −15 a drawn −3 would leave the dial
  // (below k_min = −16), so the shift flips: −15 + 3 = −12, still inside the
  // dial with room to step back. A dial is SEARCHED for, not constructed: the
  // shift is a hash of the dial, so the test walks candidates until the draw
  // lands on −3.
  let dial = dial_drawing_shift(-3, -15)
  should.equal(-3, derivation.drawn_k_shift(derivation.dial_seed(dial)))
  let assert [_, _, derivation.KSet(patched), _] =
    derivation.varied_patches(dial)
  should.equal(-12, patched)
  should.be_true(patched >= derivation.k_min)
}

pub fn k_shift_stays_inside_the_dial_test() {
  // The retired −2 shift was kept inside the dial by a flip; that holds for
  // EVERY drawn shift, at every truth near the floor, and the slot always
  // moves (a flip never lands back on truth).
  [6, -3, -14, -15, -16]
  |> list.each(fn(truth_k) {
    list.each(derivation.k_shifts, fn(shift) {
      let patched = derivation.shifted_k(truth_k, shift)
      should.not_equal(truth_k, patched)
      should.be_true(patched >= derivation.k_min)
    })
  })
}

pub fn radius_stays_anchored_test() {
  // §1 decision 4: the radius dial is the anchor the ring's meaning is built
  // on (73% of the biggest dialable radius) — not varied, not ever.
  list.each(probes(), fn(probe) {
    let #(label, dial) = probe
    let assert [_, derivation.RPct(pct), _, _] = derivation.varied_patches(dial)
    expect(pct == 73.0, label <> ": the radius start moved off 73%")
  })
}

pub fn varied_start_is_the_documented_vocabulary_test() {
  // The slot vocabulary is unchanged (phase / radius / k / keep); only the
  // values are drawn now. The fixed slot still starts at its correct truth.
  let fixture = derivation.derive_fixture(sketch.star(), "star", "2026-10-25")
  let assert [phase_slot, _, d2, _] = fixture.dial
  let assert [
    derivation.PhaseDeg(deg),
    derivation.RPct(pct),
    derivation.KSet(k),
    derivation.Keep,
  ] = fixture.patches
  should.not_equal(phase_slot.phase_deg, deg)
  should.be_true(on_grid(deg))
  should.equal(73.0, pct)
  should.not_equal(d2.k, k)
}

pub fn varied_phase_still_snaps_to_the_dial_grid_test() {
  // The dial steps in 5°: a start off the grid could never be stepped onto.
  // The draw adds whole 5° steps, so only the truth's own off-grid-ness
  // (262.4° here) is rounded away — onto the grid, always.
  let dial = [
    derivation.Dial(k: 1, radius: 5.0, phase_deg: 262.4),
    derivation.Dial(k: 2, radius: 4.0, phase_deg: 12.0),
    derivation.Dial(k: 3, radius: 3.0, phase_deg: 0.0),
    derivation.Dial(k: 4, radius: 2.0, phase_deg: 90.0),
  ]
  let offset = derivation.phase_offset_deg(derivation.dial_seed(dial))
  let assert [derivation.PhaseDeg(deg), derivation.RPct(pct), _, _] =
    derivation.varied_patches(dial)
  should.equal(derivation.snap5(262.4 +. int.to_float(offset)), deg)
  should.be_true(on_grid(deg))
  should.equal(73.0, pct)
}

pub fn distinct_drawings_draw_distinctly_test() {
  // §1 decision 5: different drawings draw different offsets. Seven distinct
  // shapes, 55 × 6 = 330 possible draws — a single distinct member means the
  // draw is degenerate (a constant dressed up as a hash).
  let probes = probes()
  expect(list.length(probes) >= 6, "the probe set is smaller than six")
  let draws =
    list.map(probes, fn(probe) {
      let #(_, dial) = probe
      let seed = derivation.dial_seed(dial)
      #(derivation.phase_offset_deg(seed), derivation.drawn_k_shift(seed))
    })
    |> list.unique
  expect(
    list.length(draws) > 1,
    "every probe drawing drew the same (phase offset, k shift)",
  )
}

pub fn fixture_round_trips_varied_patches_test() {
  // fixture_json is untouched by the varied draw (§3): the same four slots on
  // the wire, only the values differ — and they survive encode/decode exactly.
  let fixture = derivation.derive_fixture(sketch.star(), "star", "2026-10-25")
  let assert Ok(decoded) = fixture_json.decode(fixture_json.to_string(fixture))
  should.equal(4, list.length(decoded.patches))
  should.equal(fixture.patches, decoded.patches)
}

pub fn degenerate_fixture_has_no_start_test() {
  // Nothing to start: no spectrum, no dial, no patches. The admin refuses to
  // save such a drawing, so this never reaches a player.
  let fixture =
    derivation.derive_fixture([#(10.0, 10.0), #(20.0, 20.0)], "x", "2026-10-25")
  should.equal([], fixture.patches)
}

// ---- the probe set: seven distinct drawings, one per shape family ----------
// Every "for each probe" test above walks this list. The shapes are distinct
// drawings (not one drawing translated: a translation changes only the DC
// term, so it would legitimately draw the same start).

fn probes() -> List(#(String, List(derivation.Dial))) {
  list.map(probe_drawings(), fn(drawing) {
    let #(label, dots) = drawing
    #(label, derived_dial(dots))
  })
}

fn probe_drawings() -> List(#(String, List(#(Float, Float)))) {
  [
    #("star", sketch.star()),
    #("heart", sketch.heart()),
    #("wobble", sketch.wobble()),
    #("quaver", quaver_dots()),
    #("triangle", regular_polygon(3, 34.0)),
    #("hexagon", regular_polygon(6, 30.0)),
    #("bitten-square", bitten_square()),
  ]
}

fn regular_polygon(count: Int, radius: Float) -> List(#(Float, Float)) {
  indices(count)
  |> list.map(fn(i) {
    let angle = 2.0 *. pi *. int.to_float(i) /. int.to_float(count) -. pi /. 2.0
    #(50.0 +. radius *. cos(angle), 50.0 +. radius *. sin(angle))
  })
}

/// A deliberately asymmetric six-gon: no symmetry to make the dial truth look
/// like the star's or the hexagon's.
fn bitten_square() -> List(#(Float, Float)) {
  [
    #(20.0, 20.0),
    #(80.0, 18.0),
    #(82.0, 55.0),
    #(60.0, 60.0),
    #(78.0, 84.0),
    #(24.0, 80.0),
  ]
}

/// A derived dial for one drawing.
fn derived_dial(dots: List(#(Float, Float))) -> List(derivation.Dial) {
  derivation.derive_fixture(dots, "probe", "2026-10-25").dial
}

fn slot_phase(dial: List(derivation.Dial)) -> Float {
  let assert [phase_slot, _, _, _] = dial
  phase_slot.phase_deg
}

fn slot_k(dial: List(derivation.Dial)) -> Int {
  let assert [_, _, k_slot, _] = dial
  k_slot.k
}

fn start_phase(dial: List(derivation.Dial)) -> Float {
  let assert [derivation.PhaseDeg(deg), _, _, _] =
    derivation.varied_patches(dial)
  deg
}

fn start_k(dial: List(derivation.Dial)) -> Int {
  let assert [_, _, derivation.KSet(k), _] = derivation.varied_patches(dial)
  k
}

/// A dial that DRAWS `wanted` as its k shift, with its k slot at `truth_k`.
/// Searched rather than constructed: the shift is a hash of the dial, so the
/// test walks candidate truths until the draw lands on the shift under test.
/// 360 candidates over a 6-outcome draw cannot all miss in practice; if the
/// hash ever changes shape, this fails loudly rather than silently skipping.
fn dial_drawing_shift(wanted: Int, truth_k: Int) -> List(derivation.Dial) {
  let assert Ok(dial) =
    indices(360)
    |> list.map(fn(i) {
      [
        derivation.Dial(k: 1, radius: 5.0, phase_deg: int.to_float(i)),
        derivation.Dial(k: 2, radius: 4.0, phase_deg: 12.0),
        derivation.Dial(k: truth_k, radius: 3.0, phase_deg: 0.0),
        derivation.Dial(k: 4, radius: 2.0, phase_deg: 90.0),
      ]
    })
    |> list.find(fn(candidate) {
      derivation.drawn_k_shift(derivation.dial_seed(candidate)) == wanted
    })
  dial
}

/// An assertion with a message that names the probe: a bare `should.be_true`
/// on a per-probe loop says WHICH loop failed, not which shape.
fn expect(condition: Bool, what: String) -> Nil {
  case condition {
    True -> Nil
    False -> panic as what
  }
}

/// Is this a multiple of 5°? Written as "the step count is a whole number" so
/// it does not lean on the implementation's own snap5 (floats have no `%`).
fn on_grid(deg: Float) -> Bool {
  let steps = deg /. 5.0
  steps == int.to_float(float.round(steps))
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
