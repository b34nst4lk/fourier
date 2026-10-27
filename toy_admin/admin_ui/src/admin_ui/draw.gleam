//// The drawing under construction: an ordered dot list with undo/clear, plus
//// the family's node editing.
////
//// This is the editor's counterpart to fourier_sketch's sketch panel, and it
//// speaks the SKETCH's gesture vocabulary verbatim — grab / move / drop,
//// hit-test inside a radius, right-click to delete — over the same 0..100 dot
//// space:
////
////   press far from every dot  -> ADD (the tap-to-append contract)
////   press within `hit_radius` -> grab, then `set` freely, then `drop`
////   press with the right button within `hit_radius` -> `remove`
////
//// The drag is TWO-PHASE, exactly as in sketch.gleam: `grab` pushes ONE
//// snapshot and changes nothing, `set` moves the dot without touching history
//// (so a long drag is one undo step), and `drop` closes the gesture. The admin
//// has no redo stack, so its `drop` is the sketch's `cancel_grab` plus the one
//// fact the redo-less sibling needs: did anything actually move? A press that
//// never moved is a CLICK — the grab's own snapshot is popped, so it costs no
//// undo entry and changes no dot.
////
//// Index space: every index this module takes or hands back is in DRAWING order
//// (oldest first — the order `dots()` returns), never the internal newest-first
//// cons order. The storage order stays newest-first because the append and the
//// neighbour check are O(1) that way.
////
//// The other rule worth stating: an ADD that lands (almost) on the previous dot
//// is DROPPED (`min_gap`). It guards a fold over loaded dots; the pointer layer
//// never gets that close — a press that near is a grab.

import admin_ui/score.{type Point}
import gleam/float
import gleam/list

/// The editing state.
///
/// `dots` is newest-first (a plain cons list): the neighbour check and the
/// append are both O(1) that way, which is what a pointer-driven editor wants.
/// The public accessors reverse, so `dots()` / `closed_path()` / `wire_dots()`
/// all speak the drawing order a human expects. `history` holds the previous
/// `dots` lists in the same representation, so undo is a pop and can never drift
/// from what is on the canvas.
pub type Drawing {
  Drawing(dots: List(Point), history: List(List(Point)))
}

/// Fewest dots the backend will accept as a drawing (`drawing.min_dots`).
pub const min_dots = 3

/// Dots closer than this (sketch units) to the previous dot are ignored.
pub const min_gap = 0.75

/// How near (sketch units) a press must land to grab or delete a dot.
/// fourier_sketch's `hit_radius`, the same number in the same space.
pub const hit_radius = 3.0

pub fn empty() -> Drawing {
  Drawing([], [])
}

/// The dots in drawing order (oldest first).
pub fn dots(drawing: Drawing) -> List(Point) {
  list.reverse(drawing.dots)
}

pub fn count(drawing: Drawing) -> Int {
  list.length(drawing.dots)
}

pub fn can_undo(drawing: Drawing) -> Bool {
  can_submit(drawing)
}

/// Three dots is a triangle — the smallest shape the pipeline accepts.
pub fn can_submit(drawing: Drawing) -> Bool {
  count(drawing) >= min_dots
}

/// Append a dot, unless it doubles the previous one.
pub fn add(drawing: Drawing, point: Point) -> Drawing {
  case drawing.dots {
    [] -> Drawing([point], [drawing.dots, ..drawing.history])
    [last, ..rest] -> {
      let #(dx, dy) = #(point.0 -. last.0, point.1 -. last.1)
      case dx *. dx +. dy *. dy <. min_gap *. min_gap {
        True -> drawing
        False ->
          Drawing([point, last, ..rest], [drawing.dots, ..drawing.history])
      }
    }
  }
}

