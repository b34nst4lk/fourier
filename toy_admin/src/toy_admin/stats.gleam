//// Per-puzzle stats.
////
//// The store hands over raw numbers — `stats` gives (attempts, solves), and
//// `move_counts` gives every attempt's move_count — and this module turns them
//// into one menu row. Nothing here touches SQL: the arithmetic is pure and
//// pinned by tests, which matters because two of these numbers are policy:
////
////   attempts     every attempt row: solves AND abandons
////   solves       rows with solved = 1
////   solvePct     solves / attempts, ONE decimal, null when attempts = 0
////   medianMoves  the arithmetic median of ALL attempts' move_count.
////                An abandon brings its own client-reported count and a solve
////                brings its move list's length (store.gleam: `move_count` is
////                always an integer, for exactly this reason). The median of an
////                even-sized set can be fractional (mean of the two middle
////                values), so it is a Float on the wire; null when attempts = 0.
////
//// Why an abandon's count belongs in the median: the question the number
//// answers is "how many moves does this puzzle take a player?" across everyone
//// who touched it, not "how many moves did the winners need?". Excluding
//// abandons would flatter a puzzle everyone bounced off.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

pub type Summary {
  Summary(
    attempts: Int,
    solves: Int,
    solve_pct: Option(String),
    median_moves: Option(Float),
  )
}

pub fn summarize(
  attempts attempts: Int,
  solves solves: Int,
  counts counts: List(Int),
) -> Summary {
  Summary(
    attempts: attempts,
    solves: solves,
    solve_pct: solve_pct(attempts, solves),
    median_moves: median(counts),
  )
}

/// `solves / attempts` as a one-decimal percentage string ("97.3"), or `None`
/// when there are no attempts.
///
/// Integer-only on purpose: the value is computed in TENTHS, rounded half-up,
/// then formatted. Float arithmetic would print 97.29999999999998 sooner or
/// later; this cannot.
pub fn solve_pct(attempts: Int, solves: Int) -> Option(String) {
  case attempts > 0 {
    False -> None
    True -> {
      // tenths = round(solves * 1000 / attempts)
      //         = floor((solves * 2000 + attempts) / (2 * attempts))
      let tenths = { solves * 2000 + attempts } / { 2 * attempts }
      Some(int.to_string(tenths / 10) <> "." <> int.to_string(tenths % 10))
    }
  }
}

/// The arithmetic median of a set of move counts; `None` for an empty set.
/// Sorts defensively: the store already returns ascending rows, but a caller
/// passing an unsorted list must not silently get a wrong number.
pub fn median(counts counts: List(Int)) -> Option(Float) {
  let sorted = list.sort(counts, int.compare)
  let count = list.length(sorted)
  let middle = count / 2
  case count {
    0 -> None
    _ ->
      case count % 2 {
        // Odd: the middle value.
        1 -> option.map(value_at(sorted, middle), int.to_float)
        // Even: the mean of the two middle values.
        _ ->
          case value_at(sorted, middle - 1), value_at(sorted, middle) {
            Some(lower), Some(upper) -> Some(int.to_float(lower + upper) /. 2.0)
            _, _ -> None
          }
      }
  }
}

fn value_at(values: List(Int), index: Int) -> Option(Int) {
  case list.drop(from: values, up_to: index) {
    [value, ..] -> Some(value)
    [] -> None
  }
}
