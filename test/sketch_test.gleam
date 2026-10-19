import gleam/list
import gleeunit/should
import sketch

pub fn new_is_empty_test() {
  let s = sketch.new()
  should.equal(sketch.dot_count(s), 0)
  should.be_false(sketch.can_undo(s))
  should.be_false(sketch.can_redo(s))
  should.be_false(sketch.gate_ready(s))
}

pub fn add_dot_appends_in_order_test() {
  let s =
    sketch.new()
    |> sketch.add_dot(#(10.0, 0.0))
    |> sketch.add_dot(#(0.0, 10.0))
    |> sketch.add_dot(#(20.0, 20.0))
  should.equal(sketch.dots(s), [#(10.0, 0.0), #(0.0, 10.0), #(20.0, 20.0)])
}

pub fn gate_needs_three_dots_test() {
  let s =
    sketch.new()
    |> sketch.add_dot(#(1.0, 1.0))
    |> sketch.add_dot(#(2.0, 2.0))
  should.be_false(sketch.gate_ready(s))
  let s = sketch.add_dot(s, #(3.0, 3.0))
  should.be_true(sketch.gate_ready(s))
}

pub fn remove_dot_keeps_order_test() {
  let s =
    sketch.load_dots(sketch.new(), [
      #(0.0, 0.0),
      #(1.0, 0.0),
      #(2.0, 0.0),
      #(3.0, 0.0),
    ])
    |> sketch.remove_dot(1)
  should.equal(sketch.dots(s), [#(0.0, 0.0), #(2.0, 0.0), #(3.0, 0.0)])
}

pub fn remove_dot_undo_restores_test() {
  let before = [#(0.0, 0.0), #(1.0, 0.0), #(2.0, 0.0)]
  let s =
    sketch.load_dots(sketch.new(), before)
    |> sketch.remove_dot(2)
  should.equal(sketch.dots(sketch.undo(s)), before)
}

pub fn remove_out_of_range_is_noop_test() {
  let s = sketch.load_dots(sketch.new(), [#(0.0, 0.0)])
  let s = sketch.remove_dot(s, 5)
  should.equal(sketch.dots(s), [#(0.0, 0.0)])
  should.be_false(sketch.can_undo(s))
}

pub fn set_dot_moves_only_target_test() {
  let s =
    sketch.load_dots(sketch.new(), [#(0.0, 0.0), #(1.0, 1.0), #(2.0, 2.0)])
    |> sketch.grab_dot(1)
    |> sketch.set_dot(1, #(9.0, 9.0))
  should.equal(sketch.dots(s), [#(0.0, 0.0), #(9.0, 9.0), #(2.0, 2.0)])
}

pub fn set_out_of_range_noop_test() {
  let s0 = sketch.load_dots(sketch.new(), [#(0.0, 0.0)])
  let s = sketch.set_dot(s0, 7, #(5.0, 5.0))
  should.equal(sketch.dots(s), [#(0.0, 0.0)])
  should.be_false(sketch.can_undo(s))
}

pub fn grab_set_undo_redo_test() {
  let base = [#(0.0, 0.0), #(1.0, 1.0)]
  let s =
    sketch.load_dots(sketch.new(), base)
    |> sketch.grab_dot(0)
    |> sketch.set_dot(0, #(5.0, 5.0))
  let s = sketch.undo(s)
  should.equal(sketch.dots(s), base)
  let s = sketch.redo(s)
  should.equal(sketch.dots(s), [#(5.0, 5.0), #(1.0, 1.0)])
}

pub fn drag_is_one_history_step_test() {
  // grab once, many set_dots: exactly one undo step
  let s =
    sketch.load_dots(sketch.new(), [#(0.0, 0.0)])
    |> sketch.grab_dot(0)
    |> sketch.set_dot(0, #(1.0, 0.0))
    |> sketch.set_dot(0, #(2.0, 0.0))
    |> sketch.set_dot(0, #(3.0, 0.0))
  let s = sketch.undo(s)
  should.equal(sketch.dots(s), [#(0.0, 0.0)])
  should.be_false(sketch.can_undo(s))
}

pub fn cancel_grab_after_no_move_test() {
  let s0 = sketch.load_dots(sketch.new(), [#(0.0, 0.0)])
  let s = sketch.cancel_grab(sketch.grab_dot(s0, 0))
  should.equal(sketch.dots(s), [#(0.0, 0.0)])
  should.be_false(sketch.can_undo(s))
  should.be_false(sketch.can_redo(s))
}

pub fn cancel_grab_keeps_real_move_test() {
  let s0 = sketch.load_dots(sketch.new(), [#(0.0, 0.0)])
  let s =
    sketch.grab_dot(s0, 0)
    |> sketch.set_dot(0, #(7.0, 7.0))
    |> sketch.cancel_grab
  should.equal(sketch.dots(s), [#(7.0, 7.0)])
  should.be_true(sketch.can_undo(s))
  should.equal(sketch.dots(sketch.undo(s)), [#(0.0, 0.0)])
}

pub fn cancel_grab_restores_redo_test() {
  // history: add, undo -> redo pending; grab & cancel must not lose it
  let s =
    sketch.load_dots(sketch.new(), [#(0.0, 0.0)])
    |> sketch.add_dot(#(1.0, 1.0))
    |> sketch.undo
  should.be_true(sketch.can_redo(s))
  let s = sketch.cancel_grab(sketch.grab_dot(s, 0))
  should.be_true(sketch.can_redo(s))
  should.equal(sketch.dots(sketch.redo(s)), [#(0.0, 0.0), #(1.0, 1.0)])
}

pub fn undo_redo_chain_test() {
  let s =
    sketch.new()
    |> sketch.add_dot(#(1.0, 0.0))
    |> sketch.add_dot(#(2.0, 0.0))
    |> sketch.add_dot(#(3.0, 0.0))
  let s = sketch.undo(s) |> sketch.undo
  should.equal(sketch.dot_count(s), 1)
  let s = sketch.redo(s) |> sketch.redo
  should.equal(sketch.dot_count(s), 3)
  // a new action after undo clears the redo stack
  let s = sketch.undo(s) |> sketch.add_dot(#(9.0, 9.0))
  should.be_false(sketch.can_redo(s))
  should.equal(sketch.dot_count(s), 3)
}

pub fn undo_on_empty_noop_test() {
  let s = sketch.undo(sketch.new())
  should.equal(sketch.dots(s), [])
  should.be_false(sketch.can_redo(s))
}

pub fn redo_on_empty_noop_test() {
  let s = sketch.redo(sketch.new())
  should.equal(sketch.dots(s), [])
  should.be_false(sketch.can_undo(s))
}

pub fn clear_is_undoable_test() {
  let s =
    sketch.load_dots(sketch.new(), [
      #(0.0, 0.0),
      #(1.0, 1.0),
      #(2.0, 2.0),
    ])
    |> sketch.clear
  should.equal(sketch.dot_count(s), 0)
  should.equal(sketch.dot_count(sketch.undo(s)), 3)
}

pub fn clear_empty_is_noop_test() {
  should.be_false(sketch.can_undo(sketch.clear(sketch.new())))
}

pub fn preset_load_is_undoable_test() {
  let s =
    sketch.load_dots(sketch.new(), sketch.star())
    |> sketch.undo
  should.equal(sketch.dot_count(s), 0)
}

pub fn start_has_no_history_test() {
  let s = sketch.start([#(1.0, 1.0), #(2.0, 2.0), #(3.0, 3.0)])
  should.equal(sketch.dot_count(s), 3)
  should.be_false(sketch.can_undo(s))
  should.be_true(sketch.gate_ready(s))
}

pub fn presets_pass_gate_test() {
  list.each([sketch.star(), sketch.heart(), sketch.wobble()], fn(dots) {
    should.be_true(sketch.gate_ready(sketch.load_dots(sketch.new(), dots)))
  })
}

pub fn presets_in_bounds_test() {
  list.each([sketch.star(), sketch.heart(), sketch.wobble()], fn(dots) {
    should.be_true(
      list.all(dots, fn(d) {
        { d.0 >=. 0.0 } && { d.0 <=. 100.0 } && { d.1 >=. 0.0 } && { d.1 <=. 100.0 }
      }),
    )
  })
}

pub fn star_has_ten_points_test() {
  should.equal(list.length(sketch.star()), 10)
}

pub fn presets_are_distinct_test() {
  should.not_equal(sketch.star(), sketch.heart())
  should.not_equal(sketch.star(), sketch.wobble())
  should.not_equal(sketch.heart(), sketch.wobble())
}