/// Index of the dot closest to `at`, if any lies within `max_dist` (inclusive).
/// Squared distances throughout (no sqrt) and ties go to the EARLIEST index —
/// fourier_sketch's `nearest_dot`, so grabbing the same spot always grabs the
/// same dot. `points` is in drawing order, and the index is in that space.
pub fn nearest(
  points: List(Point),
  at: Point,
  max_dist: Float,
) -> Result(Int, Nil) {
  let limit = max_dist *. max_dist
  let #(_, found) =
    list.index_fold(points, #(limit, Error(Nil)), fn(acc, point, index) {
      let #(dx, dy) = #(point.0 -. at.0, point.1 -. at.1)
      let distance = { dx *. dx } +. { dy *. dy }
      let closer = case acc.1 {
        Ok(_) -> distance <. acc.0
        Error(_) -> distance <=. acc.0
      }
      case closer {
        True -> #(distance, Ok(index))
        False -> acc
      }
    })
  found
}

/// Delete the dot at `index` (drawing order): ONE undo step, the surviving
/// dots keep their order. An index off either end is a silent no-op.
pub fn remove(drawing: Drawing, index: Int) -> Drawing {
  case in_bounds(drawing, index) {
    False -> drawing
    True -> {
      let ordered = dots(drawing)
      let kept =
        list.append(list.take(ordered, index), list.drop(ordered, index + 1))
      Drawing(list.reverse(kept), [drawing.dots, ..drawing.history])
    }
  }
}

/// Begin a drag on dot `index`: snapshot once, change nothing. The snapshot is
/// the whole undo entry a drag will ever cost; `drop` takes it back if the drag
/// never moved.
pub fn grab(drawing: Drawing, index: Int) -> Drawing {
  case in_bounds(drawing, index) {
    False -> drawing
    True -> Drawing(drawing.dots, [drawing.dots, ..drawing.history])
  }
}

/// Move dot `index` during a drag: no history, no undo entry — the grab owns
/// the single step.
pub fn set(drawing: Drawing, index: Int, point: Point) -> Drawing {
  case in_bounds(drawing, index) {
    False -> drawing
    True -> {
      let ordered = dots(drawing)
      let moved =
        list.append(list.take(ordered, index), [
          point,
          ..list.drop(ordered, index + 1)
        ])
      Drawing(list.reverse(moved), drawing.history)
    }
  }
}

/// Close the drag on `drawing` (only ever the drawing an open `grab` made):
/// returns the drawing and whether the drag actually moved.
///
/// A drag that never moved — a plain click, or a drag back to the exact start —
/// is a click: the grab's own snapshot is popped, so nothing is left for undo
/// and no preview needs scheduling. A real move keeps its snapshot: exactly one
/// undo step for the whole drag.
pub fn drop(drawing: Drawing) -> #(Drawing, Bool) {
  case drawing.history {
    [snapshot, ..rest] ->
      case snapshot == drawing.dots {
        True -> #(Drawing(drawing.dots, rest), False)
        False -> #(drawing, True)
      }
    [] -> #(drawing, False)
  }
}

fn in_bounds(drawing: Drawing, index: Int) -> Bool {
  { index >= 0 } && { index < count(drawing) }
}

pub fn undo(drawing: Drawing) -> Drawing {
  case drawing.history {
    [previous, ..rest] -> Drawing(previous, rest)
    [] -> drawing
  }
}

pub fn clear(drawing: Drawing) -> Drawing {
  case drawing.dots {
    [] -> drawing
    _ -> Drawing(dots: [], history: [drawing.dots, ..drawing.history])
  }
}

/// The closing path the panel strokes through the dots: an
/// `M x y L x y ... Z` string in the panel's 0..100 viewBox. fourier_sketch
/// smooths its sketch path with curves; the editor deliberately does not — it
/// shows the polygon the derivation will actually resample.
pub fn closed_path(drawing: Drawing) -> String {
  case dots(drawing) {
    [] -> ""
    [first, ..rest] ->
      list.fold(rest, "M " <> coord(first), fn(acc, point) {
        acc <> " L " <> coord(point)
      })
      <> " Z"
  }
}

fn coord(point: Point) -> String {
  float.to_string(point.0) <> " " <> float.to_string(point.1)
}

/// The wire shape the API expects for `dots`: `[[x,y],...]`.
pub fn wire_dots(drawing: Drawing) -> List(List(Float)) {
  list.map(dots(drawing), fn(point) {
    let #(x, y) = point
    [x, y]
  })
}
