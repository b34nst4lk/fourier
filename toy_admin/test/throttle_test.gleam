//// The request throttle (PLAN-daily-puzzles.md §3, "throttle"): per-uuid
//// ~20/5min and per-IP 60/5min, both configurable, in memory only.
////
//// WHY: the solve endpoint is the only write surface a stranger can reach. No
//// accounts exist (Q16), so a uuid is a self-chosen identity — cheap to forge —
//// which is exactly why the IP limit exists as the outer fence and the uuid
//// limit as the inner one. Neither is a security control; both keep a stray
//// script from filling the attempts table.
////
//// WHY NO PERSISTENCE: a restart may forget the counters — the worst case is a
//// burst right after a deploy, and the tables are telemetry, not money.
////
//// WHY ETS AND NOT A GEN_SERVER: the limiter is one atomic increment per
//// request. `ets:update_counter/4` is atomic on its own and needs no mailbox,
//// no supervision tree and no queue to become a bottleneck; an actor would add
//// a serialisation point in front of every request for nothing. The table is
//// named, public and created once by `setup()` before the server starts (see
//// the note there on why creation is not race-tolerant).
////
//// WINDOWS ARE FIXED, NOT SLIDING: hits are counted per
//// `now / window_seconds` bucket. A fixed window lets a caller send 2x the
//// limit across a boundary; for keeping the attempts table sane that is a fine
//// trade for a counter you can delete by key.

import gleam/dict
import gleam/list
import gleam/option
import gleeunit/should
import helpers
import toy_admin/throttle

// ---------- the pure decision ----------

pub fn first_hits_of_a_window_pass_test() {
  let limit = throttle.Limit(hits: 3, window_seconds: 300)
  // hits_so_far 0, 1, 2 pass; the 4th (hits_so_far 3) is refused.
  list.each([0, 1, 2], fn(hits_so_far) {
    let #(_stored, decision) = throttle.evaluate(limit, 1_000_000, hits_so_far)
    should.equal(throttle.Allowed, decision)
  })
}

pub fn the_hit_that_exceeds_the_limit_is_refused_test() {
  let limit = throttle.Limit(hits: 3, window_seconds: 300)
  let #(_stored, decision) = throttle.evaluate(limit, 1_000_000, 3)
  should.equal(throttle.Limited(retry_after_seconds: 200), decision)
}

pub fn evaluate_increments_the_count_test() {
  let limit = throttle.Limit(hits: 3, window_seconds: 300)
  let #(stored, _decision) = throttle.evaluate(limit, 1_000_000, 7)
  should.equal(8, stored)
}

pub fn retry_after_points_at_the_window_edge_test() {
  let limit = throttle.Limit(hits: 3, window_seconds: 300)
  // Window boundaries fall on multiples of 300: at 1_000_000 (a boundary) the
  // caller may retry the whole window away; one second before the edge, one
  // second.
  let #(_, at_edge) = throttle.evaluate(limit, 1_000_200, 3)
  should.equal(throttle.Limited(retry_after_seconds: 300), at_edge)
  let #(_, near_edge) = throttle.evaluate(limit, 1_000_499, 3)
  should.equal(throttle.Limited(retry_after_seconds: 1), near_edge)
}

pub fn counters_are_scoped_to_one_window_test() {
  let limit = throttle.Limit(hits: 3, window_seconds: 300)
  // Same key, next window: the count starts over, so a hit that was over the
  // limit at 1_000_299 is allowed again at 1_000_300.
  let #(_stored, previous_window) = throttle.evaluate(limit, 1_000_499, 3)
  should.equal(throttle.Limited(retry_after_seconds: 1), previous_window)
  let #(stored, next_window) = throttle.evaluate(limit, 1_000_500, 0)
  should.equal(throttle.Allowed, next_window)
  should.equal(1, stored)
}

pub fn a_zero_limit_refuses_everything_test() {
  // Literal reading, and the documented way to switch a limit off is a huge
  // number, not zero (0 reads as "no hits allowed" — pinning it here so nobody
  // flips the meaning later).
  let limit = throttle.Limit(hits: 0, window_seconds: 300)
  let #(stored, decision) = throttle.evaluate(limit, 1_000_000, 0)
  should.equal(1, stored)
  // 1_000_000 is 100s into its window: 200s to the edge.
  should.equal(throttle.Limited(retry_after_seconds: 200), decision)
}

// ---------- configuration ----------

pub fn limits_default_to_twenty_per_five_minutes_and_sixty_per_ip_test() {
  let #(uuid, ip) = throttle.limits_from(fn(_key) { option.None })
  should.equal(throttle.Limit(hits: 20, window_seconds: 300), uuid)
  should.equal(throttle.Limit(hits: 60, window_seconds: 300), ip)
}

