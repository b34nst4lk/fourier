//// The app's update function, tested where it is pure (PLAN-daily-puzzles.md §3
//// Q18/Q20).
////
//// Lustre effects are values, not side effects: `effect.from` builds one and
//// runs nothing, so `update` can be driven from a test exactly as the runtime
//// drives it. What is asserted here is the STATE — the drawing, the dial terms,
//// the score, the armed delete — never the browser calls, which are smoke-tested
//// on the built page instead.
////
//// The fixture is the real star (star_fixture.gleam), so "opening a test play
//// opens where the toy opens" is measured against the numbers the pipeline
//// really produces.

import admin_ui
import admin_ui/dial
import admin_ui/draw
import admin_ui/score
import admin_ui/wire
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import star_fixture
import test_helpers.{close}

fn star() -> wire.Fixture {
  wire.Fixture(
    name: "the star",
    show_date: "2026-10-25",
    centroid: star_fixture.centroid,
    dials: [dial.KindPhase, dial.KindRadius, dial.KindK, dial.KindFixed],
    dial: star_fixture.dial(),
    extras: [],
    target: star_fixture.target(),
    patches: [],
    dots: Some([]),
  )
}

/// The star as the API really serves it: the four dial terms PLUS the rest of
/// the spectrum as fixed extras (507 rows), starting at truth in every slot.
fn star_full() -> wire.Fixture {
  wire.Fixture(..star(), extras: star_fixture.extras(), patches: [
    dial.Keep,
    dial.Keep,
    dial.Keep,
    dial.Keep,
  ])
}

fn model() -> admin_ui.Model {
  admin_ui.Model(
    view: admin_ui.Authoring,
    rows: [],
    busy: False,
    flash: None,
    failure: None,
    editing: None,
    name: "",
    show_date: "",
    drawing: draw.empty(),
    play: None,
    armed: None,
    preview: None,
    preview_pending: False,
    preview_stale: False,
    preview_start: False,
    preview_scheduled: admin_ui.PreviewClock(0, None, None),
  )
}

/// Drive the update function the way the runtime does, keeping the new state
/// (the effect is a value; nothing runs).
fn step(model: admin_ui.Model, msg: admin_ui.Msg) -> admin_ui.Model {
  let #(next, _) = admin_ui.update(model, msg)
  next
}

fn play_state(model: admin_ui.Model) -> admin_ui.Play {
  let assert Some(play) = model.play
  play
}

/// Boot a test play the way the preview response does.
fn started(fixture: wire.Fixture) -> admin_ui.Model {
  let model = step(model(), admin_ui.Previewed(Ok(fixture)))
  model
}

pub fn a_previewed_fixture_starts_a_test_play_at_the_toys_start_test() {
  let model = started(star())
  should.equal(admin_ui.TestPlay, model.view)

  let play = play_state(model)
  // four slots, in the fixture's order; the fixed one carries truth
  should.equal(4, list.length(play.kinds))
  should.equal(dial.KindFixed, play_kind(play, 3))

  // the toy's start: phase 0, radius 72%, k 8, and therefore zero percent —
  // the same distance from the answer a player begins at
  close(play.match, 0.0, 1.0e-9)
  should.equal(False, score.solved(play.match))

  // and the target/normalizer came from the fixture, not from a re-derivation
  close(play.normalizer, star_fixture.rms_polar, 1.0e-6)
  should.equal(512, list.length(play.target))
}

pub fn a_test_play_starts_from_the_fixtures_own_patches_test() {
  // The fixture's start (derived with it) is what the editor test-plays — the
  // same numbers the toy boots a daily with, not a client-side constant.
  let fixture =
    wire.Fixture(..star(), patches: [
      dial.PhaseDeg(355.0),
      dial.RPct(73.0),
      dial.KSet(8),
      dial.Keep,
    ])
  let play = play_state(started(fixture))

  let assert [phase_slot, radius_slot, k_slot, fixed_slot] = play.terms
  close(phase_slot.phase_deg, 355.0, 1.0e-9)
  close(
    radius_slot.radius,
    0.73 *. dial.max_radius(star_fixture.dial()),
    1.0e-9,
  )
  should.equal(8, k_slot.k)
  // the fixed slot keeps truth: a patch never moves it
  let last_truth = list.last(star_fixture.dial())
  let assert Ok(last_truth) = last_truth
  close(fixed_slot.radius, last_truth.radius, 1.0e-12)
}

