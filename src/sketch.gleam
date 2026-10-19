//// Panel-1 state model: dots on a closed path + undo/redo history.
////
//// History contract (encoded in test/sketch_test.gleam):
//// - History-pushing actions: add_dot, remove_dot, clear, load_dots.
//// - Drag is two-phase: grab_dot(index) once, then set_dot freely — a long
////   drag is exactly ONE undo step. cancel_grab reverts a grab that never
////   moved (click without drag) and restores the redo stack it displaced.
//// - Any new action clears the redo stack.
//// - start/ boot restore carries no history.
//// - Coordinates are plain #(x, y) floats; the app layer owns the units
////   (sketch space is 0..100, y-down — see docs/PLAN.md §4).
//// - Out-of-range indices are silent no-ops that push no history.

import gleam/int
import gleam/list

pub type Dot =
  #(Float, Float)

/// What an undo entry remembers: the dots to restore, plus the redo stack as
/// it was before the action (so cancel_grab can put it back untouched).
/// Public for the app layer's convenience, but only sketch.gleam should
/// construct one — the semantics below are module-internal.
pub type Snapshot {
  Snapshot(dots: List(Dot), redo_stack: List(List(Dot)))
}

pub type Sketch {
  Sketch(
    dots: List(Dot),
    undo_stack: List(Snapshot),
    redo_stack: List(List(Dot)),
  )
}

pub fn new() -> Sketch {
  Sketch([], [], [])
}

/// Boot-time restore (localStorage load): dots with no history at all.
pub fn start(dots: List(Dot)) -> Sketch {
  Sketch(dots, [], [])
}

pub fn dots(s: Sketch) -> List(Dot) {
  s.dots
}

pub fn dot_count(s: Sketch) -> Int {
  list.length(s.dots)
}

/// The DFT panels stay idle until a polygon is meaningful.
pub fn gate_ready(s: Sketch) -> Bool {
  dot_count(s) >= 3
}

pub fn can_undo(s: Sketch) -> Bool {
  case s.undo_stack {
    [] -> False
    _ -> True
  }
}

pub fn can_redo(s: Sketch) -> Bool {
  case s.redo_stack {
    [] -> False
    _ -> True
  }
}

/// Maximum remembered history (newest kept). Caps memory growth during long
/// sessions and keeps undo depth human.
const max_history = 200

fn push_history(s: Sketch, new_dots: List(Dot)) -> Sketch {
  Sketch(
    new_dots,
    push_capped([Snapshot(s.dots, s.redo_stack), ..s.undo_stack]),
    [],
  )
}

/// Keep the newest `max_history` snapshots, silently dropping the oldest.
fn push_capped(stack: List(Snapshot)) -> List(Snapshot) {
  case list.length(stack) > max_history {
    True -> list.take(stack, max_history)
    False -> stack
  }
}

fn in_bounds(s: Sketch, index: Int) -> Bool {
  { index >= 0 } && { index < dot_count(s) }
}

pub fn add_dot(s: Sketch, at: Dot) -> Sketch {
  push_history(s, list.append(s.dots, [at]))
}

pub fn remove_dot(s: Sketch, index: Int) -> Sketch {
  case in_bounds(s, index) {
    False -> s
    True ->
      push_history(
        s,
        list.append(list.take(s.dots, index), list.drop(s.dots, index + 1)),
      )
  }
}

/// Begin a drag on dot `index`: snapshots once, changes nothing.
pub fn grab_dot(s: Sketch, index: Int) -> Sketch {
  case in_bounds(s, index) {
    False -> s
    True ->
      Sketch(
        s.dots,
        [Snapshot(s.dots, s.redo_stack), ..s.undo_stack],
        [],
      )
  }
}

