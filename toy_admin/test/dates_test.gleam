//// Visit-date logic (PLAN-daily-puzzles.md §2 Q11): visitor-local midnight
//// with a clamped ±14h offset, and the never-past serving rule.

import gleam/option.{None, Some}
import gleeunit/should
import toy_admin/dates

// 2026-10-25T00:00:00Z
const oct_25_midnight = 1_792_886_400

pub fn epoch_zero_is_1970_test() {
  should.equal("1970-01-01", dates.visitor_local_date(0, 0))
}

pub fn plain_utc_visitor_test() {
  // 2026-10-25T00:00:00Z, no offset
  should.equal("2026-10-25", dates.visitor_local_date(oct_25_midnight, 0))
}

pub fn east_offset_crosses_into_next_day_test() {
  // 2026-10-24T23:00:00Z in UTC+02:00 -> 2026-10-25T01:00 local
  should.equal("2026-10-25", dates.visitor_local_date(1_792_882_800, 120))
}

pub fn west_offset_crosses_into_previous_day_test() {
  // 2026-10-25T01:00:00Z in UTC−02:00 -> 2026-10-24T23:00 local
  should.equal("2026-10-24", dates.visitor_local_date(1_792_890_000, -120))
}

pub fn year_rollover_forward_test() {
  // 2026-12-31T23:30:00Z in UTC+01:00 -> 2027-01-01T00:30 local
  should.equal("2027-01-01", dates.visitor_local_date(1_798_759_800, 60))
}

pub fn year_rollover_backward_test() {
  // 2027-01-01T00:30:00Z in UTC−01:00 -> 2026-12-31T23:30 local
  should.equal("2026-12-31", dates.visitor_local_date(1_798_763_400, -60))
}

pub fn leap_day_exists_in_2028_test() {
  // 2028-02-28T23:30:00Z in UTC+01:00 -> 2028-02-29T00:30 local
  should.equal("2028-02-29", dates.visitor_local_date(1_835_393_400, 60))
}

pub fn feb_29_is_skipped_in_2026_test() {
  // 2026-02-28T23:30:00Z in UTC+01:00 -> 2026-03-01T00:30 local
  should.equal("2026-03-01", dates.visitor_local_date(1_772_321_400, 60))
}

pub fn offset_is_clamped_at_plus_14h_test() {
  // 2026-06-01T10:00:00Z with a claimed +15h lands at the +14h clamp:
  // 2026-06-02T00:00 local (not 2026-06-02T01:00)
  should.equal("2026-06-02", dates.visitor_local_date(1_780_308_000, 900))
}

pub fn offset_is_clamped_at_minus_14h_test() {
  // 2026-10-25T00:00:00Z with a claimed −15h lands at the −14h clamp:
  // 2026-10-24T10:00 local
  should.equal("2026-10-24", dates.visitor_local_date(oct_25_midnight, -900))
}

pub fn clamp_offset_bounds_test() {
  should.equal(840, dates.clamp_offset(900))
  should.equal(-840, dates.clamp_offset(-900))
  should.equal(840, dates.clamp_offset(840))
  should.equal(-840, dates.clamp_offset(-840))
  should.equal(0, dates.clamp_offset(0))
  should.equal(120, dates.clamp_offset(120))
  should.equal(-330, dates.clamp_offset(-330))
}

// ---------- never-past serving rule (Q11) ----------

pub fn serve_date_clamps_to_newest_published_test() {
  // A visitor whose local date is ahead of the newest published puzzle gets
  // the newest puzzle, never a future one.
  should.equal(
    Some("2026-10-24"),
    dates.serve_date("2026-10-25", Some("2026-10-24")),
  )
}

pub fn serve_date_keeps_an_older_visitor_date_test() {
  // Time-travelling visitors (or a stale cache) get their own date when it is
  // not in the future relative to the schedule.
  should.equal(
    Some("2026-10-24"),
    dates.serve_date("2026-10-24", Some("2026-10-25")),
  )
}

pub fn serve_date_keeps_an_equal_date_test() {
  should.equal(
    Some("2026-10-25"),
    dates.serve_date("2026-10-25", Some("2026-10-25")),
  )
}

pub fn serve_date_with_nothing_published_test() {
  should.equal(None, dates.serve_date("2026-10-25", None))
}

// ---------- date validation (ingest + schedule input) ----------

pub fn valid_dates_test() {
  should.be_true(dates.is_valid_date("2026-10-25"))
  should.be_true(dates.is_valid_date("1970-01-01"))
  should.be_true(dates.is_valid_date("2000-02-29"))
  should.be_true(dates.is_valid_date("2028-02-29"))
  should.be_true(dates.is_valid_date("2026-12-31"))
}

pub fn invalid_dates_test() {
  should.be_false(dates.is_valid_date("2026-02-29"))
  should.be_false(dates.is_valid_date("2026-04-31"))
  should.be_false(dates.is_valid_date("2026-13-01"))
  should.be_false(dates.is_valid_date("2026-00-10"))
  should.be_false(dates.is_valid_date("2026-1-01"))
  should.be_false(dates.is_valid_date("26-01-01"))
  should.be_false(dates.is_valid_date("2026-01-01T00:00:00Z"))
  should.be_false(dates.is_valid_date(""))
  should.be_false(dates.is_valid_date("20xx-01-01"))
}
