//// The dial state machine's tests (PLAN-daily-puzzles.md §3 Q19).
////
//// These assert the PLAYER experience the editor must reproduce, so the
//// expectations are the toy's numbers: ±1 k clamped at ±16, ±5° phase that
//// wraps, ±2%-of-max radius clamped to 0..200%, fixed slots immovable, and the
//// shipped p6 start (phase 0°, radius 72%, k 8, fourth slot untouched).

import admin_ui/dial
import admin_ui/score
import gleam/list
import gleeunit/should
import test_helpers.{close}

fn truth() -> List(score.Term) {
  [
    score.Term(1, 27.574653306648354, 270.0),
    score.Term(-4, 6.587099924414947, 270.0),
    score.Term(6, 2.9276293593855414, 270.0),
    score.Term(-14, 0.5377710335446912, 270.0),
  ]
}

fn slot(terms: List(score.Term), index: Int) -> score.Term {
  let assert [term, ..] = list.drop(terms, index)
  term
}

fn kinds() -> List(dial.Kind) {
  [dial.KindPhase, dial.KindRadius, dial.KindK, dial.KindFixed]
}

pub fn a_k_dial_steps_by_one_and_clamps_at_sixteen_test() {
  let term = score.Term(15, 4.0, 90.0)
  let up = dial.step(dial.KindK, term, 1, 10.0)
  should.equal(16, up.k)
  // 16 is the ceiling: another step up is a no-op, not 17
  should.equal(16, dial.step(dial.KindK, up, 1, 10.0).k)
  should.equal(15, dial.step(dial.KindK, up, -1, 10.0).k)

  let floor = score.Term(-16, 4.0, 90.0)
  should.equal(-16, dial.step(dial.KindK, floor, -1, 10.0).k)
  should.equal(-15, dial.step(dial.KindK, floor, 1, 10.0).k)
  // k moves nothing else
  should.equal(4.0, up.radius)
  should.equal(90.0, up.phase_deg)
}

pub fn a_phase_dial_steps_by_five_degrees_and_wraps_test() {
  let term = score.Term(1, 4.0, 355.0)
  close(dial.step(dial.KindPhase, term, 1, 10.0).phase_deg, 0.0, 1.0e-9)
  close(dial.step(dial.KindPhase, term, -1, 10.0).phase_deg, 350.0, 1.0e-9)
  close(
    dial.step(dial.KindPhase, score.Term(1, 4.0, 2.0), -1, 10.0).phase_deg,
    357.0,
    1.0e-9,
  )
  // the angle is the only thing that moves
  should.equal(4.0, dial.step(dial.KindPhase, term, 1, 10.0).radius)
}

pub fn a_radius_dial_steps_by_two_percent_of_the_largest_and_clamps_test() {
  let max_r = 27.574653306648354
  let unit = 0.02 *. max_r
  let term = score.Term(1, max_r, 90.0)

  close(
    dial.step(dial.KindRadius, term, 1, max_r).radius,
    max_r +. unit,
    1.0e-9,
  )
  close(
    dial.step(dial.KindRadius, term, -1, max_r).radius,
    max_r -. unit,
    1.0e-9,
  )

  // 200% of the largest is the ceiling
  let near_ceiling = score.Term(1, 1.99 *. max_r, 90.0)
  close(
    dial.step(dial.KindRadius, near_ceiling, 1, max_r).radius,
    2.0 *. max_r,
    1.0e-9,
  )
  // and the step never goes below zero
  let tiny = score.Term(1, 0.01 *. max_r, 90.0)
  close(dial.step(dial.KindRadius, tiny, -1, max_r).radius, 0.0, 1.0e-9)
  // no overshoot below zero either
  close(
    dial.step(dial.KindRadius, score.Term(1, 0.0, 90.0), -1, max_r).radius,
    0.0,
    1.0e-9,
  )
}

pub fn a_fixed_dial_never_moves_test() {
  let term = score.Term(-7, 3.5, 33.0)
  let moved = dial.step(dial.KindFixed, term, 1, 10.0)
  should.equal(score.Term(-7, 3.5, 33.0), moved)
  should.equal(term, dial.step(dial.KindFixed, term, -1, 10.0))
}

pub fn the_arrangement_speaks_the_wires_language_test() {
  // The four words on the fixture's `dials` array; the editor reads kinds off
  // the wire and writes them back, so the round trip must be lossless.
  should.equal(Ok(dial.KindPhase), dial.parse_kind("phase"))
  should.equal(Ok(dial.KindRadius), dial.parse_kind("radius"))
  should.equal(Ok(dial.KindK), dial.parse_kind("k"))
  should.equal(Ok(dial.KindFixed), dial.parse_kind("fixed"))
  should.equal(Error(Nil), dial.parse_kind("phase_deg"))

  should.equal("phase", dial.name_of(dial.KindPhase))
  should.equal("radius", dial.name_of(dial.KindRadius))
  should.equal("k", dial.name_of(dial.KindK))
  should.equal("fixed", dial.name_of(dial.KindFixed))
}

