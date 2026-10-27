//// The one wall-clock read in the backend.
////
//// Everything else in toy_admin takes time as an argument (dates.gleam does;
//// the throttle's `evaluate` does) so its logic stays pure and testable. Two call
//// sites need "now" for real: the store's created_at/updated_at stamps and the
//// `/api/puzzle/today` route (which must know the visitor's local date). Both
//// go through here.
////
//// Epoch SECONDS, UTC: sub-second precision buys nothing for a daily puzzle and
//// would make stored timestamps noisy to read.

import gleam/erlang/atom

/// Seconds since the Unix epoch, UTC.
pub fn now_seconds() -> Int {
  system_time(atom.create("second"))
}

@external(erlang, "erlang", "system_time")
fn system_time(unit: atom.Atom) -> Int