pub fn limits_read_the_environment_test() {
  let env =
    dict.from_list([
      #("THROTTLE_UUID_LIMIT", "5"),
      #("THROTTLE_UUID_WINDOW_SECONDS", "60"),
      #("THROTTLE_IP_LIMIT", "3"),
      #("THROTTLE_IP_WINDOW_SECONDS", "10"),
    ])
  let #(uuid, ip) = throttle.limits_from(fn(key) { lookup(env, key) })
  should.equal(throttle.Limit(hits: 5, window_seconds: 60), uuid)
  should.equal(throttle.Limit(hits: 3, window_seconds: 10), ip)
}

pub fn limits_ignore_unparsable_or_non_positive_values_test() {
  // A typo in compose must not silently switch the fence off (or on): fall back
  // to the default and keep serving.
  let env =
    dict.from_list([
      #("THROTTLE_UUID_LIMIT", "lots"),
      #("THROTTLE_UUID_WINDOW_SECONDS", ""),
      #("THROTTLE_IP_LIMIT", "-3"),
      #("THROTTLE_IP_WINDOW_SECONDS", "0"),
    ])
  let #(uuid, ip) = throttle.limits_from(fn(key) { lookup(env, key) })
  should.equal(throttle.default_uuid_limit, uuid)
  should.equal(throttle.default_ip_limit, ip)
}

pub fn limits_read_the_real_environment_test() {
  // The one test with a real `os:getenv`: it ties `limits()` to the rule above.
  helpers.set_env("THROTTLE_UUID_LIMIT", "7")
  helpers.set_env("THROTTLE_IP_WINDOW_SECONDS", "45")
  let #(uuid, ip) = throttle.limits()
  helpers.set_env("THROTTLE_UUID_LIMIT", "20")
  helpers.set_env("THROTTLE_IP_WINDOW_SECONDS", "300")
  should.equal(throttle.Limit(hits: 7, window_seconds: 300), uuid)
  should.equal(throttle.Limit(hits: 60, window_seconds: 45), ip)
}

// ---------- the table ----------

pub fn hits_count_up_and_stop_at_the_limit_test() {
  let limit = throttle.Limit(hits: 3, window_seconds: 300)
  should.equal(throttle.Allowed, hit("ip-1.2.3.4", limit, 1_000_000))
  should.equal(throttle.Allowed, hit("ip-1.2.3.4", limit, 1_000_001))
  should.equal(throttle.Allowed, hit("ip-1.2.3.4", limit, 1_000_002))
  // 1_000_003 sits 103s into its 300s window: 197s to the edge.
  should.equal(
    throttle.Limited(retry_after_seconds: 197),
    hit("ip-1.2.3.4", limit, 1_000_003),
  )
}

pub fn sweep_drops_rows_from_past_windows_test() {
  // Rows are {Key, Window} -> Count; a row from a window before the current one
  // can never be read again, so sweeping keeps the table's size proportional to
  // one window's traffic instead of the process's uptime.
  throttle.reset()
  let limit = throttle.Limit(hits: 5, window_seconds: 300)
  list.each(["uuid-x", "uuid-y", "uuid-z"], fn(key) {
    let _ = hit(key, limit, 0)
  })
  should.equal(3, throttle.size())
  throttle.sweep(1)
  should.equal(0, throttle.size())
}

pub fn keys_do_not_share_a_counter_test() {
  let limit = throttle.Limit(hits: 1, window_seconds: 300)
  should.equal(throttle.Allowed, hit("uuid-a", limit, 1_000_000))
  should.equal(throttle.Allowed, hit("uuid-b", limit, 1_000_000))
  should.equal(
    throttle.Limited(retry_after_seconds: 200),
    hit("uuid-a", limit, 1_000_000),
  )
}

pub fn the_table_forgets_the_previous_window_test() {
  let limit = throttle.Limit(hits: 1, window_seconds: 300)
  should.equal(throttle.Allowed, hit("uuid-c", limit, 1_000_000))
  // 200s into the same 300s window: refused, 100s to wait.
  should.equal(
    throttle.Limited(retry_after_seconds: 100),
    hit("uuid-c", limit, 1_000_100),
  )
  should.equal(throttle.Allowed, hit("uuid-c", limit, 1_000_300))
}

// ---------- helpers ----------

fn lookup(
  env: dict.Dict(String, String),
  key: String,
) -> option.Option(String) {
  case dict.get(env, key) {
    Ok(value) -> option.Some(value)
    Error(_) -> option.None
  }
}

fn hit(key: String, limit: throttle.Limit, now: Int) -> throttle.Decision {
  throttle.hit(key, limit, now)
}
