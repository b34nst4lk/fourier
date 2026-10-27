//// Visit-date logic for the daily schedule.
//// Pure — no clock reads, no timezone database: the visitor's offset, already
//// clamped, is the whole input.
////
//// Conventions
//// -----------
//// - A date is the ISO string "YYYY-MM-DD": fixed width, zero padded, four
////   digit years. That makes lexicographic order equal calendar order, which
////   the never-past rule relies on (see `serve_date`).
//// - `tz_offset_minutes` is the offset to ADD to UTC to reach the visitor's
////   local time: UTC+02:00 is +120, UTC−05:00 is −300. Note that JavaScript's
////   `Date.getTimezoneOffset()` reports the opposite sign, so the client sends
////   its negation: `-new Date().getTimezoneOffset()`.
//// - The offset is clamped to ±14h (±840 min): the real-world extremes are
////   UTC−12:00 and UTC+14:00, so anything beyond that is bad input, and a
////   forged value must not be able to reach another day's puzzle.
//// - "Midnight" is the visitor's local midnight: the date is the calendar date
////   of the instant as seen by the visitor.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

/// ±14h, in minutes (the clamp).
pub const max_offset_minutes = 840

const minutes_per_hour = 60

const seconds_per_day = 86_400

const digits = "0123456789"

pub fn clamp_offset(minutes: Int) -> Int {
  case minutes > max_offset_minutes {
    True -> max_offset_minutes
    False ->
      case minutes < -max_offset_minutes {
        True -> -max_offset_minutes
        False -> minutes
      }
  }
}

/// The visitor-local calendar date of `utc_epoch_seconds`, in "YYYY-MM-DD",
/// with `tz_offset_minutes` clamped to ±14h.
pub fn visitor_local_date(
  utc_epoch_seconds: Int,
  tz_offset_minutes: Int,
) -> String {
  let offset_seconds = clamp_offset(tz_offset_minutes) * minutes_per_hour
  let local_seconds = utc_epoch_seconds + offset_seconds
  let #(year, month, day) =
    civil_from_days(floor_div(local_seconds, seconds_per_day))
  pad(year, 4) <> "-" <> pad(month, 2) <> "-" <> pad(day, 2)
}

/// Never-past rule: serve the visitor's local date, but never one newer than the
/// newest published show-date. `None` means nothing is published yet — the
/// client falls back to the built-in quaver.
pub fn serve_date(
  proposed_local: String,
  newest_published: Option(String),
) -> Option(String) {
  case newest_published {
    None -> None
    Some(newest) ->
      case string.compare(proposed_local, newest) {
        order.Gt -> Some(newest)
        _ -> Some(proposed_local)
      }
  }
}

/// Structural + calendar validity of a "YYYY-MM-DD" date. Rejects
/// out-of-range months/days and impossible leap days (2026-02-29).
pub fn is_valid_date(date: String) -> Bool {
  case string.length(date) == 10 {
    False -> False
    True -> {
      // string.slice takes (string, index, LENGTH) in stdlib 1.x.
      let year = string.slice(date, 0, 4)
      let month = string.slice(date, 5, 2)
      let day = string.slice(date, 8, 2)
      let dashed =
        string.slice(date, 4, 1) == "-" && string.slice(date, 7, 1) == "-"
      case dashed && all_digits(year) && all_digits(month) && all_digits(day) {
        False -> False
        True ->
          case int.parse(year), int.parse(month), int.parse(day) {
            Ok(y), Ok(m), Ok(d) ->
              m >= 1 && m <= 12 && d >= 1 && d <= days_in_month(y, m)
            _, _, _ -> False
          }
      }
    }
  }
}

// ---------- internals ----------

fn all_digits(text: String) -> Bool {
  text
  |> string.to_graphemes
  |> list.all(fn(grapheme) { string.contains(digits, grapheme) })
}

fn is_leap_year(year: Int) -> Bool {
  { year % 4 == 0 && year % 100 != 0 } || year % 400 == 0
}

fn days_in_month(year: Int, month: Int) -> Int {
  case month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 -> 31
    4 | 6 | 9 | 11 -> 30
    2 ->
      case is_leap_year(year) {
        True -> 29
        False -> 28
      }
    _ -> 0
  }
}

/// Integer division rounding towards −infinity (Gleam's `/` truncates).
fn floor_div(numerator: Int, denominator: Int) -> Int {
  let quotient = numerator / denominator
  case numerator % denominator < 0 {
    True -> quotient - 1
    False -> quotient
  }
}

fn pad(value: Int, width: Int) -> String {
  string.pad_start(int.to_string(value), width, "0")
}

/// Days since 1970-01-01 -> civil date (Howard Hinnant's civil_from_days,
/// with the truncating-division era adjustment). Pure integer arithmetic, so
/// no timezone database and no leap-second surface.
fn civil_from_days(days: Int) -> #(Int, Int, Int) {
  let z = days + 719_468
  let era = case z >= 0 {
    True -> z
    False -> z - 146_096
  }
  let era = era / 146_097
  let day_of_era = z - era * 146_097
  let year_of_era =
    {
      day_of_era
      - day_of_era
      / 1460
      + day_of_era
      / 36_524
      - day_of_era
      / 146_096
    }
    / 365
  let year = year_of_era + era * 400
  let day_of_year =
    day_of_era - { 365 * year_of_era + year_of_era / 4 - year_of_era / 100 }
  let month_part = { 5 * day_of_year + 2 } / 153
  let day = day_of_year - { 153 * month_part + 2 } / 5 + 1
  let month = case month_part < 10 {
    True -> month_part + 3
    False -> month_part - 9
  }
  let adjusted_year = case month <= 2 {
    True -> year + 1
    False -> year
  }
  #(adjusted_year, month, day)
}
