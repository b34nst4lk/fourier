//// v2 core contracts (TDD): the fixture pipeline and the dial logic must
//// reproduce the archived JS prototype's ground-truth numbers.
//// Gold sources: prototype_js/generate_proto.mjs console output and its
//// jsdom artifact checks (tag prototype-js-v1).

import fourier_toy/puzzle.{DialK, DialP, DialR, KSet, Keep, PhaseDeg, RPct}
import fourier_toy/shapes
import gleam/int
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn approx(a: Float, b: Float, eps: Float) -> Nil {
  let delta = case a -. b >. 0.0 {
    True -> a -. b
    False -> b -. a
  }
  let assert True = delta <. eps
  Nil
}

// ---------- fixtures: dialable truth matches the JS prototype ----------

pub fn star_dial_gold_test() {
  let star = shapes.star()
  star.dial
  |> should.equal([
    shapes.TermState(1, 27.574653, 270.0),
    shapes.TermState(-4, 6.5871, 270.0),
    shapes.TermState(6, 2.927629, 270.0),
    shapes.TermState(-14, 0.537771, 270.0),
  ])
  star.extras |> list.length |> should.equal(0)
}

pub fn star_target_is_traced_not_synthesized_test() {
  // the star's cap = the truncation: the dial-at-truth cannot fully equal
  // the traced target — its match must sit in (96.5, 98.5)
  let star = shapes.star()
  let m = shapes.match_pct(star, star.dial)
  let assert True = m >. 96.5
  let assert True = m <. 98.5
  Nil
}

pub fn flower_dial_gold_test() {
  let flower = shapes.flower()
  let assert [d0, d1, d2, d3] = flower.dial
  let shapes.TermState(k0, _, _) = d0
  k0 |> should.equal(1)
  approx(d0.r, 14.3, 1.0e-3)
  approx(d0.phase_deg, 0.0, 1.0e-6)
  let assert shapes.TermState(-5, _, 325.0) = d1
  approx(d1.r, 5.46, 1.0e-3)
  let assert shapes.TermState(7, _, 35.0) = d2
  approx(d2.r, 5.46, 1.0e-3)
  let assert shapes.TermState(-11, 0.78, 0.0) = d3
  flower.extras |> list.length |> should.equal(0)
}

pub fn fish_dial_gold_and_extras_count_test() {
  let fish = shapes.fish()
  let assert [
    shapes.TermState(-1, 26.07, 255.0),
    shapes.TermState(1, 16.27, 90.0),
    shapes.TermState(-2, 7.51, 340.0),
    shapes.TermState(2, 4.9, 180.0),
  ] = fish.dial
  fish.extras |> list.length |> should.equal(25)
}

pub fn quaver_dial_gold_and_extras_count_test() {
  let quaver = shapes.quaver()
  let assert [
    shapes.TermState(-1, 17.97, 265.0),
    shapes.TermState(1, 11.3, 305.0),
    shapes.TermState(-3, 4.68, 260.0),
    shapes.TermState(3, 2.83, 195.0),
  ] = quaver.dial
  quaver.extras |> list.length |> should.equal(25)
}

// ---------- metric parity with the archived JS prototype ----------

pub fn synthesizable_shapes_solve_to_about_100_test() {
  // flower + fish + quaver targets are rebuilt from their snapped synthesis,
  // so the dial-at-truth solves them to ~100%; the star cannot (traced).
  [shapes.flower(), shapes.fish(), shapes.quaver()]
  |> list.each(fn(shape) {
    let m = shapes.match_pct(shape, shape.dial)
    let assert True = m >. 99.9
    Nil
  })
}

pub fn star_initial_p3_match_gold_test() {
  // P3's star start (radii 72%/8%/0%/0%) = 67.1% in the JS prototype
  let star = shapes.star()
  let initial = [
    shapes.TermState(1, 0.72 *. star.dial_max_r, 270.0),
    shapes.TermState(-4, 0.08 *. star.dial_max_r, 270.0),
    shapes.TermState(6, 0.0, 270.0),
    shapes.TermState(-14, 0.0, 270.0),
  ]
  approx(shapes.match_pct(star, initial), 67.1, 0.15)
}

pub fn fish_initial_p8_start_clamps_to_zero_test() {
  // P8 start: phase +90° on the dominant, radius 72%, k−2 on slot 3
  let fish = shapes.fish()
  let state =
    puzzle.initial(fish, [
      PhaseDeg(345.0),
      RPct(72.0),
      KSet(-6),
      Keep,
    ])
  shapes.match_pct(fish, state) |> should.equal(0.0)
}

pub fn flower_initial_p10_start_test() {
  let flower = shapes.flower()
  let state =
    puzzle.initial(flower, [
      PhaseDeg(90.0),
      RPct(72.0),
      KSet(5),
      RPct(16.0),
    ])
  let assert [s0, s1, s2, s3] = state
  // slot1 keeps its truth radius; phase patched to 90°
  let assert shapes.TermState(1, _, 90.0) = s0
  approx(s0.r, flower.dial_max_r, 1.0e-9)
  // slot2 radius patched to 72% of max, truth phase kept (325°)
  let assert shapes.TermState(-5, _, 325.0) = s1
  approx(s1.r, 0.72 *. flower.dial_max_r, 1.0e-9)
  // slot3 k patched to +5, radius/phase kept
  let assert shapes.TermState(5, _, 35.0) = s2
  // slot4 radius patched to 16% of max, k/phase kept
  let assert shapes.TermState(-11, _, 0.0) = s3
  approx(s3.r, 0.16 *. flower.dial_max_r, 1.0e-9)
  // the start is visibly unsolved
  let m = shapes.match_pct(flower, state)
  let assert True = m <. 95.0
  Nil
}

