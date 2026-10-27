//// The score port's tests.
////
//// Three layers of ground truth, strongest first:
////   1. star_fixture.gleam — the REAL star fixture from the backend's
////      derivation pipeline (arc-length resample + DFT). If the port's sampling
////      convention, units, chain order or normalizer drift, these numbers move.
////   2. analytic cases — a circle reproduced exactly (100%), a 10% radius error
////      (90%), a phase rotation by hand. Exact maths, not recorded output.
////   3. the toy's start patch — the admin's test play must open far from the
////      answer (clamped to 0), exactly as the toy's does.

import admin_ui/score
import gleam/list
import gleeunit/should
import star_fixture
import test_helpers.{close}

pub fn a_term_rotates_from_the_centroid_in_degrees_test() {
  // k = 1, r = 10, phase 90° at t = 0 -> ten units along +y. Sketch space has
  // y growing DOWN (the toys' own convention: the star's y runs 10..82), so a
  // +90° phase is the bottom of the circle. This pins degrees->radians and the
  // t = 0 alignment.
  let here = score.position_at(#(50.0, 50.0), [score.Term(1, 10.0, 90.0)], 0.0)
  close(here.0, 50.0, 1.0e-9)
  close(here.1, 60.0, 1.0e-9)

  // a quarter period later the same term points 180°: (40, 50)
  let quarter =
    score.position_at(#(50.0, 50.0), [score.Term(1, 10.0, 90.0)], 0.25)
  close(quarter.0, 40.0, 1.0e-9)
  close(quarter.1, 50.0, 1.0e-9)
}

pub fn a_reproduced_trace_scores_one_hundred_test() {
  let centroid = #(50.0, 50.0)
  let truth = [score.Term(1, 10.0, 0.0), score.Term(-3, 4.0, 33.0)]
  let target = score.synth_trace(centroid, truth)
  let normalizer = score.rms_polar(target, centroid.0, centroid.1)

  let perfect = score.match_pct(centroid, truth, target, normalizer)
  close(perfect, 100.0, 1.0e-9)
}

pub fn the_metric_normalises_by_the_target_radius_test() {
  // A 10-unit radius target, a 9-unit chain: the error is exactly 1 unit, so
  // the score is exactly (1 - 1/10) * 100. Pins the normalizer AND the linear
  // response (a 512-sample denominator, not a running mean).
  let centroid = #(50.0, 50.0)
  let target = score.synth_trace(centroid, [score.Term(1, 10.0, 0.0)])
  let normalizer = score.rms_polar(target, centroid.0, centroid.1)
  close(normalizer, 10.0, 1.0e-9)

  let short =
    score.match_pct(centroid, [score.Term(1, 9.0, 0.0)], target, normalizer)
  close(short, 90.0, 1.0e-9)

  // a collapsed chain sits at the centroid: every sample is 10 units off, so
  // the raw score is exactly 0
  let collapsed =
    score.match_pct(centroid, [score.Term(1, 0.0, 0.0)], target, normalizer)
  close(collapsed, 0.0, 1.0e-9)
  // and a wild guess clamps at 0 rather than showing a negative score
  let absurd =
    score.match_pct(centroid, [score.Term(1, 40.0, 0.0)], target, normalizer)
  close(absurd, 0.0, 1.0e-9)
}

pub fn extras_are_chained_after_the_dial_terms_test() {
  // The fish/quaver depend on this: extras are real epicycles appended to the
  // chain, not a constant offset. With them the trace is exact; without them
  // it is visibly off.
  let centroid = #(40.0, 55.0)
  let dial = [score.Term(1, 20.0, 15.0), score.Term(-2, 7.0, 200.0)]
  let extras = [score.Term(3, 2.0, 40.0), score.Term(-5, 0.8, 300.0)]
  let target =
    score.synth_trace(centroid, [
      score.Term(1, 20.0, 15.0),
      score.Term(-2, 7.0, 200.0),
      score.Term(3, 2.0, 40.0),
      score.Term(-5, 0.8, 300.0),
    ])
  let normalizer = score.rms_polar(target, centroid.0, centroid.1)

  close(
    score.match_pct(centroid, list.append(dial, extras), target, normalizer),
    100.0,
    1.0e-9,
  )
  let missing = score.match_pct(centroid, dial, target, normalizer)
  should.equal(True, missing <. 100.0)
  should.equal(True, missing >. 50.0)
}

pub fn the_recorded_star_scores_ninety_seven_point_six_nine_test() {
  // The real fixture (star_fixture.gleam): four dialable terms, no extras. The
  // derivation's own measurement of that approximation is 97.6889%.
  let target = star_fixture.target()
  let normalizer =
    score.rms_polar(target, star_fixture.centroid.0, star_fixture.centroid.1)
  close(normalizer, star_fixture.rms_polar, 1.0e-6)

  let match =
    score.match_pct(
      star_fixture.centroid,
      star_fixture.dial(),
      target,
      normalizer,
    )
  close(match, 97.68891741835091, 1.0e-6)
  should.equal(True, match >. 97.0)
  should.equal(True, score.solved(match))
}

pub fn the_toys_start_patch_scores_zero_not_negative_test() {
  // The admin's test play opens where the toy's shipped puzzle opens (phase
  // 0°, radius 72%, k 8, slot 4 untouched): raw -45.21%, displayed 0. The
  // editor must feel the same distance from the answer a player does.
  let target = star_fixture.target()
  let normalizer =
    score.rms_polar(target, star_fixture.centroid.0, star_fixture.centroid.1)
  let max_r = 27.574653306648354
  let start = [
    score.Term(1, 27.574653306648354, 0.0),
    score.Term(-4, 0.72 *. max_r, 270.0000000000019),
    score.Term(8, 2.9276293593855414, 270.00000000000006),
    score.Term(-14, 0.5377710335446912, 270.0000000000257),
  ]
  let match = score.match_pct(star_fixture.centroid, start, target, normalizer)
  close(match, 0.0, 1.0e-9)
  should.equal(True, match <. 70.0)
}

pub fn the_full_synthesis_is_the_rule_that_clears_the_badge_test() {
  // The reported symptom in test play: a drawing solved to the eye scored 91.9%
  // — under the badge — because only the four dial terms reached the metric
  // while the comet drew dial terms CHAINED WITH the extras. This analytic pair
  // is that drawing in miniature: the extras' curvature is worth 8.5 points, so
  // the two candidate rules straddle the badge.
  let centroid = #(50.0, 50.0)
  let dial_terms = [
    score.Term(1, 20.0, 0.0),
    score.Term(-2, 7.0, 30.0),
    score.Term(3, 4.0, 45.0),
  ]
  let extras = [score.Term(5, 1.6, 10.0), score.Term(-7, 0.9, 120.0)]
  let target = score.synth_trace(centroid, list.append(dial_terms, extras))
  let normalizer = score.rms_polar(target, 50.0, 50.0)

  // the rule: dial terms first, then the extras chained after them
  let full =
    score.synthesis_match(centroid, dial_terms, extras, target, normalizer)
  close(full, 100.0, 1.0e-9)
  should.equal(True, score.solved(full))

  // the bug: score the dials alone and the same picture never lights the badge
  let dial_only = score.match_pct(centroid, dial_terms, target, normalizer)
  close(dial_only, 91.51756743926322, 1.0e-6)
  should.equal(False, score.solved(dial_only))

  // ...and on a puzzle with no extras the rule is the plain metric (no drift
  // for the shapes the derivation happens to approximate with four terms)
  let bare = score.synth_trace(centroid, dial_terms)
  let bare_normalizer = score.rms_polar(bare, 50.0, 50.0)
  close(
    score.synthesis_match(centroid, dial_terms, [], bare, bare_normalizer),
    100.0,
    1.0e-9,
  )
}

pub fn the_star_at_truth_needs_its_extras_to_clear_the_gold_test() {
  // The real fixture with the real 507 extras: the full synthesis is 99.99998%
  // (a solved star), the four dials alone are 97.6889%. The gap is exactly what
  // the editor was hiding from the score.
  let target = star_fixture.target()
  let normalizer =
    score.rms_polar(target, star_fixture.centroid.0, star_fixture.centroid.1)
  let full =
    score.synthesis_match(
      star_fixture.centroid,
      star_fixture.dial(),
      star_fixture.extras(),
      target,
      normalizer,
    )
  close(full, 99.99997685463386, 1.0e-6)
  should.equal(True, full >=. 99.9)

  // the four dials alone are 97.6889 — solved, but not the near-exact number
  // the picture deserves (the rich case above straddles the badge; this one
  // straddles the "you matched it" reading)
  let dial_only =
    score.match_pct(
      star_fixture.centroid,
      star_fixture.dial(),
      target,
      normalizer,
    )
  close(dial_only, 97.68891737585086, 1.0e-6)
  should.equal(True, dial_only <. 99.9)
  // the fixture carries the rest of the spectrum, not a token sample
  should.equal(507, list.length(star_fixture.extras()))
}
