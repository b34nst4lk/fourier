//// Per-puzzle stats arithmetic (PLAN-daily-puzzles.md §4 Q23, phase 4a).
////
//// The store hands over the raw attempt numbers: (attempts, solves) from one
//// aggregate and the ascending list of every attempt's move_count from
//// `store.move_counts`. This module turns those into the menu row:
////
////   attempts    every attempt row (solves + abandons)
////   solves      solved rows
////   solvePct    solves/attempts as a ONE-decimal string ("97.3"),
////               null when there are no attempts
////   medianMoves median of ALL attempts' move_count — an abandon brings its own
////               count, and a solve brings its move list's length; null when
////               there are no attempts. The arithmetic median can be
////               fractional (even count: the mean of the two middle values),
////               so it is a Float on the wire.
////
//// Percent arithmetic is integer-only (no float rounding surprises): the
//// value is computed in TENTHS, rounded half-up, then formatted. 97.3% must
//// never print as 97.29999999999998.

import gleam/option
import gleeunit/should
import toy_admin/stats

// ---------- solve percentage ----------

pub fn solve_pct_is_null_without_attempts_test() {
  should.equal(option.None, stats.solve_pct(0, 0))
  // Defensive: a negative attempt count cannot mean a percentage.
  should.equal(option.None, stats.solve_pct(-1, 0))
}

pub fn solve_pct_keeps_one_decimal_test() {
  // 73/75 = 97.333...% -> "97.3" (truncated by rounding, printed exactly).
  should.equal(option.Some("97.3"), stats.solve_pct(75, 73))
  // 1/3 = 33.333...% -> "33.3".
  should.equal(option.Some("33.3"), stats.solve_pct(3, 1))
  // 2/3 = 66.666...% -> "66.7" (half-up on the tenths digit).
  should.equal(option.Some("66.7"), stats.solve_pct(3, 2))
}

pub fn solve_pct_renders_the_ends_exactly_test() {
  should.equal(option.Some("100.0"), stats.solve_pct(5, 5))
  should.equal(option.Some("0.0"), stats.solve_pct(5, 0))
  // Exactly one decimal always: 12.5 must not collapse to "12.5" vs "12.50"
  // differences later; 6.25 rounds half-up to 6.3, not 6.2.
  should.equal(option.Some("12.5"), stats.solve_pct(8, 1))
  should.equal(option.Some("6.3"), stats.solve_pct(16, 1))
}

pub fn solve_pct_rounds_a_tie_up_test() {
  // 1/20 = 5.0 exactly (no tie); 1/40 = 2.5 -> "2.5"; 1/80 = 1.25 -> "1.3".
  should.equal(option.Some("2.5"), stats.solve_pct(40, 1))
  should.equal(option.Some("1.3"), stats.solve_pct(80, 1))
}

// ---------- median ----------

pub fn median_of_nothing_is_null_test() {
  should.equal(option.None, stats.median([]))
}

pub fn median_of_one_is_that_value_test() {
  should.equal(option.Some(7.0), stats.median([7]))
}

pub fn median_of_an_odd_count_is_the_middle_test() {
  should.equal(option.Some(3.0), stats.median([1, 3, 5]))
  should.equal(option.Some(9.0), stats.median([1, 9, 9, 9, 12]))
}

pub fn median_of_an_even_count_averages_the_middle_two_test() {
  // The honest arithmetic median, hence fractional values are possible.
  should.equal(option.Some(3.0), stats.median([2, 4]))
  should.equal(option.Some(2.5), stats.median([2, 3]))
  should.equal(option.Some(2.5), stats.median([1, 2, 3, 4]))
}

// ---------- the row ----------

pub fn summarize_composes_the_menu_row_test() {
  let summary = stats.summarize(attempts: 3, solves: 1, counts: [2, 3, 7])
  should.equal(3, summary.attempts)
  should.equal(1, summary.solves)
  should.equal(option.Some("33.3"), summary.solve_pct)
  should.equal(option.Some(3.0), summary.median_moves)
}

pub fn summarize_of_no_attempts_is_all_null_test() {
  let summary = stats.summarize(attempts: 0, solves: 0, counts: [])
  should.equal(0, summary.attempts)
  should.equal(0, summary.solves)
  should.equal(option.None, summary.solve_pct)
  should.equal(option.None, summary.median_moves)
}
