//// The calendar's one piece of arithmetic: WHICH DAY may the next puzzle take
//// (agent drafts, 2026-10-25).
////
//// Both places that offer a date field — a new puzzle and an approve — prefill
//// it with this answer, and the browser computes it: the server has no opinion
//// about "the next free day" (it only refuses a day another published puzzle
//// holds). So the rule lives here, stated in plain dates:
////
////     the first day on or after TODAY that no row occupies.
////
//// Dates cross the wire as strings in the store's own vocabulary (YYYY-MM-DD),
//// so the arithmetic converts to a day count and back instead of building a
//// platform Date: no timezone, no DST, no leap-second surprise — a day is a day.
//// (The backend's dates.gleam does its own calendar for the same reason; this is
//// the browser's copy, and it needs only what a prefill needs.)
////
//// Drafts have NO date (the store's empty show_date marker), so they can never
//// hold a day: an undated sketch is not competing for the schedule. A row whose
//// date the walk cannot read is skipped for the same reason — a corrupt row must
//// not be able to stall the UI.

import gleam/int
import gleam/list
import gleam/string

/// Today, in the browser's LOCAL timezone — where the human is, not where the
/// server is (this date never crosses the wire; it is a prefill).
@external(javascript, "./today.mjs", "today_local")
pub fn today() -> String

/// The first free day on or after `start`. An unreadable `start` is handed back
/// unchanged: a prefill that still looks like a date beats a blank one, and the
/// server validates whatever is saved anyway.
pub fn next_available(dates: List(String), start: String) -> String {
  case day_number(start) {
    Error(_) -> start
    Ok(day) -> date_of(first_free(day, taken_days(dates)))
  }
}

/// The day count of every readable date in the list; the unreadable ones and the
/// drafts (empty) drop out here.
fn taken_days(dates: List(String)) -> List(Int) {
  list.filter_map(dates, day_number)
}

fn first_free(day: Int, taken: List(Int)) -> Int {
  case list.contains(taken, day) {
    // The walk only ever visits days that a row holds, so it ends after at most
    // (rows + 1) steps: a solid run finishes on the day after its last.
    True -> first_free(day + 1, taken)
    False -> day
  }
}

/// A `YYYY-MM-DD` date as a day count (days since 1970-01-01, the civil-from-days
/// convention). A string in any other shape, or with a month/day that cannot
/// exist, is Error: nothing is "fixed up" into a date.
pub fn day_number(date: String) -> Result(Int, Nil) {
  case string.split(date, "-") {
    [years, months, days] ->
      case int.parse(years), int.parse(months), int.parse(days) {
        Ok(year), Ok(month), Ok(day)
          if year > 0 && month >= 1 && month <= 12 && day >= 1 && day <= 31
        -> Ok(days_from_civil(year, month, day))
        _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

/// The date of a day count, zero-padded back into `YYYY-MM-DD`.
pub fn date_of(day: Int) -> String {
  let z = day + 719_468
  let era = z / 146_097
  let doe = z - era * 146_097
  let yoe = { doe - doe / 1460 + doe / 36_524 - doe / 146_096 } / 365
  let year = yoe + era * 400
  let doy = doe - { 365 * yoe + yoe / 4 - yoe / 100 }
  let mp = { 5 * doy + 2 } / 153
  let day_of_month = doy - { 153 * mp + 2 } / 5 + 1
  let month =
    mp
    + case mp < 10 {
      True -> 3
      False -> -9
    }
  let year = case month <= 2 {
    True -> year + 1
    False -> year
  }
  pad(year, 4) <> "-" <> pad(month, 2) <> "-" <> pad(day_of_month, 2)
}

// Hinnant's civil-from-days / days-from-civil, the standard pair: exact for every
// day of the proleptic Gregorian calendar, and integer-only.
fn days_from_civil(year: Int, month: Int, day: Int) -> Int {
  let year = case month <= 2 {
    True -> year - 1
    False -> year
  }
  let era = year / 400
  let yoe = year - era * 400
  let shifted =
    month
    + case month > 2 {
      True -> -3
      False -> 9
    }
  let doy = { 153 * shifted + 2 } / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146_097 + doe - 719_468
}

fn pad(number: Int, width: Int) -> String {
  let text = int.to_string(number)
  case string.length(text) >= width {
    True -> text
    False -> string.repeat("0", width - string.length(text)) <> text
  }
}
