//// Core contracts (TDD): the fixture pipeline and the dial logic must
//// reproduce the archived JS prototype's ground-truth numbers.
//// Gold sources: prototype_js/generate_proto.mjs console output and its
//// jsdom artifact checks (tag prototype-js-v1).
////
//// A shape DIALS exactly its top-THREE terms; its 4th term lives in `extras`.
//// The synthesis term set is identical (top-4 = top-3 + extras[0]), so the
//// metric pins below hold whichever way the terms are split.

import fourier_toy/puzzle.{DialK, DialP, DialR, KSet, PhaseDeg, RPct}
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

// ---------- fixtures: the dialable truth is the top 3 terms ----------
// (the former 4th term is the first extra — same synthesis, new split)

pub fn star_dial_top3_gold_test() {
  let star = shapes.star()
  star.dial
  |> should.equal([
    shapes.TermState(1, 27.574653, 270.0),
    shapes.TermState(-4, 6.5871, 270.0),
    shapes.TermState(6, 2.927629, 270.0),
  ])
  // the star's 4th term is small and baked in, not dialed
  star.extras
  |> should.equal([shapes.TermState(-14, 0.537771, 270.0)])
}

pub fn flower_dial_top3_gold_test() {
  let flower = shapes.flower()
  let assert [d0, d1, d2] = flower.dial
  let shapes.TermState(k0, _, _) = d0
  k0 |> should.equal(1)
  approx(d0.r, 14.3, 1.0e-3)
  approx(d0.phase_deg, 0.0, 1.0e-6)
  let assert shapes.TermState(-5, _, 325.0) = d1
  approx(d1.r, 5.46, 1.0e-3)
  let assert shapes.TermState(7, _, 35.0) = d2
  approx(d2.r, 5.46, 1.0e-3)
  flower.extras
  |> should.equal([shapes.TermState(-11, 0.78, 0.0)])
}

pub fn fish_dial_top3_gold_test() {
  let fish = shapes.fish()
  fish.dial
  |> should.equal([
    shapes.TermState(-1, 26.07, 255.0),
    shapes.TermState(1, 16.27, 90.0),
    shapes.TermState(-2, 7.51, 340.0),
  ])
  // 28 table rows, 3 dialed ⇒ 26 baked extras; the head is the 4th term
  fish.extras |> list.length |> should.equal(26)
  fish.extras
  |> list.first
  |> should.equal(Ok(shapes.TermState(2, 4.9, 180.0)))
}

pub fn quaver_dial_top3_gold_test() {
  let quaver = shapes.quaver()
  quaver.dial
  |> should.equal([
    shapes.TermState(-1, 17.97, 265.0),
    shapes.TermState(1, 11.3, 305.0),
    shapes.TermState(-3, 4.68, 260.0),
  ])
  quaver.extras |> list.length |> should.equal(26)
  quaver.extras
  |> list.first
  |> should.equal(Ok(shapes.TermState(3, 2.83, 195.0)))
}

pub fn dial_max_r_unchanged_test() {
  // term 1 is the biggest dialable radius under BOTH splits (top-3 and
  // top-4), so the radius dial's unit — and its 200% ceiling — cannot move
  shapes.star().dial_max_r |> should.equal(27.574653)
  approx(shapes.flower().dial_max_r, 14.3, 1.0e-3)
  shapes.fish().dial_max_r |> should.equal(26.07)
  shapes.quaver().dial_max_r |> should.equal(17.97)
}

// ---------- metric parity with the archived JS prototype ----------

pub fn star_target_is_traced_not_synthesized_test() {
  // the star's cap = the truncation: the dial-at-truth cannot fully equal
  // the traced target — its match must sit in (96.5, 98.5)
  let star = shapes.star()
  let m = shapes.match_pct(star, star.dial)
  let assert True = m >. 96.5
  let assert True = m <. 98.5
  Nil
}

pub fn synthesizable_shapes_solve_to_about_100_test() {
  // flower + fish + quaver targets are rebuilt from their snapped synthesis,
  // so the dial-at-truth (plus its baked extras) solves them to ~100%; the
  // star cannot (traced).
  [shapes.flower(), shapes.fish(), shapes.quaver()]
  |> list.each(fn(shape) {
    let m = shapes.match_pct(shape, shape.dial)
    let assert True = m >. 99.9
    Nil
  })
}

// ---------- the 3-patch board ----------

pub fn quaver_setup_is_three_dials_test() {
  // the shipped puzzle dials exactly three terms — one of each kind
  let setup = puzzle.quaver_setup()
  setup.dials |> should.equal([DialP, DialR, DialK])
  setup.patches
  |> should.equal([PhaseDeg(355.0), RPct(73.0), KSet(-5)])
}

pub fn initial_resolves_three_patches_test() {
  // one patch per dialed slot, in chain order: slot 1's phase, slot 2's
  // radius (73% of the biggest dialable radius), slot 3's k
  let quaver = shapes.quaver()
  let state = puzzle.initial(quaver, puzzle.quaver_setup().patches)
  let assert [s0, s1, s2] = state
  should.equal(shapes.TermState(-1, 17.97, 355.0), s0)
  should.equal(1, s1.k)
  approx(s1.r, 0.73 *. 17.97, 1.0e-9)
  should.equal(305.0, s1.phase_deg)
  should.equal(shapes.TermState(-5, 4.68, 260.0), s2)
}

pub fn quaver_start_is_unsolved_gold_test() {
  // k −5 against the truth's −3 clamps the metric to 0: the served start is
  // a real puzzle, not the answer (the live seam check recorded the same)
  let quaver = shapes.quaver()
  let state = puzzle.initial(quaver, puzzle.quaver_setup().patches)
  shapes.match_pct(quaver, state) |> should.equal(0.0)
}

pub fn flower_p7_start_test() {
  // the flower start: phase +90° on the dominant, radius 72%, k +5 on slot 3
  // — a 4th patch would have no slot to land on
  let flower = shapes.flower()
  let state = puzzle.initial(flower, [PhaseDeg(90.0), RPct(72.0), KSet(5)])
  let assert [s0, s1, s2] = state
  // slot 1: phase patched to 90°, radius at truth (the max ⇒ dial_max_r)
  let shapes.TermState(k0, r0, p0) = s0
  should.equal(1, k0)
  approx(r0, 14.3, 1.0e-3)
  should.equal(90.0, p0)
  // slot 2: radius patched to 72% of max, k/phase at truth
  let shapes.TermState(k1, r1, p1) = s1
  should.equal(-5, k1)
  approx(r1, 0.72 *. 14.3, 1.0e-3)
  should.equal(325.0, p1)
  // slot 3: k patched to +5, radius/phase at truth
  let shapes.TermState(k2, r2, p2) = s2
  should.equal(5, k2)
  approx(r2, 5.46, 1.0e-3)
  should.equal(35.0, p2)
  // the start is visibly unsolved
  let m = shapes.match_pct(flower, state)
  let assert True = m <. 95.0
  Nil
}

pub fn fish_p8_start_clamps_to_zero_test() {
  // the fish start: phase +90° on the dominant, radius 72%, k−6 on slot 3
  let fish = shapes.fish()
  let state = puzzle.initial(fish, [PhaseDeg(345.0), RPct(72.0), KSet(-6)])
  shapes.match_pct(fish, state) |> should.equal(0.0)
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
