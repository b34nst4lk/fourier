//// The request throttle (PLAN-daily-puzzles.md §3): per-uuid ~20/5min and
//// per-IP 60/5min, both configurable, in memory only.
////
//// WHY A THROTTLE AT ALL: the solve endpoint is the only write surface a
//// stranger can reach. There are no accounts (Q16) — a uuid is a self-chosen
//// identity, cheap to forge — which is exactly why the IP limit is the outer
//// fence and the uuid limit the inner one. Neither is a security control; both
//// keep a stray script from filling the attempts table.
////
//// WHY NO PERSISTENCE: a restart forgets the counters. Worst case is one burst
//// right after a deploy, and the attempts table is telemetry, not money.
////
//// WHY ETS AND NOT AN ACTOR: the limiter is one atomic increment per request.
//// `ets:update_counter/4` is atomic by itself, needs no mailbox, no supervision
//// tree and no queue; an actor would put a serialisation point in front of every
//// request to gain nothing. The table is named and public, created once by
//// `setup()`.
////
//// WINDOWS ARE FIXED, NOT SLIDING: hits are counted per
//// `now / window_seconds` bucket. A fixed window lets a caller send up to 2x
//// the limit across a boundary — a fine trade for a counter that is deleted by
//// key. The bucket is part of the key, so last window's counters are simply
//// never read again (they are swept — see `sweep`).
////
//// KEYS ARE NAMESPACED BY THE CALLER ("uuid-<uuid>", "ip-<addr>"): a uuid that
//// happens to look like an address must not share a counter with it.

import gleam/int
import gleam/option.{type Option}
import gleam/string
import toy_admin/env

/// A budget of `hits` per fixed `window_seconds` window.
pub type Limit {
  Limit(hits: Int, window_seconds: Int)
}

/// The defaults the plan names: ~20 solves per uuid per 5 minutes, 60 per IP.
pub const default_uuid_limit = Limit(hits: 20, window_seconds: 300)

pub const default_ip_limit = Limit(hits: 60, window_seconds: 300)

pub const uuid_limit_env = "THROTTLE_UUID_LIMIT"

pub const uuid_window_env = "THROTTLE_UUID_WINDOW_SECONDS"

pub const ip_limit_env = "THROTTLE_IP_LIMIT"

pub const ip_window_env = "THROTTLE_IP_WINDOW_SECONDS"

/// The one, process-wide table. The name is an Erlang atom on that side
/// (`?TABLE` in throttle_ffi.erl); this constant is the same name as a Gleam
/// String, for documentation and diagnostics.
pub const table_name = "toy_admin_throttle"

/// After how many stale rows a `sweep` runs (see `sweep`).
const sweep_threshold = 4096

pub type Decision {
  Allowed
  Limited(retry_after_seconds: Int)
}

// ---------- configuration ----------

/// The uuid and IP limits from the environment.
pub fn limits() -> #(Limit, Limit) {
  limits_from(env.get)
}

/// The uuid fence's current limit (from the environment).
pub fn uuid_limit() -> Limit {
  let #(uuid, _ip) = limits()
  uuid
}

/// The IP fence's current limit (from the environment).
pub fn ip_limit() -> Limit {
  let #(_uuid, ip) = limits()
  ip
}

/// The configuration rule, with the environment lookup injected so it is
/// testable without mutating the process environment. An unparsable or
/// non-positive number falls back to that limit's default: a typo in compose
/// must not switch a fence off (or on) silently.
pub fn limits_from(get: fn(String) -> Option(String)) -> #(Limit, Limit) {
  #(
    Limit(
      hits: limit_hits(get, uuid_limit_env, default_uuid_limit.hits),
      window_seconds: limit_hits(
        get,
        uuid_window_env,
        default_uuid_limit.window_seconds,
      ),
    ),
    Limit(
      hits: limit_hits(get, ip_limit_env, default_ip_limit.hits),
      window_seconds: limit_hits(
        get,
        ip_window_env,
        default_ip_limit.window_seconds,
      ),
    ),
  )
}

fn limit_hits(
  get: fn(String) -> Option(String),
  key: String,
  default: Int,
) -> Int {
  case get(key) {
    option.Some(value) ->
      case int.parse(string.trim(value)) {
        Ok(number) if number > 0 -> number
        _ -> default
      }
    option.None -> default
  }
}

// ---------- the decision, pure ----------

/// The fixed window `now` falls in.
pub fn window_of(limit: Limit, now: Int) -> Int {
  now / limit.window_seconds
}

/// Decide the hit that would be number `hits_so_far + 1` in this window, and
/// return the count to store. Pure: the table layer below is the only thing
/// that mutates, so the rule is testable without a database, a clock or a
/// process.
pub fn evaluate(limit: Limit, now: Int, hits_so_far: Int) -> #(Int, Decision) {
  let count = hits_so_far + 1
  case count <= limit.hits {
    True -> #(count, Allowed)
    // The window's edge is the moment the counter is forgotten, so that is
    // when the caller may retry. Never 0: a `Retry-After: 0` reads as "go now".
    False -> #(
      count,
      Limited(
        retry_after_seconds: limit.window_seconds - now % limit.window_seconds,
      ),
    )
  }
}

// ---------- the table ----------

/// Create the limiter table if it is not there yet.
///
/// `main` calls this before the server starts (so a broken setup fails loudly at
/// boot rather than at the first request) and `hit` calls it again defensively:
/// losing that race is handled in the FFI, where creating a table that already
/// exists is not an error.
pub fn setup() -> Nil {
  setup_table()
}

/// Count one hit for `key` and decide. Keys must be namespaced by the caller
/// ("uuid-…", "ip-…").
pub fn hit(key: String, limit: Limit, now: Int) -> Decision {
  setup()
  let window_key = #(key, window_of(limit, now))
  // One atomic read-modify-write: the count this hit makes it, with the row
  // created at 0 if absent. No lock, no lost update, no race between two
  // concurrent requests for the same key.
  let hits_so_far = bump(window_key) - 1
  let #(_stored, decision) = evaluate(limit, now, hits_so_far)
  sweep_if_busy(window_of(limit, now))
  decision
}

/// Forget every window older than `window`. Rows from a past window are never
/// read again (the window is part of the key), so they are pure garbage; this
/// keeps the table's size proportional to the traffic of one window rather than
/// to the process's uptime.
pub fn sweep(window: Int) -> Nil {
  sweep_rows(window)
}

/// Live rows, for tests and for eyeballing the limiter. Garbage after the last
/// sweep included.
pub fn size() -> Int {
  table_size()
}

fn sweep_if_busy(window: Int) -> Nil {
  case size() > sweep_threshold {
    True -> sweep(window)
    False -> Nil
  }
}

/// Forget everything. Not used by the request path at all: tests use it to get a
/// clean slate, and it doubles as the manual "unblock a burst" switch.
pub fn reset() -> Nil {
  clear_table()
}

// ---------- the Erlang bits ----------
// One row per (key, window). The four functions live in throttle_ffi.erl
// because each needs an atom/option/match-spec argument or an exception guard
// that Gleam cannot express — see that file.

@external(erlang, "throttle_ffi", "setup")
fn setup_table() -> Nil

/// Insert-or-increment; returns the row's count after this hit.
@external(erlang, "throttle_ffi", "hit")
fn bump(key: #(String, Int)) -> Int

@external(erlang, "throttle_ffi", "sweep")
fn sweep_rows(window: Int) -> Nil

@external(erlang, "throttle_ffi", "size")
fn table_size() -> Int

@external(erlang, "throttle_ffi", "clear")
fn clear_table() -> Nil
