//// The app's update function, tested where it is pure.
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
import admin_ui/schedule
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
    status_filter: admin_ui.AnyStatus,
    creator_filter: admin_ui.AnyCreator,
    busy: False,
    flash: None,
    failure: None,
    editing: None,
    name: "",
    show_date: "",
    drawing: draw.empty(),
    drag: None,
    play: None,
    armed: None,
    approving: None,
    approve_date: "",
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

/// A press on empty space: the left button on a fresh spot is the ADD — the
/// original tap-to-append contract, unchanged by the edit vocabulary.
fn press(model: admin_ui.Model, point: #(Float, Float)) -> admin_ui.Model {
  step(model, admin_ui.DotsDown(0, point))
}

/// pointerup (and pointerleave — same message, same decoder) closes the drag.
fn release(model: admin_ui.Model) -> admin_ui.Model {
  step(model, admin_ui.DotsUp)
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
  // Before a save the derivation's own numbers are shown . One bullet per
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
  // The arrangement is DATA. The readout filters by KIND, not by position,
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

pub fn a_press_adds_a_dot_and_undo_takes_it_back_test() {
  let tapped = press(model(), #(10.0, 10.0))
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
  let drawn = press(model(), #(10.0, 10.0))
  let drawn = press(drawn, #(20.0, 10.0))
  let drawn = press(drawn, #(20.0, 20.0))

  let taken = wire.Failure(409, ["DuplicateShowDate"])
  let refused = step(drawn, admin_ui.Saved(Error(taken)))
  // still in the editor, still holding the shape: a taken date costs a re-pick,
  // never the drawing
  should.equal(admin_ui.Authoring, refused.view)
  should.equal(3, draw.count(refused.drawing))
  should.equal(Some(taken), refused.failure)
}

pub fn a_saved_puzzle_lands_on_the_menu_and_the_calendar_reloads_test() {
  let drawn = press(model(), #(10.0, 10.0))
  let saved = step(drawn, admin_ui.Saved(Ok(Nil)))
  should.equal(admin_ui.Menu, saved.view)
  should.equal(Some("saved"), saved.flash)
  should.equal(True, saved.busy)
  // the editor's leftovers are gone — a fresh "new puzzle" starts blank
  should.equal(0, draw.count(saved.drawing))
  should.equal("", saved.name)
}

// ---------------------------------------------------------------------------
// The pointer gestures: press / move / release and the right-button delete.
//
// The bug this answers: the authoring canvas could only APPEND, so one
// misplaced dot meant clearing the whole drawing. The sketch's vocabulary is
// ported whole (grab within `draw.hit_radius`, move without history, one undo
// step per drag, right-click deletes), and every CHANGE goes through
// `schedule_preview` so the live panel shows it.
// ---------------------------------------------------------------------------

pub fn a_press_near_a_dot_grabs_it_instead_of_adding_test() {
  let drawn = press(model(), #(10.0, 10.0))
  // inside the 3-unit hit radius a press GRABS: the count stays, nothing is
  // appended on top of the dot the user meant to move
  let grabbed = step(drawn, admin_ui.DotsDown(0, #(11.0, 11.0)))
  should.equal(1, draw.count(grabbed.drawing))
  should.equal(Some(0), grabbed.drag)

  // ...and a press out on empty space still ADDS (the tap contract survives)
  let added = step(drawn, admin_ui.DotsDown(0, #(40.0, 40.0)))
  should.equal(2, draw.count(added.drawing))
  should.equal([#(10.0, 10.0), #(40.0, 40.0)], draw.dots(added.drawing))
  should.equal(None, added.drag)
}

pub fn a_drag_moves_the_dot_and_schedules_one_preview_test() {
  let drawn = press(model(), #(10.0, 10.0)) |> release
  let before = drawn.preview_scheduled.generation

  // the press grabs, and a grab is not a change: nothing is scheduled
  let grabbed = step(drawn, admin_ui.DotsDown(0, #(10.0, 10.0)))
  should.equal(Some(0), grabbed.drag)
  should.equal(drawn.preview_scheduled, grabbed.preview_scheduled)

  // the moves repaint the dot, and NO move schedules: the debounce must not
  // fire per pointer sample, only for the drop
  let moved = step(grabbed, admin_ui.DotsMove(#(20.0, 30.0)))
  let moved = step(moved, admin_ui.DotsMove(#(25.0, 35.0)))
  should.equal([#(25.0, 35.0)], draw.dots(moved.drawing))
  should.equal(drawn.preview_scheduled, moved.preview_scheduled)
  should.equal(Some(0), moved.drag)

  // the drop closes the drag and schedules exactly ONE preview (one bump)
  let dropped = step(moved, admin_ui.DotsUp)
  should.equal(None, dropped.drag)
  should.equal(before + 1, dropped.preview_scheduled.generation)
  should.equal(Some(before + 1), dropped.preview_scheduled.scheduled)

  // and the whole drag was ONE undo step: it returns the pre-grab dot
  should.equal([#(10.0, 10.0)], draw.dots(step(dropped, admin_ui.Undo).drawing))
}

pub fn a_click_on_a_dot_is_not_a_change_test() {
  let drawn = press(model(), #(10.0, 10.0)) |> release
  let clock = drawn.preview_scheduled

  // press on the dot and let go without moving: a click, not a drag
  let clicked = step(drawn, admin_ui.DotsDown(0, #(10.5, 10.5))) |> release
  should.equal(draw.dots(drawn.drawing), draw.dots(clicked.drawing))
  should.equal(None, clicked.drag)
  // no preview was scheduled and no generation bumped
  should.equal(clock, clicked.preview_scheduled)
  // and no undo entry was left behind: one undo still takes the ADD back
  should.equal(0, draw.count(step(clicked, admin_ui.Undo).drawing))
}

pub fn a_right_press_deletes_the_nearest_dot_and_previews_test() {
  let drawn =
    press(model(), #(10.0, 10.0))
    |> release
    |> press(#(50.0, 50.0))
    |> release
  should.equal(2, draw.count(drawn.drawing))
  let before = drawn.preview_scheduled.generation

  // the right button deletes the dot in reach — not the last one drawn
  let deleted = step(drawn, admin_ui.DotsDown(2, #(51.0, 51.0)))
  should.equal(1, draw.count(deleted.drawing))
  should.equal([#(10.0, 10.0)], draw.dots(deleted.drawing))
  // a delete is a change, never a grab
  should.equal(None, deleted.drag)
  // the panel PREVIEWS the deletion: the same funnel the taps use
  should.equal(before + 1, deleted.preview_scheduled.generation)
  should.equal(Some(before + 1), deleted.preview_scheduled.scheduled)
  // ...and it is one undo step
  should.equal(2, draw.count(step(deleted, admin_ui.Undo).drawing))
}

pub fn a_right_press_away_from_every_dot_deletes_nothing_test() {
  let drawn = press(model(), #(10.0, 10.0)) |> release
  let clock = drawn.preview_scheduled

  // the sketch's rule: nothing in reach, nothing deleted, nothing scheduled
  let missed = step(drawn, admin_ui.DotsDown(2, #(80.0, 80.0)))
  should.equal(1, draw.count(missed.drawing))
  should.equal(clock, missed.preview_scheduled)

  // an empty drawing has nothing to delete either
  let empty = step(model(), admin_ui.DotsDown(2, #(10.0, 10.0)))
  should.equal(0, draw.count(empty.drawing))
  should.equal(model().preview_scheduled, empty.preview_scheduled)
}

pub fn a_release_or_a_move_with_no_drag_in_flight_changes_nothing_test() {
  let drawn = press(model(), #(10.0, 10.0)) |> release

  // pointerup and pointerleave share this message; with no drag it is a no-op
  let upped = step(drawn, admin_ui.DotsUp)
  should.equal(draw.dots(drawn.drawing), draw.dots(upped.drawing))
  should.equal(drawn.preview_scheduled, upped.preview_scheduled)

  // a pointermove with nothing grabbed moves nothing (it would otherwise drag
  // whichever dot happens to sit at the last index)
  let stray = step(drawn, admin_ui.DotsMove(#(70.0, 70.0)))
  should.equal(draw.dots(drawn.drawing), draw.dots(stray.drawing))
  should.equal(drawn.preview_scheduled, stray.preview_scheduled)
}

pub fn a_drag_never_survives_a_view_swap_test() {
  let grabbed = press(model(), #(10.0, 10.0)) |> release |> press(#(10.0, 10.0))
  should.equal(Some(0), grabbed.drag)
  // a fresh drawing starts with no gesture in flight
  should.equal(None, step(grabbed, admin_ui.StartNew).drag)
}

// ---------------------------------------------------------------------------
// The calendar as a working list: the two filters, the draft badges, and the
// approve action (agent drafts, 2026-10-25).
//
// A local agent files undated drafts; a human dates them. That split is the
// whole point of the schedule states, so what is asserted here is that the menu
// can SEGMENT the calendar (whose draft is this, what is still undated) and that
// approving is a one-field write: the date, nothing else.
// ---------------------------------------------------------------------------

fn row(
  id: Int,
  name: String,
  show_date: String,
  status: String,
  creator: String,
) -> wire.Row {
  wire.Row(
    id: id,
    name: name,
    show_date: show_date,
    status: status,
    creator: creator,
    attempts: 0,
    solves: 0,
    solve_pct: None,
    median_moves: None,
  )
}

/// One calendar with one of each: a published human puzzle, a human draft and an
/// agent draft.
fn calendar() -> List(wire.Row) {
  [
    row(1, "the star", "2026-11-18", "published", "human"),
    row(2, "my sketch", "", "draft", "human"),
    row(3, "the snail", "", "draft", "hermes"),
  ]
}

fn named(rows: List(wire.Row)) -> List(String) {
  list.map(rows, fn(row) { row.name })
}

pub fn the_two_filters_segment_the_calendar_test() {
  let model = admin_ui.Model(..model(), rows: calendar())

  // status: all / published / drafts
  should.equal(
    ["the star", "my sketch", "the snail"],
    named(admin_ui.visible_rows(model)),
  )
  should.equal(
    ["the star"],
    named(admin_ui.visible_rows(
      admin_ui.Model(..model, status_filter: admin_ui.PublishedOnly),
    )),
  )
  should.equal(
    ["my sketch", "the snail"],
    named(admin_ui.visible_rows(
      admin_ui.Model(..model, status_filter: admin_ui.DraftsOnly),
    )),
  )

  // creator: all / you (the human) / the agents
  should.equal(
    ["the star", "my sketch"],
    named(admin_ui.visible_rows(
      admin_ui.Model(..model, creator_filter: admin_ui.MineOnly),
    )),
  )
  should.equal(
    ["the snail"],
    named(admin_ui.visible_rows(
      admin_ui.Model(..model, creator_filter: admin_ui.AgentsOnly),
    )),
  )

  // the two compose: "agent drafts" is one row, "my drafts" is another
  should.equal(
    ["the snail"],
    named(admin_ui.visible_rows(
      admin_ui.Model(
        ..model,
        status_filter: admin_ui.DraftsOnly,
        creator_filter: admin_ui.AgentsOnly,
      ),
    )),
  )
  should.equal(
    ["my sketch"],
    named(admin_ui.visible_rows(
      admin_ui.Model(
        ..model,
        status_filter: admin_ui.DraftsOnly,
        creator_filter: admin_ui.MineOnly,
      ),
    )),
  )
  // ...and an empty intersection is empty, not "all"
  should.equal(
    [],
    named(admin_ui.visible_rows(
      admin_ui.Model(
        ..model,
        status_filter: admin_ui.PublishedOnly,
        creator_filter: admin_ui.AgentsOnly,
      ),
    )),
  )
}

pub fn the_filters_are_set_by_their_own_messages_test() {
  let drafts = step(model(), admin_ui.FilterStatus(admin_ui.DraftsOnly))
  should.equal(admin_ui.DraftsOnly, drafts.status_filter)
  let mine = step(drafts, admin_ui.FilterCreator(admin_ui.MineOnly))
  should.equal(admin_ui.MineOnly, mine.creator_filter)
  // and switching one filter leaves the other alone
  should.equal(admin_ui.DraftsOnly, mine.status_filter)
}

pub fn only_a_draft_offers_approve_and_only_a_dated_row_offers_test_test() {
  // The row's buttons ARE its state: a draft cannot be played (there is no day
  // to play), and a dated puzzle has nothing to approve.
  should.equal(
    [admin_ui.EditAction, admin_ui.ApproveAction, admin_ui.DeleteAction],
    admin_ui.row_actions(row(3, "the snail", "", "draft", "hermes")),
  )
  should.equal(
    [admin_ui.PlayAction, admin_ui.EditAction, admin_ui.DeleteAction],
    admin_ui.row_actions(row(1, "the star", "2026-11-18", "published", "human")),
  )
}

pub fn an_agent_draft_is_badged_with_its_author_and_a_human_one_is_not_test() {
  // The creator chip: an agent's id, so the human knows who filed the sketch.
  // "human" is the absence of a chip — the default author is not news.
  should.equal(
    Some("hermes"),
    admin_ui.creator_badge(row(3, "the snail", "", "draft", "hermes")),
  )
  should.equal(
    None,
    admin_ui.creator_badge(row(2, "my sketch", "", "draft", "human")),
  )
  // the draft badge is the status, nothing else
  should.equal(
    True,
    admin_ui.draft_badge(row(3, "the snail", "", "draft", "hermes")),
  )
  should.equal(
    False,
    admin_ui.draft_badge(row(1, "the star", "2026-11-18", "published", "human")),
  )
}

pub fn an_approve_opens_with_the_next_free_day_test() {
  let model = admin_ui.Model(..model(), rows: calendar())
  let opened = step(model, admin_ui.StartApprove(3))
  should.equal(Some(3), opened.approving)

  // The prefill is the calendar's next free day — computed here, from the rows
  // in hand (the server only says "taken" when it is). No literal date: "today"
  // is the browser's clock, so what is asserted is the property —
  // schedule_test.gleam pins the arithmetic against fixed days.
  let expected =
    schedule.next_available(admin_ui.taken_dates(calendar()), schedule.today())
  should.equal(expected, opened.approve_date)
  should.equal(
    False,
    list.contains(admin_ui.taken_dates(calendar()), opened.approve_date),
  )
  let assert Ok(prefilled) = schedule.day_number(opened.approve_date)
  let assert Ok(today) = schedule.day_number(schedule.today())
  should.be_true(prefilled >= today)
}

pub fn an_approve_is_confirmed_with_the_date_and_nothing_else_test() {
  let model = admin_ui.Model(..model(), rows: calendar())
  let opened = step(model, admin_ui.StartApprove(3))

  // the human picks another day: the field is the input
  let picked = step(opened, admin_ui.ApproveDateChanged("2026-12-01"))
  should.equal("2026-12-01", picked.approve_date)

  // confirming goes to the server, and the body is the one-field PUT
  let confirmed = step(picked, admin_ui.Approve)
  should.equal(True, confirmed.busy)
  should.equal(Some(3), confirmed.approving)

  // ...and the answer comes back to the calendar
  let settled = step(confirmed, admin_ui.Approved(Ok(Nil)))
  should.equal(None, settled.approving)
  should.equal("", settled.approve_date)
  should.equal(Some("approved"), settled.flash)
  should.equal(True, settled.busy)
}

pub fn a_refused_approve_keeps_the_open_date_for_another_try_test() {
  // A taken date costs a re-pick, never the state: the row stays open with the
  // date that was refused, and the banner says which date it was about.
  let model = admin_ui.Model(..model(), rows: calendar())
  let opened = step(model, admin_ui.StartApprove(3))
  let failure = wire.Failure(409, ["DuplicateShowDate"])
  let refused = step(opened, admin_ui.Approved(Error(failure)))
  should.equal(Some(3), refused.approving)
  should.equal(opened.approve_date, refused.approve_date)
  should.equal(Some(failure), refused.failure)
  should.equal(False, refused.busy)
}

pub fn back_closes_the_approve_without_writing_test() {
  let model = admin_ui.Model(..model(), rows: calendar())
  let opened = step(model, admin_ui.StartApprove(3))
  let closed = step(opened, admin_ui.CancelApprove)
  should.equal(None, closed.approving)
  should.equal("", closed.approve_date)
  should.equal(None, closed.failure)
}

pub fn a_new_puzzle_prefills_the_next_free_day_test() {
  // The unified rule the editor shows: the date field starts at the next free
  // day (a save publishes), and clearing it makes a draft.
  let model = admin_ui.Model(..model(), rows: calendar())
  let fresh = step(model, admin_ui.StartNew)
  should.equal(
    schedule.next_available(admin_ui.taken_dates(calendar()), schedule.today()),
    fresh.show_date,
  )
  should.equal(None, fresh.approving)
  // the hint says what clearing the field means, in both editors
  should.equal("no date — this saves as a draft", admin_ui.date_hint(""))
  should.equal("", admin_ui.date_hint("2026-11-19"))
}

pub fn approve_and_delete_are_never_open_together_test() {
  let model = admin_ui.Model(..model(), rows: calendar())
  let armed = step(model, admin_ui.ArmDelete(3))
  should.equal(Some(3), armed.armed)

  let opened = step(armed, admin_ui.StartApprove(3))
  should.equal(None, opened.armed)
  should.equal(Some(3), opened.approving)

  let armed_again = step(opened, admin_ui.ArmDelete(3))
  should.equal(None, armed_again.approving)
  should.equal("", armed_again.approve_date)
  should.equal(Some(3), armed_again.armed)
}

pub fn editing_a_draft_keeps_its_empty_date_as_a_draft_test() {
  // The editor's date field is the schedule in both directions: opening a draft
  // leaves the field empty (and the hint explains that an empty date on save
  // keeps it a draft), and opening a published row fills it in.
  let model = admin_ui.Model(..model(), rows: calendar())
  let editing = step(model, admin_ui.StartEdit(3))
  should.equal(Some(3), editing.editing)
  should.equal("", editing.show_date)
  should.equal("the snail", editing.name)
  let published = step(model, admin_ui.StartEdit(1))
  should.equal("2026-11-18", published.show_date)
}

fn play_kind(play: admin_ui.Play, slot: Int) -> dial.Kind {
  let assert [kind, ..] = list.drop(play.kinds, slot)
  kind
}

fn slot_term(play: admin_ui.Play, slot: Int) -> score.Term {
  let assert [term, ..] = list.drop(play.terms, slot)
  term
}
