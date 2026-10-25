//// The calendar's one piece of arithmetic: which day may the next puzzle take
//// (agent drafts, 2026-10-25).
////
//// The approve action and a new puzzle both prefilled their date with it, and
//// the browser computes it — the server has no opinion about "the next free day"
//// (it only answers "that date is taken" when it is). So this is the UI's rule,
//// and it is stated in one place, in plain dates:
////
////   the first day on or after TODAY that no row occupies.
////
//// Dates are strings on the wire (YYYY-MM-DD, the store's own vocabulary), so
//// the arithmetic converts to a day count and back rather than to a platform
//// Date object: no timezone, no DST, no leap-second surprises — a day is a day
//// (the same reason the backend's dates.gleam does its own calendar).

import admin_ui/schedule
import gleam/list
import gleeunit/should

/// A Wednesday; the weekday itself never matters (nothing here knows about
/// working days), it is only a fixed point in the calendar.
const today = "2026-11-18"

pub fn a_free_day_is_today_test() {
  // Nothing scheduled at all: the answer is today, not tomorrow.
  should.equal("2026-11-18", schedule.next_available([], today))
  // Rows in the past do not push the answer forward: they are already served.
  should.equal(
    "2026-11-18",
    schedule.next_available(["2026-11-01", "2026-11-17"], today),
  )
}

pub fn a_taken_today_moves_to_tomorrow_test() {
  should.equal("2026-11-19", schedule.next_available(["2026-11-18"], today))
  should.equal(
    "2026-11-20",
    schedule.next_available(["2026-11-18", "2026-11-19"], today),
  )
}

pub fn a_gap_between_taken_days_is_the_answer_test() {
  // The 18th and the 20th are taken; the 19th is the next free day, and the
  // run does NOT continue to the 21st just because a later day is also taken.
  should.equal(
    "2026-11-19",
    schedule.next_available(["2026-11-18", "2026-11-20", "2026-11-25"], today),
  )
}

pub fn a_row_scheduled_far_ahead_leaves_today_free_test() {
  should.equal("2026-11-18", schedule.next_available(["2027-03-01"], today))
}

pub fn drafts_occupy_no_day_test() {
  // A draft has no date (the store's empty show_date marker), so it can never
  // hold a day against the next puzzle.
  should.equal("2026-11-18", schedule.next_available(["", "", ""], today))
  should.equal(
    "2026-11-19",
    schedule.next_available(["", "2026-11-18", ""], today),
  )
}

pub fn a_solid_run_ends_the_day_after_its_last_test() {
  // Today through the 22nd are all taken: the answer is the 23rd. Nothing says
  // so explicitly — the walk simply runs out of taken days there.
  should.equal(
    "2026-11-23",
    schedule.next_available(
      ["2026-11-18", "2026-11-19", "2026-11-20", "2026-11-21", "2026-11-22"],
      today,
    ),
  )
}

pub fn the_walk_rolls_over_months_and_years_test() {
  should.equal(
    "2026-12-01",
    schedule.next_available(["2026-11-30"], "2026-11-30"),
  )
  should.equal(
    "2027-01-01",
    schedule.next_available(["2026-12-31"], "2026-12-31"),
  )
  // 2026 is not a leap year; 2028 is (so the 29th exists and is not skipped).
  should.equal(
    "2026-03-01",
    schedule.next_available(["2026-02-28"], "2026-02-28"),
  )
  should.equal(
    "2028-02-29",
    schedule.next_available(["2028-02-28"], "2028-02-28"),
  )
}

pub fn a_day_no_calendar_recognises_is_ignored_test() {
  // A row the walk cannot read cannot hold a day: it is skipped, not allowed to
  // stop the walk (this is the one place a bad date could hang the UI).
  should.equal(
    "2026-11-18",
    schedule.next_available(
      ["nope", "2026-11-18x", "2026-13-01", "2026-11-32"],
      today,
    ),
  )
}

pub fn an_unreadable_today_is_given_back_unchanged_test() {
  // No arithmetic is possible, so the field keeps what it had: a prefill that
  // looks like a date is better than a blank one, and the server still validates
  // whatever is saved.
  should.equal("soon", schedule.next_available(["2026-11-18"], "soon"))
}

pub fn a_date_survives_the_round_trip_test() {
  // The conversion the whole file rests on: a day count and back is the same
  // string, including the awkward ones (year boundaries, leap day, padding).
  let dates = [
    "1970-01-01",
    "2000-02-29",
    "2026-11-18",
    "2026-12-31",
    "2027-01-01",
    "2028-02-29",
  ]
  list.each(dates, fn(date) {
    let assert Ok(day) = schedule.day_number(date)
    should.equal(date, schedule.date_of(day))
  })
  // and the count is monotone: consecutive days are one apart
  let assert Ok(first) = schedule.day_number("1970-01-01")
  let assert Ok(second) = schedule.day_number("1970-01-02")
  should.equal(1, second - first)
}
