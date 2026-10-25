//// The live preview panel's state machine (PLAN-daily-puzzles.md §10, the
//// 2026-10-25 grill): a debounced preview POST per drawing change, a monotone
//// generation that discards answers to superseded requests, a toggle between
//// the dial truth and the fixture's patched start, and a panel that keeps its
//// last fixture rather than blanking on a failed call.
////
//// The test seam for the debounce is the MESSAGE, not the clock: `update`
//// answers a draw change with an effect that arms a timer, and the timer's
//// only job is to dispatch `PreviewFire(generation)`. Effects are values in a
//// test, so firing a timer by hand is exactly what the runtime will do 300ms
//// later — the generation in the message is what makes an early or superseded
//// fire harmless.

import admin_ui
import admin_ui/dial
import admin_ui/draw
import admin_ui/wire
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/element
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

/// A fixture the way a saved puzzle serves one: every slot perturbed, so the
/// truth view and the player start are visibly different.
fn patched() -> wire.Fixture {
  wire.Fixture(..star(), patches: [
    dial.PhaseDeg(355.0),
    dial.RPct(73.0),
    dial.KSet(8),
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

/// A tap is a draw change: it schedules the next preview.
fn tap(model: admin_ui.Model, point: #(Float, Float)) -> admin_ui.Model {
  step(model, admin_ui.DotsTapped(point))
}

/// One preview round trip: the drawing's timer fires, the request is in flight,
/// the answer arrives.
fn previewed(model: admin_ui.Model, fixture: wire.Fixture) -> admin_ui.Model {
  let model = tap(model, #(10.0, 10.0))
  let generation = model.preview_scheduled.generation
  let model = step(model, admin_ui.PreviewFire(generation))
  step(model, admin_ui.PanelPreviewed(generation, Ok(fixture)))
}

pub fn a_answer_from_a_superseded_request_is_discarded_test() {
  let first = tap(model(), #(10.0, 10.0))
  let first = step(first, admin_ui.PreviewFire(1))
  should.equal(Some(1), first.preview_scheduled.inflight)
  should.equal(True, first.preview_pending)

  // a newer drawing starts a newer request while the first is still out
  let second = tap(first, #(20.0, 10.0))
  let second = step(second, admin_ui.PreviewFire(2))
  should.equal(Some(2), second.preview_scheduled.inflight)

  // the older answer lands late: it must not paint the panel, and it must not
  // touch the pending mark or the request the newer generation owns
  let late = step(second, admin_ui.PanelPreviewed(1, Ok(patched())))
  should.equal(None, late.preview)
  should.equal(True, late.preview_pending)
  should.equal(Some(2), late.preview_scheduled.inflight)

  // the answer the panel is waiting for is the one that lands
  let ok = step(late, admin_ui.PanelPreviewed(2, Ok(star())))
  should.equal(Some(star()), ok.preview)
  should.equal(False, ok.preview_pending)
  should.equal(None, ok.preview_scheduled.inflight)
}

pub fn a_burst_of_taps_leaves_exactly_one_request_test() {
  let model = tap(model(), #(10.0, 10.0))
  let model = tap(model, #(20.0, 10.0))
  let model = tap(model, #(20.0, 20.0))
  should.equal(3, model.preview_scheduled.generation)
  should.equal(Some(3), model.preview_scheduled.scheduled)
  should.equal(False, model.preview_pending)

  // the first two timers still fire, but their generations were superseded
  let model = step(model, admin_ui.PreviewFire(1))
  let model = step(model, admin_ui.PreviewFire(2))
  should.equal(None, model.preview_scheduled.inflight)
  should.equal(False, model.preview_pending)

  // only the last one asks the server
  let model = step(model, admin_ui.PreviewFire(3))
  should.equal(Some(3), model.preview_scheduled.inflight)
  should.equal(True, model.preview_pending)
  should.equal(None, model.preview_scheduled.scheduled)

  // a timer fires once; a repeated fire for the same generation is ignored
  let model = step(model, admin_ui.PreviewFire(3))
  should.equal(Some(3), model.preview_scheduled.inflight)
}

pub fn the_toggle_switches_between_truth_and_the_patched_start_test() {
  let fixture = patched()
  let model = previewed(model(), fixture)
  should.equal(Some(fixture), model.preview)
  // the panel opens on the dial truth
  should.equal(False, model.preview_start)
  should.equal(fixture.dial, admin_ui.panel_terms(fixture, model.preview_start))

  let started = step(model, admin_ui.StartView)
  should.equal(True, started.preview_start)
  let start = admin_ui.panel_terms(fixture, True)
  should.equal(
    dial.initial(fixture.dial, fixture.dials, fixture.patches),
    start,
  )
  let assert [phase, radius, k, fixed] = start
  close(phase.phase_deg, 355.0, 1.0e-9)
  close(radius.radius, 0.73 *. dial.max_radius(fixture.dial), 1.0e-9)
  should.equal(8, k.k)
  // a non-dial slot stays at truth in both views
  let assert [truth_fixed] = list.drop(fixture.dial, 3)
  close(truth_fixed.phase_deg, fixed.phase_deg, 1.0e-9)
  close(truth_fixed.radius, fixed.radius, 1.0e-9)
  should.equal(truth_fixed.k, fixed.k)

  let truth = step(started, admin_ui.TruthView)
  should.equal(False, truth.preview_start)
  should.equal(fixture.dial, admin_ui.panel_terms(fixture, False))
}

pub fn the_panels_dial_rows_are_read_only_and_skip_non_dials_test() {
  let html = element.to_string(admin_ui.preview_dial_rows(patched(), False))
  // three stepper rows would be three buttons in pairs; there are none
  should.equal(False, string.contains(html, "<button"))
  // the non-dial (fixed) slot is not a row at all
  should.equal(False, string.contains(html, "not a dial"))
  // `attribute.classes` serialises as `class="row read-only "` (a trailing
  // separator), so the needle stops at the last token rather than the quote
  should.equal(3, count(html, "class=\"row read-only"))
  // and the values are the truth view's (the star's dial truth)
  should.equal(True, string.contains(html, "270°"))
  should.equal(True, string.contains(html, "24%"))
  should.equal(True, string.contains(html, "k +6"))

  // the start view renders the fixture's own patched numbers instead
  let started_html =
    element.to_string(admin_ui.preview_dial_rows(patched(), True))
  should.equal(False, string.contains(started_html, "<button"))
  should.equal(True, string.contains(started_html, "355°"))
  should.equal(True, string.contains(started_html, "73%"))
  should.equal(True, string.contains(started_html, "k +8"))
}

pub fn a_failed_preview_flags_stale_and_keeps_the_last_fixture_test() {
  let first = tap(model(), #(10.0, 10.0))
  let first = step(first, admin_ui.PreviewFire(1))
  let first = step(first, admin_ui.PanelPreviewed(1, Ok(star())))
  should.equal(Some(star()), first.preview)
  should.equal(False, first.preview_stale)

  // the next drawing's preview is refused with a 400 and errors
  let failed = tap(first, #(20.0, 10.0))
  let failed = step(failed, admin_ui.PreviewFire(2))
  let failed =
    step(
      failed,
      admin_ui.PanelPreviewed(2, Error(wire.Failure(400, ["BadDrawing"]))),
    )
  // the panel keeps its last fixture and only the flag moves
  should.equal(Some(star()), failed.preview)
  should.equal(True, failed.preview_stale)
  should.equal(False, failed.preview_pending)
  should.equal(None, failed.preview_scheduled.inflight)

  // the next success updates the fixture and clears the flag
  let ok = tap(failed, #(20.0, 20.0))
  let ok = step(ok, admin_ui.PreviewFire(3))
  let ok = step(ok, admin_ui.PanelPreviewed(3, Ok(patched())))
  should.equal(Some(patched()), ok.preview)
  should.equal(False, ok.preview_stale)
}

pub fn opening_the_full_board_voids_the_panels_clock_test() {
  let model = tap(model(), #(10.0, 10.0))
  should.equal(Some(1), model.preview_scheduled.scheduled)

  // the full board's own preview is a separate flow: it must not leave the
  // panel's timer armed to fire a second POST behind it
  let model = step(model, admin_ui.Preview)
  should.equal(None, model.preview_scheduled.scheduled)
  let fired = step(model, admin_ui.PreviewFire(1))
  should.equal(None, fired.preview_scheduled.inflight)
  should.equal(False, fired.preview_pending)

  // nor may a panel answer that was already in flight enter the play view
  let play = step(model, admin_ui.Previewed(Ok(star())))
  should.equal(admin_ui.TestPlay, play.view)
  let late = step(play, admin_ui.PanelPreviewed(1, Ok(star())))
  should.equal(None, late.preview)
}

pub fn a_stale_fire_after_leaving_the_authoring_view_is_ignored_test() {
  let model = tap(model(), #(10.0, 10.0))
  let model = step(model, admin_ui.BackToMenu)
  let fired = step(model, admin_ui.PreviewFire(1))
  should.equal(None, fired.preview_scheduled.inflight)
  should.equal(False, fired.preview_pending)
}

/// How many times `needle` occurs in `haystack`.
fn count(haystack: String, needle: String) -> Int {
  string.split(haystack, needle) |> list.length |> fn(n) { n - 1 }
}
