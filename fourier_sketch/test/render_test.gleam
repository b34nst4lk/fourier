import gleam/list
import gleeunit/should
import render
import sketch
import terms

pub fn build_targets_slices_top_n_test() {
  let full = terms.compute(sketch.star(), 64, 1000)
  let targets = render.build_targets(full, 5)
  should.equal(list.length(targets), 5)
  // each target is (k, radius, phase) — same rows, same order as the slice
  should.equal(targets, list.take(list.map(full, tuple_term), 5))
}

fn tuple_term(t: terms.Term) -> #(Int, Float, Float) {
  #(t.k, t.radius, t.phase)
}

pub fn build_targets_over_count_test() {
  // asking for more than exists yields everything
  let full = terms.compute(sketch.heart(), 64, 1000)
  should.equal(list.length(render.build_targets(full, 9999)), 64)
}

pub fn build_targets_empty_test() {
  should.equal(render.build_targets([], 10), [])
}

pub fn clamp_circles_test() {
  should.equal(render.clamp_circles(10), 10)
  should.equal(render.clamp_circles(1), 4)
  should.equal(render.clamp_circles(300), 256)
}
