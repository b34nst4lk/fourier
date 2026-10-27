//// The calendar row: one document, two fences.
////
////   GET /api/admin/puzzles   (admin.gleam)      the editor's menu
////   GET /api/agent/schedule  (agent.gleam)      the agent's view of the same
////                                               calendar
////
//// The row is identity + schedule + authorship + the stats numbers, and both
//// readers get the SAME fields on purpose: a reviewer comparing the two
//// endpoints should not have to diff two hand-built objects, and a new field
//// (like `status`) must not appear in one and not the other. What differs
//// between the two APIs is the fence and the write routes, not the vocabulary.
////
//// The numbers themselves are `stats.summarize`'s (attempts = every attempt row,
//// solves = solved rows, solvePct one decimal or null, medianMoves the median of
//// ALL attempts' move_count or null). This module only assembles them into JSON.
////
//// The per-row read is N+1 by design (admin.gleam's header argues it): the
//// calendar is hundreds of rows at most, and the store stays a set of small
//// composable primitives.

import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import toy_admin/stats
import toy_admin/store

/// One calendar row. `Error(Nil)` when the store cannot answer for the row's
/// stats: the caller turns that into a 500 StoreError rather than a partial row.
pub fn calendar_row(
  path: String,
  puzzle: store.Puzzle,
) -> Result(json.Json, Nil) {
  use #(attempts, solves) <- result.try(
    store.stats(path, puzzle.id)
    |> result.map_error(fn(_) { Nil }),
  )
  use counts <- result.try(
    store.move_counts(path, puzzle.id)
    |> result.map_error(fn(_) { Nil }),
  )
  let summary =
    stats.summarize(attempts: attempts, solves: solves, counts: counts)

  Ok(
    json.object([
      #("id", json.int(puzzle.id)),
      #("name", json.string(puzzle.name)),
      #("showDate", json.string(puzzle.show_date)),
      // The two facts the admin UI badges and filters on, and the one the
      // agent reads to see which of its shapes a human has dated.
      #("status", json.string(puzzle.status)),
      #("creator", json.string(puzzle.creator)),
      #("attempts", json.int(summary.attempts)),
      #("solves", json.int(summary.solves)),
      #("solvePct", optional_string(summary.solve_pct)),
      #("medianMoves", optional_float(summary.median_moves)),
    ]),
  )
}

/// Every row, in the store's order (newest show_date first, drafts last).
pub fn calendar_rows(
  path: String,
  puzzles: List(store.Puzzle),
) -> Result(List(json.Json), Nil) {
  puzzles
  |> list.map(fn(puzzle) { calendar_row(path, puzzle) })
  |> result.all
}

fn optional_string(value: Option(String)) -> json.Json {
  case value {
    Some(text) -> json.string(text)
    None -> json.null()
  }
}

fn optional_float(value: Option(Float)) -> json.Json {
  case value {
    Some(number) -> json.float(number)
    None -> json.null()
  }
}