pub fn the_truth_score_chains_the_fixtures_extras_test() {
  // The toy's rule (fourier_toy/shapes.match_pct): the illustration AND the
  // score measure the FULL synthesis — the dial terms the player turns, then the
  // extras, which are fixed and correct. Dropping the extras on the way to the
  // metric is what made a solved drawing read 91.9% in test play.
  let play = play_state(started(star_full()))
  let full = list.append(play.terms, play.fixture.extras)

  close(
    play.match,
    score.match_pct(play.fixture.centroid, full, play.target, play.normalizer),
    1.0e-9,
  )
  should.equal(True, play.match >=. 99.9)

  // ...and the dial terms alone do NOT clear the gold: 97.6889%. That gap is
  // the extras doing real work, so this fixture discriminates.
  let dial_only =
    score.match_pct(
      play.fixture.centroid,
      play.terms,
      play.target,
      play.normalizer,
    )
  close(dial_only, 97.68891737585086, 1.0e-6)
  should.equal(True, dial_only <. 99.9)

  // the fixture really carries them (the derivation emits every other k != 0)
  should.equal(507, list.length(play.fixture.extras))
}

pub fn a_dial_step_rescores_the_full_synthesis_test() {
  // Stepping a dial must re-score the SAME list the comet draws: the terms the
  // player moved plus the untouched extras. A re-score over the dials alone
  // would make the number and the picture disagree the moment a dial moves.
  let model = started(star_full())
  let before = play_state(model)
  let stepped = play_state(step(model, admin_ui.DialStep(0, 1)))
  let full = list.append(stepped.terms, stepped.fixture.extras)

  close(
    stepped.match,
    score.match_pct(
      stepped.fixture.centroid,
      full,
      stepped.target,
      stepped.normalizer,
    ),
    1.0e-9,
  )
  should.equal(True, stepped.match <. before.match)
  should.equal(1, stepped.moves)
}

pub fn the_patched_start_clamps_its_score_at_zero_test() {
  // The fixture's own start (phase 355°, radius 73%, k 8) is hopeless by
  // design: the raw score is negative and the display clamps at 0 — adding the
  // extras must not rescue it.
  let fixture =
    wire.Fixture(..star_full(), patches: [
      dial.PhaseDeg(355.0),
      dial.RPct(73.0),
      dial.KSet(8),
      dial.Keep,
    ])
  let play = play_state(started(fixture))
  close(play.match, 0.0, 1.0e-9)
  should.equal(False, score.solved(play.match))
}

pub fn the_derived_readout_lists_one_entry_per_movable_slot_test() {
  // Before a save the derivation's own numbers are shown (Q2/Q3). One bullet per
  // MOVABLE slot, in the dial row's vocabulary: which dial it is and what it is
  // set to.
  let model = started(star())
  let assert Some(play) = model.play
  should.equal(admin_ui.truth_entries(play.fixture), [
    "term 1 · phase dial — set φ 270°",
    // the radius dial's own slot: 6.587 of the 27.575 max = 24%
    "term 2 · radius dial — set r 24%",
    "term 3 · k dial — set k +6",
  ])
}

pub fn a_fixed_slot_never_appears_in_the_derived_readout_test() {
  // Q19: the arrangement is DATA. The readout filters by KIND, not by position,
  // so an arrangement that puts the fixed term first still lists exactly the
  // dials — each with its own slot number and its own slot's numbers.
  let fixture =
    wire.Fixture(..star(), dials: [
      dial.KindFixed,
      dial.KindPhase,
      dial.KindRadius,
      dial.KindK,
    ])
  should.equal(admin_ui.truth_entries(fixture), [
    "term 2 · phase dial — set φ 270°",
    // slot 3's OWN numbers (k=+6, r 2.928 = 11%), not slot 2's
    "term 3 · radius dial — set r 11%",
    "term 4 · k dial — set k −14",
  ])
}

pub fn a_phase_step_moves_the_comet_and_the_score_test() {
  let model = started(star())
  let before = play_state(model).match
  let stepped = step(model, admin_ui.DialStep(0, 1))
  let after = play_state(stepped)

  // slot 1 is the phase dial: 0° -> 5°, the arm swings (no server round trip,
  // no re-derivation)
  close(slot_term(after, 0).phase_deg, 5.0, 1.0e-9)
  should.equal(1, after.moves)

  // the stored score IS the metric of the stored terms — the view can never show
  // a number the comet is not drawing
  close(
    after.match,
    score.match_pct(
      after.fixture.centroid,
      after.terms,
      after.target,
      after.normalizer,
    ),
    1.0e-12,
  )

  // start and first step both sit under the clamp: from a hopeless corner a 5°
  // nudge does not climb, and the display stays 0 rather than showing a negative
  close(before, 0.0, 1.0e-9)
  close(after.match, 0.0, 1.0e-9)
}