/// Move dot `index` during a drag: no history, no redo clearing.
pub fn set_dot(s: Sketch, index: Int, at: Dot) -> Sketch {
  case in_bounds(s, index) {
    False -> s
    True ->
      Sketch(
        list.append(list.take(s.dots, index), [at, ..list.drop(s.dots, index + 1)]),
        s.undo_stack,
        s.redo_stack,
      )
  }
}

/// A grab that never moved (click, or drag back to the exact start): undo the
/// grab itself and restore the redo stack that grabbing displaced.
pub fn cancel_grab(s: Sketch) -> Sketch {
  case s.undo_stack {
    [Snapshot(snapped, redo), ..rest] ->
      case snapped == s.dots {
        True -> Sketch(s.dots, rest, redo)
        False -> s
      }
    _ -> s
  }
}

pub fn undo(s: Sketch) -> Sketch {
  case s.undo_stack {
    [Snapshot(prev, _), ..rest] ->
      Sketch(prev, rest, [s.dots, ..s.redo_stack])
    _ -> s
  }
}

pub fn redo(s: Sketch) -> Sketch {
  case s.redo_stack {
    [next, ..rest] ->
      Sketch(next, [Snapshot(s.dots, s.redo_stack), ..s.undo_stack], rest)
    _ -> s
  }
}

pub fn clear(s: Sketch) -> Sketch {
  case s.dots {
    [] -> s
    _ -> push_history(s, [])
  }
}

/// Load a dot list as an undoable action (presets, imports).
pub fn load_dots(s: Sketch, dots: List(Dot)) -> Sketch {
  push_history(s, dots)
}

// ---------------------------------------------------------------------------
// Seed presets (star, heart, wobble) in sketch space 0..100, y-down.
// They double as test fixtures for the math core.
// ---------------------------------------------------------------------------

const pi = 3.141_592_653_589_793

@external(erlang, "math", "cos")
@external(javascript, "./fourier_sketch_ffi.mjs", "cos")
fn cos(x: Float) -> Float

@external(erlang, "math", "sin")
@external(javascript, "./fourier_sketch_ffi.mjs", "sin")
fn sin(x: Float) -> Float

/// Index sequence [0, 1, .., n-1] — gleam_stdlib 1.0 has no list.range.
fn indices(n: Int) -> List(Int) {
  list.repeat(Nil, n)
  |> list.index_map(fn(_, i) { i })
}

/// 5-point star: 10 vertices alternating outer/inner radius.
pub fn star() -> List(Dot) {
  indices(10)
  |> list.map(fn(i) {
    let a =
      { pi *. { int.to_float(i) /. 5.0 } } -. { pi /. 2.0 }
    let r = case { i % 2 } == 0 {
      True -> 40.0
      False -> 17.0
    }
    #({ 50.0 +. { r *. cos(a) } }, { 50.0 +. { r *. sin(a) } })
  })
}

/// Parametric heart (y-up curve flipped into y-down sketch space).
pub fn heart() -> List(Dot) {
  indices(20)
  |> list.map(fn(i) {
    let t = 2.0 *. pi *. { int.to_float(i) /. 20.0 }
    let x = 16.0 *. { cube(sin(t)) }
    let y =
      { 13.0 *. cos(t) }
      -. { 5.0 *. cos({ 2.0 *. t }) }
      -. { 2.0 *. cos({ 3.0 *. t }) }
      -. cos({ 4.0 *. t })
    #({ 50.0 +. { 2.4 *. x } }, { 50.0 -. { 2.4 *. y } })
  })
}

/// Circle with a sinusoidal radius wobble.
pub fn wobble() -> List(Dot) {
  indices(24)
  |> list.map(fn(i) {
    let t = 2.0 *. pi *. { int.to_float(i) /. 24.0 }
    let r = 30.0 +. { 8.0 *. sin({ 5.0 *. t }) }
    #({ 50.0 +. { r *. cos(t) } }, { 50.0 +. { r *. sin(t) } })
  })
}

fn cube(x: Float) -> Float {
  { x *. x } *. x
}