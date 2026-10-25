//// The drawing model's tests (PLAN-daily-puzzles.md §3 authoring).
////
//// The interesting cases are the ones the pointer layer will actually produce:
//// a tap that fires twice, undo at the bottom of the history, clear after a
//// half-finished shape, and the three-dot floor the backend enforces.

import admin_ui/draw
import gleeunit/should

fn three() -> draw.Drawing {
  draw.empty()
  |> draw.add(#(10.0, 10.0))
  |> draw.add(#(20.0, 10.0))
  |> draw.add(#(20.0, 20.0))
}

pub fn a_tap_appends_one_dot_test() {
  let drawing = draw.empty() |> draw.add(#(42.0, 7.0))
  should.equal(1, draw.count(drawing))
  should.equal([#(42.0, 7.0)], draw.dots(drawing))
}

pub fn a_second_tap_on_the_same_spot_is_ignored_test() {
  // pointerdown + pointerup both report a point; without this gate a single
  // tap would place two dots.
  let drawing = draw.empty() |> draw.add(#(10.0, 10.0))
  let twice = draw.add(drawing, #(10.2, 10.1))
  should.equal(1, draw.count(twice))
  should.equal(draw.dots(drawing), draw.dots(twice))

  // ...and the ignored tap leaves nothing behind for undo to find
  should.equal(draw.empty(), draw.undo(twice) |> draw.undo())
}

pub fn a_tap_far_enough_away_is_kept_test() {
  let drawing =
    draw.empty() |> draw.add(#(10.0, 10.0)) |> draw.add(#(10.0, 11.0))
  should.equal(2, draw.count(drawing))
}

pub fn undo_pops_the_last_dot_only_test() {
  let drawing = draw.undo(three())
  should.equal(2, draw.count(drawing))
  should.equal([#(10.0, 10.0), #(20.0, 10.0)], draw.dots(drawing))

  // undo past the beginning is a no-op, not a crash and not a phantom dot
  let empty = draw.empty() |> draw.undo() |> draw.undo()
  should.equal([], draw.dots(empty))
}

pub fn clear_empties_and_undo_brings_the_shape_back_test() {
  // Clear is destructive-looking, so it goes through the same history: a
  // mis-click on clear costs nothing.
  let cleared = draw.clear(three())
  should.equal([], draw.dots(cleared))
  should.equal(3, draw.count(draw.undo(cleared)))

  // clearing an already-empty drawing adds no history
  should.equal(draw.empty(), draw.clear(draw.empty()) |> draw.undo())
}

pub fn three_dots_is_the_smallest_submittable_shape_test() {
  should.equal(False, draw.can_submit(draw.empty()))
  should.equal(False, draw.can_submit(draw.empty() |> draw.add(#(1.0, 1.0))))
  should.equal(
    False,
    draw.can_submit(
      draw.empty() |> draw.add(#(1.0, 1.0)) |> draw.add(#(2.0, 1.0)),
    ),
  )
  should.equal(True, draw.can_submit(three()))
}

pub fn the_path_is_a_closed_polygon_test() {
  should.equal("", draw.closed_path(draw.empty()))
  should.equal(
    "M 10.0 10.0 L 20.0 10.0 L 20.0 20.0 Z",
    draw.closed_path(three()),
  )
}

pub fn the_wire_shape_is_a_list_of_pairs_test() {
  should.equal(
    [[10.0, 10.0], [20.0, 10.0], [20.0, 20.0]],
    draw.wire_dots(three()),
  )
}
