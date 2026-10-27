//// The drawing model's tests.
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

// ---------------------------------------------------------------------------
// The family's edit vocabulary (fourier_sketch's sketch.gleam, ported): a
// hit-test, a delete, and the two-phase drag. The bug: the authoring canvas
// could only APPEND, so a misplaced dot meant clearing the whole drawing.
// ---------------------------------------------------------------------------

pub fn nearest_picks_the_closest_dot_within_the_hit_radius_test() {
  // squared distances throughout, ties to the EARLIEST index, `max_dist`
  // inclusive — fourier_sketch's nearest_dot, verbatim rules
  let points = [#(10.0, 10.0), #(50.0, 50.0), #(52.0, 50.0), #(80.0, 80.0)]

  should.equal(Ok(2), draw.nearest(points, #(52.0, 51.0), 3.0))
  // equidistant from dots 1 and 2: the earlier one wins, so a grab of the same
  // spot is always the same dot
  should.equal(Ok(1), draw.nearest(points, #(51.0, 50.5), 3.0))
  // exactly on the radius is in reach…
  should.equal(Ok(1), draw.nearest(points, #(50.0, 53.0), 3.0))
  // …a hair outside it is not
  should.equal(Error(Nil), draw.nearest(points, #(50.0, 53.1), 3.0))
  // nothing anywhere near: this is the ADD path, not a grab
  should.equal(Error(Nil), draw.nearest(points, #(20.0, 20.0), 3.0))
  // an empty drawing has nothing to hit
  should.equal(Error(Nil), draw.nearest([], #(10.0, 10.0), 3.0))
}

pub fn the_hit_radius_is_the_familys_three_units_test() {
  // the admin's dots live in the same 0..100 square as the sketch's, so the
  // grab radius must be the same number — not a pixel count
  should.equal(3.0, draw.hit_radius)
}

pub fn remove_drops_one_dot_and_keeps_the_drawing_order_test() {
  // drawing order is 10,10 · 20,10 · 20,20 · 10,20; remove the second
  let cut = three() |> draw.add(#(10.0, 20.0)) |> draw.remove(1)
  should.equal(3, draw.count(cut))
  should.equal([#(10.0, 10.0), #(20.0, 20.0), #(10.0, 20.0)], draw.dots(cut))
  // the outline is the surviving order — a delete never reshuffles the path
  should.equal("M 10.0 10.0 L 20.0 20.0 L 10.0 20.0 Z", draw.closed_path(cut))
}

pub fn a_removed_dot_comes_back_with_one_undo_test() {
  let cut = draw.remove(three(), 2)
  should.equal([#(10.0, 10.0), #(20.0, 10.0)], draw.dots(cut))
  should.equal(draw.dots(three()), draw.dots(draw.undo(cut)))
}

pub fn removing_nothing_is_a_no_op_test() {
  // an index off either end deletes nothing and remembers nothing
  should.equal(draw.dots(three()), draw.dots(draw.remove(three(), 3)))
  should.equal(draw.dots(three()), draw.dots(draw.remove(three(), -1)))
  should.equal(draw.empty(), draw.remove(draw.empty(), 0) |> draw.undo())
}

pub fn a_drop_after_a_click_restores_the_grab_test() {
  // grabbing changes no dot…
  let grabbed = draw.grab(three(), 1)
  should.equal(draw.dots(three()), draw.dots(grabbed))

  // …and a press that never moved (or a drag back to the exact start) is a
  // CLICK: the grab's own snapshot is popped, so no undo entry is left behind
  let #(after, moved) = draw.drop(grabbed)
  should.equal(False, moved)
  should.equal(three(), after)

  let #(returned, moved_back) =
    grabbed
    |> draw.set(1, #(33.0, 44.0))
    |> draw.set(1, #(20.0, 10.0))
    |> draw.drop
  should.equal(False, moved_back)
  should.equal(three(), returned)
}

pub fn a_drop_after_a_move_keeps_exactly_one_undo_step_test() {
  // a long drag is ONE undo step however many moves it makes
  let moved =
    draw.grab(three(), 1)
    |> draw.set(1, #(30.0, 40.0))
    |> draw.set(1, #(31.0, 41.0))
  should.equal([#(10.0, 10.0), #(31.0, 41.0), #(20.0, 20.0)], draw.dots(moved))

  let #(after, did_move) = draw.drop(moved)
  should.equal(True, did_move)
  should.equal(draw.dots(moved), draw.dots(after))

  // one undo returns the pre-grab drawing…
  let back = draw.undo(after)
  should.equal(draw.dots(three()), draw.dots(back))
  // …and the step before the drag is still the second dot: the moves pushed
  // no history of their own
  should.equal(2, draw.count(draw.undo(back)))
}

pub fn a_move_off_the_ends_is_a_no_op_test() {
  let grabbed = draw.grab(three(), 1)
  should.equal(draw.dots(grabbed), draw.dots(draw.set(grabbed, 3, #(1.0, 1.0))))
  should.equal(
    draw.dots(grabbed),
    draw.dots(draw.set(grabbed, -1, #(1.0, 1.0))),
  )
  // a grab of a dot that is not there changes nothing at all
  should.equal(three(), draw.grab(three(), 9))
}