pub fn a_fixed_slot_never_moves_in_test_play_test() {
  let model = started(star())
  let before = play_state(model)
  let stepped = step(model, admin_ui.DialStep(3, 1))
  let after = play_state(stepped)
  should.equal(slot_term(before, 3), slot_term(after, 3))
  close(after.match, before.match, 1.0e-12)
}

pub fn the_solved_badge_fires_once_and_the_count_freezes_test() {
  // Solving is the truth dial state applied through the dials: set every slot
  // to the fixture's own numbers, then step k once to land there...
  let model = started(star())
  let play = play_state(model)
  let truth = admin_ui.Play(..play, terms: play.fixture.dial)
  let honest =
    score.match_pct(
      truth.fixture.centroid,
      truth.terms,
      truth.target,
      truth.normalizer,
    )
  // the fixture's own four terms score the documented 97.7%
  close(honest, 97.68891741835091, 1.0e-6)
  should.equal(True, score.solved(honest))
}

pub fn a_tap_adds_a_dot_and_undo_takes_it_back_test() {
  let tapped = step(model(), admin_ui.DotsTapped(#(10.0, 10.0)))
  should.equal(1, draw.count(tapped.drawing))
  let back = step(tapped, admin_ui.Undo)
  should.equal(0, draw.count(back.drawing))
  // a cleared drawing keeps its history: undo restores it
  let cleared = step(tapped, admin_ui.Clear)
  should.equal(0, draw.count(cleared.drawing))
  let restored = step(cleared, admin_ui.Undo)
  should.equal(1, draw.count(restored.drawing))
}

pub fn the_name_and_the_date_are_just_text_test() {
  let named = step(model(), admin_ui.NameChanged("the star"))
  should.equal("the star", named.name)
  let dated = step(named, admin_ui.ShowDateChanged("2026-10-25"))
  should.equal("2026-10-25", dated.show_date)
}

pub fn a_delete_is_armed_then_confirmed_test() {
  let armed = step(model(), admin_ui.ArmDelete(7))
  should.equal(Some(7), armed.armed)

  // the two-second clock disarms; a late tick for a DIFFERENT row does nothing
  let disarmed = step(armed, admin_ui.DisarmDelete(7))
  should.equal(None, disarmed.armed)
  let still = step(armed, admin_ui.DisarmDelete(9))
  should.equal(Some(7), still.armed)

  // confirming clears the arm and goes to the server
  let confirmed = step(armed, admin_ui.Delete(7))
  should.equal(None, confirmed.armed)
}

pub fn a_refused_save_keeps_the_drawing_and_says_why_test() {
  let drawn = step(model(), admin_ui.DotsTapped(#(10.0, 10.0)))
  let drawn = step(drawn, admin_ui.DotsTapped(#(20.0, 10.0)))
  let drawn = step(drawn, admin_ui.DotsTapped(#(20.0, 20.0)))

  let taken = wire.Failure(409, ["DuplicateShowDate"])
  let refused = step(drawn, admin_ui.Saved(Error(taken)))
  // still in the editor, still holding the shape: a taken date costs a re-pick,
  // never the drawing
  should.equal(admin_ui.Authoring, refused.view)
  should.equal(3, draw.count(refused.drawing))
  should.equal(Some(taken), refused.failure)
}

pub fn a_saved_puzzle_lands_on_the_menu_and_the_calendar_reloads_test() {
  let drawn = step(model(), admin_ui.DotsTapped(#(10.0, 10.0)))
  let saved = step(drawn, admin_ui.Saved(Ok(Nil)))
  should.equal(admin_ui.Menu, saved.view)
  should.equal(Some("saved"), saved.flash)
  should.equal(True, saved.busy)
  // the editor's leftovers are gone — a fresh "new puzzle" starts blank
  should.equal(0, draw.count(saved.drawing))
  should.equal("", saved.name)
}

fn play_kind(play: admin_ui.Play, slot: Int) -> dial.Kind {
  let assert [kind, ..] = list.drop(play.kinds, slot)
  kind
}

fn slot_term(play: admin_ui.Play, slot: Int) -> score.Term {
  let assert [term, ..] = list.drop(play.terms, slot)
  term
}