// ---------- dial stepping contracts ----------

pub fn phase_step_wraps_test() {
  puzzle.step(DialP, shapes.TermState(1, 5.0, 0.0), -1, 10.0)
  |> should.equal(shapes.TermState(1, 5.0, 355.0))
  puzzle.step(DialP, shapes.TermState(1, 5.0, 0.0), 1, 10.0)
  |> should.equal(shapes.TermState(1, 5.0, 5.0))
}

pub fn radius_step_has_floor_and_ceiling_test() {
  let max_r = 20.0
  let max_state = shapes.TermState(1, 2.0 *. max_r, 0.0)
  puzzle.step(DialR, max_state, 1, max_r) |> should.equal(max_state)
  let zero_state = shapes.TermState(1, 0.0, 0.0)
  puzzle.step(DialR, zero_state, -1, max_r) |> should.equal(zero_state)
  puzzle.step(DialR, shapes.TermState(1, 1.0, 0.0), 1, max_r)
  |> should.equal(shapes.TermState(1, 1.0 +. 0.02 *. max_r, 0.0))
}

pub fn k_step_clamps_test() {
  puzzle.step(DialK, shapes.TermState(16, 1.0, 0.0), 1, 10.0)
  |> should.equal(shapes.TermState(16, 1.0, 0.0))
  puzzle.step(DialK, shapes.TermState(-16, 1.0, 0.0), -1, 10.0)
  |> should.equal(shapes.TermState(-16, 1.0, 0.0))
  puzzle.step(DialK, shapes.TermState(1, 1.0, 0.0), -1, 10.0)
  |> should.equal(shapes.TermState(0, 1.0, 0.0))
}

// ---------- solvability helpers ----------

pub fn solved_threshold_test() {
  let flower = shapes.flower()
  shapes.solved(flower, flower.dial) |> should.be_true
  shapes.solved(flower, [
    shapes.TermState(1, 14.3, 90.0),
    ..list.drop(flower.dial, 1)
  ])
  |> should.be_false
}

pub fn k_int_to_float_sanity_test() {
  int.to_float(3) |> should.equal(3.0)
}

// ---------- display contracts: the row small print tells the truth ----------

pub fn locked_note_names_the_locked_fields_test() {
  let quaver = shapes.quaver()
  let assert [s0, s1, s2, s3] = quaver.dial
  let max_r = quaver.dial_max_r
  // display helpers via the public readouts: pct through the radius readout,
  // deg through the phase readout — numbers come from the fixture itself
  let pct = fn(s) { puzzle.slot_value(DialR, s, max_r) }
  let deg = fn(s) { puzzle.slot_value(DialP, s, max_r) }

  // the phase dial's small print locks r and k — NOT φ (φ is what this dial
  // changes; the DialP branch once printed r · φ)
  let phase_note = puzzle.locked_note(DialP, s0, max_r)
  phase_note
  |> should.equal("locked: r " <> pct(s0) <> " · k " <> puzzle.fmt_k(s0.k))

  let radius_note = puzzle.locked_note(DialR, s1, max_r)
  radius_note
  |> should.equal("locked: k " <> puzzle.fmt_k(s1.k) <> " · φ " <> deg(s1))

  let k_note = puzzle.locked_note(DialK, s2, max_r)
  k_note |> should.equal("locked: r " <> pct(s2) <> " · φ " <> deg(s2))

  let fixed_note = puzzle.locked_note(puzzle.DialFixed, s3, max_r)
  fixed_note
  |> should.equal(
    "fixed, correct: k "
    <> puzzle.fmt_k(s3.k)
    <> " · r "
    <> pct(s3)
    <> " · φ "
    <> deg(s3),
  )
}

// ---------- the canvas ink contract: colour follows the KIND ----------
// The FFI's PALETTES are keyed on puzzle.kind_code (fourier_toy_ffi.mjs
// term_color), and each dial row's readout wears puzzle.kind_class in
// index.html. Both follow the KIND — so a rearranged puzzle still inks its
// phase dial red, its radius dial yellow and its k dial blue, never the slot
// index (the arrangement is data: v1 is P/R/K/Fixed, and slot 4 is fixed).
// The codes are a wire contract with the .mjs palette switch: they may never
// be renumbered without moving that switch.
pub fn kind_ink_is_keyed_on_the_dial_kind_test() {
  puzzle.kind_code(DialP) |> should.equal(0)
  puzzle.kind_code(DialR) |> should.equal(1)
  puzzle.kind_code(DialK) |> should.equal(2)
  puzzle.kind_code(puzzle.DialFixed) |> should.equal(3)

  puzzle.kind_class(DialP) |> should.equal("kind-phase")
  puzzle.kind_class(DialR) |> should.equal("kind-radius")
  puzzle.kind_class(DialK) |> should.equal("kind-k")
  puzzle.kind_class(puzzle.DialFixed) |> should.equal("kind-fixed")
}