pub fn the_shipped_start_patch_opens_where_the_toy_opens_test() {
  let start = dial.initial(truth(), kinds(), dial.standard_patches())
  let max_r = dial.max_radius(truth())

  // slot 1: phase pinned to 0, radius and k still true
  close(slot(start, 0).phase_deg, 0.0, 1.0e-9)
  close(slot(start, 0).radius, 27.574653306648354, 1.0e-9)
  should.equal(1, slot(start, 0).k)
  // slot 2: radius at 72% of the largest, phase and k untouched
  close(slot(start, 1).radius, 0.72 *. max_r, 1.0e-9)
  close(slot(start, 1).phase_deg, 270.0, 1.0e-9)
  should.equal(-4, slot(start, 1).k)
  // slot 3: k moved to 8
  should.equal(8, slot(start, 2).k)
  // slot 4: fixed, at truth
  should.equal(score.Term(-14, 0.5377710335446912, 270.0), slot(start, 3))
}

pub fn a_fixed_slot_ignores_a_patch_meant_for_it_test() {
  // Guards the slot bookkeeping: fixed slots consume no patch, so a
  // perturbation can never land on a dial nobody is allowed to turn.
  let start =
    dial.initial(truth(), kinds(), [
      dial.PhaseDeg(0.0),
      dial.RPct(72.0),
      dial.KSet(8),
      dial.KSet(0),
    ])
  should.equal(score.Term(-14, 0.5377710335446912, 270.0), slot(start, 3))
  // ...and the third slot still got ITS patch, not the fixed slot's
  should.equal(8, slot(start, 2).k)
}

pub fn the_readouts_are_the_toys_test() {
  let max_r = 27.574653306648354
  should.equal("+5", dial.fmt_k(5))
  should.equal("−5", dial.fmt_k(-5))
  should.equal(
    "k +5",
    dial.slot_value(dial.KindK, score.Term(5, 1.0, 0.0), max_r),
  )
  should.equal(
    "270°",
    dial.slot_value(dial.KindPhase, score.Term(5, 1.0, 270.4), max_r),
  )
  should.equal(
    "50%",
    dial.slot_value(dial.KindRadius, score.Term(5, 0.5 *. max_r, 0.0), max_r),
  )
  should.equal("97.7", dial.fmt1(97.68891741835091))
  should.equal("100.0", dial.fmt1(100.0))
}

pub fn the_derived_readout_speaks_the_dial_rows_words_test() {
  // Q2/Q3: the derived truths are shown before a save, one bullet per movable
  // slot. A bullet says which dial it is and what that slot is set to — in the
  // dial row's own words, so the readout and the stepper it describes cannot
  // drift apart.
  let max_r = 27.574653306648354
  should.equal("phase dial", dial.slot_label(dial.KindPhase))
  should.equal("radius dial", dial.slot_label(dial.KindRadius))
  should.equal("k dial", dial.slot_label(dial.KindK))
  should.equal("fixed term", dial.slot_label(dial.KindFixed))

  should.equal(
    "φ 270°",
    dial.truth_value(
      dial.KindPhase,
      score.Term(1, 27.574653306648354, 270.0),
      max_r,
    ),
  )
  should.equal(
    "r 100%",
    dial.truth_value(
      dial.KindRadius,
      score.Term(1, 27.574653306648354, 90.0),
      max_r,
    ),
  )
  should.equal(
    "k −4",
    dial.truth_value(dial.KindK, score.Term(-4, 6.587099924414947, 90.0), max_r),
  )

  // the value half is the STEPPER's readout, lettered — not a second formatter
  // that agrees with it today
  let term = score.Term(-4, 6.587099924414947, 270.0)
  should.equal(
    "φ " <> dial.slot_value(dial.KindPhase, term, max_r),
    dial.truth_value(dial.KindPhase, term, max_r),
  )
  should.equal(
    "r " <> dial.slot_value(dial.KindRadius, term, max_r),
    dial.truth_value(dial.KindRadius, term, max_r),
  )
  should.equal(
    dial.slot_value(dial.KindK, term, max_r),
    dial.truth_value(dial.KindK, term, max_r),
  )
}

pub fn kind_codes_are_the_canvas_ink_contract_test() {
  // canvas.mjs's term_color switches on these codes to ink a chain row: red =
  // phase, yellow = radius, blue = k, neutral = fixed. The colour follows the
  // KIND (the arrangement is data), so a re-arranged puzzle keeps its colours —
  // the numbers may never move without the .mjs switch moving with them.
  should.equal(0, dial.kind_code(dial.KindPhase))
  should.equal(1, dial.kind_code(dial.KindRadius))
  should.equal(2, dial.kind_code(dial.KindK))
  should.equal(3, dial.kind_code(dial.KindFixed))
}
