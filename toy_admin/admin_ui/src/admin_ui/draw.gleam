//// The drawing under construction: an ordered dot list with undo/clear
//// (PLAN-daily-puzzles.md §3 authoring, phase 4b).
////
//// This is the editor's counterpart to fourier_sketch's sketch panel, but
//// simpler on purpose: the admin draws a puzzle, it does not edit one dot at a
//// time. So the gesture is "tap to append", `undo` pops the last dot, `clear`
//// starts over, and there is no dragging or hit-testing.
////
//// The one rule worth stating: a tap that lands (almost) on the previous dot is
//// DROPPED. Pointer events fire `down` and then a `move`/`up` at the same spot,
//// and without a proximity gate a single tap would append two dots and the
//// shape would never close. The threshold is in sketch units (0..100), so it is
//// resolution-independent — the FFI converts pixel positions into sketch space
//// before anything reaches this module.

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
