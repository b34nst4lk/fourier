//// The public API (PLAN-daily-puzzles.md §2/§3): the three routes the toys call.
////
//// Everything here runs through wisp's simulator — no socket, no container — so
//// the wire contract (status codes, envelope, error names) is pinned by tests.
//// The store is a real SQLite file in `build/` (`DB_PATH` aimed per test), never
//// a mock: the routes' job is to translate, and the translation is only correct
//// if the thing it talks to is the thing that ships.
////
//// Envelope, in one place:
////   200 {"status":"ok", ...}      the work happened
////   200 {"status":"none","fallback":true}   nothing published (Q5 fallback)
////   4xx/5xx {"status":"error","errors":["<stable name>", ...]}
//// Error names are the client's vocabulary (the toy maps them to copy); they are
//// part of the contract, so they are asserted as strings here.

import gleam/dynamic/decode
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import helpers
import toy_admin
import toy_admin/clock
import toy_admin/dates
import toy_admin/store
import toy_admin/throttle
import wisp
import wisp/simulate

// Canonical lowercase v4 (RFC 4122): ingest.is_uuid_v4 accepts exactly this
// shape, so the tests must too.
const uuid = "2f1c8e1a-1a2b-4c3d-8e4f-0123456789ab"

const dots = "[[0.0,0.0],[10.0,0.0],[10.0,10.0]]"

const fixture =
  "{\"name\":\"Star\",\"showDate\":\"2026-10-25\",\"centroid\":[1.5,2.5],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":2,\"radius\":27.57,\"phase\":270.0}],\"extras\":[],\"target\":[[0.0,0.0],[1.5,2.5]]}"

// ---------- GET /api/puzzle/today ----------

pub fn today_with_nothing_published_reports_none_test() {
  // The client's fallback path (Q5): no puzzle at all is not an error.
  fresh_db("today-none")
  let response = get("/api/puzzle/today?tz=120")
  should.equal(200, response.status)
  should.equal(
    "{\"status\":\"none\",\"fallback\":true}",
    simulate.read_body(response),
  )
}

pub fn today_serves_the_puzzle_for_the_visitors_local_date_test() {
  let path = fresh_db("today-serves")
  let today = local_date(0)
  let assert Ok(_) = store.insert_puzzle(path, "Star", today, dots, fixture)

  let response = get("/api/puzzle/today?tz=0")
  should.equal(200, response.status)
  let assert Ok(#("ok", option.Some(#(show_date, dot_count)))) =
    json.parse(simulate.read_body(response), using: today_decoder())
  should.equal(today, show_date)
  should.equal(3, dot_count)
}

pub fn today_defaults_to_utc_without_a_tz_param_test() {
  // Absent offset = UTC, documented in the route. A wrong default would serve
  // tomorrow's puzzle to everyone west of Greenwich.
  let path = fresh_db("today-default-tz")
  let today = local_date(0)
  let assert Ok(_) = store.insert_puzzle(path, "Star", today, dots, fixture)

  let assert Ok(#("ok", option.Some(#(show_date, _)))) =
    json.parse(
      simulate.read_body(get("/api/puzzle/today")),
      using: today_decoder(),
    )
  should.equal(today, show_date)
}

pub fn today_never_serves_past_the_newest_published_test() {
  // Q11's never-past rule: the visitor's local date is later than the newest
  // published show_date, so the newest published one is served — not a hole.
  let path = fresh_db("today-never-past")
  let assert Ok(_) =
    store.insert_puzzle(path, "Older", "2026-01-01", dots, fixture)
  let assert Ok(_) =
    store.insert_puzzle(path, "Newest", "2026-01-02", dots, fixture)

  let assert Ok(#("ok", option.Some(#(show_date, _)))) =
    json.parse(
      simulate.read_body(get("/api/puzzle/today?tz=840")),
      using: today_decoder(),
    )
  should.equal("2026-01-02", show_date)
}

pub fn today_rejects_an_unparsable_tz_test() {
  fresh_db("today-bad-tz")
  let response = get("/api/puzzle/today?tz=tomorrow")
  should.equal(400, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"BadTimezone\"]}",
    simulate.read_body(response),
  )
}

pub fn today_is_get_only_test() {
  fresh_db("today-method")
  let response =
    simulate.request(http.Post, "/api/puzzle/today?tz=0")
    |> toy_admin.handle_request
  should.equal(405, response.status)
}

// ---------- POST /api/solve ----------

pub fn solve_records_a_solve_test() {
  let path = fresh_db("solve-ok")
  let assert Ok(_) =
    store.insert_puzzle(path, "Star", "2026-10-25", dots, fixture)

  let response =
    post("/api/solve", solve_body(uuid, "2026-10-25", solve_moves()))
  should.equal(200, response.status)
  should.equal("{\"status\":\"ok\"}", simulate.read_body(response))

  let assert Ok(option.Some(attempt)) =
    store.attempt_for(path, uuid, "2026-10-25")
  should.be_true(attempt.solved)
  should.equal(2, attempt.move_count)
  should.equal(option.Some(solve_moves()), attempt.moves_json)
}

pub fn solve_is_idempotent_test() {
  // The toy retries a save it is not sure about; the second record REPLACES the
  // first instead of failing or double-counting.
  let path = fresh_db("solve-resend")
  let assert Ok(_) =
    store.insert_puzzle(path, "Star", "2026-10-25", dots, fixture)

  let _ = post("/api/solve", solve_body(uuid, "2026-10-25", solve_moves()))
  let response =
    post("/api/solve", solve_body(uuid, "2026-10-25", solve_moves()))
  should.equal(200, response.status)
  let assert Ok(#(attempts, solves)) = store.stats(path, 1)
  should.equal(#(1, 1), #(attempts, solves))
}

pub fn solve_rejects_a_body_that_is_not_a_solve_test() {
  fresh_db("solve-bad-body")
  should.equal(400, post("/api/solve", "not json at all").status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"BadRequest\"]}",
    simulate.read_body(post("/api/solve", "{\"uuid\":42}")),
  )
}

pub fn solve_reports_every_validation_problem_test() {
  // Stable names, in validation order: record-level first, then moves by index.
  fresh_db("solve-problems")
  let body =
    "{\"uuid\":\"not-a-uuid\",\"puzzleDate\":\"2026-02-30\",\"moves\":[{\"slot\":0,\"dir\":1},{\"slot\":7,\"dir\":0}]}"
  let response = post("/api/solve", body)
  should.equal(400, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"BadUuid\",\"BadPuzzleDate\",\"BadSlot\",\"BadDirection\"]}",
    simulate.read_body(response),
  )
}

pub fn solve_caps_the_move_list_test() {
  fresh_db("solve-too-many")
  let moves = list.repeat("{\"slot\":0,\"dir\":1}", 501) |> json_array
  let body =
    "{\"uuid\":\""
    <> uuid
    <> "\",\"puzzleDate\":\"2026-10-25\",\"moves\":"
    <> moves
    <> "}"
  let response = post("/api/solve", body)
  should.equal(400, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"TooManyMoves\"]}",
    simulate.read_body(response),
  )
}

pub fn solve_for_an_unknown_date_is_not_found_test() {
  let path = fresh_db("solve-unknown")
  let assert Ok(_) =
    store.insert_puzzle(path, "Star", "2026-10-25", dots, fixture)

  let response =
    post("/api/solve", solve_body(uuid, "2026-10-26", solve_moves()))
  should.equal(404, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"UnknownPuzzle\"]}",
    simulate.read_body(response),
  )
}

pub fn solve_is_post_only_test() {
  fresh_db("solve-method")
  let response = get("/api/solve")
  should.equal(405, response.status)
}

// ---------- POST /api/attempts/abandon ----------

pub fn abandon_records_a_move_count_test() {
  let path = fresh_db("abandon-ok")
  let assert Ok(_) =
    store.insert_puzzle(path, "Star", "2026-10-25", dots, fixture)

  let response =
    post("/api/attempts/abandon", abandon_body(uuid, "2026-10-25", 4))
  should.equal(200, response.status)
  should.equal("{\"status\":\"ok\"}", simulate.read_body(response))

  let assert Ok(option.Some(attempt)) =
    store.attempt_for(path, uuid, "2026-10-25")
  should.equal(False, attempt.solved)
  should.equal(4, attempt.move_count)
  should.equal(option.None, attempt.moves_json)
}

pub fn abandon_rejects_a_negative_count_test() {
  fresh_db("abandon-negative")
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"TooManyMoves\"]}",
    simulate.read_body(post(
      "/api/attempts/abandon",
      abandon_body(uuid, "2026-10-25", -1),
    )),
  )
}

pub fn abandon_caps_the_count_at_the_server_max_test() {
  // Same bound as a solve's move list (ingest.max_moves): a count nobody could
  // have played is a client bug, not telemetry.
  fresh_db("abandon-cap")
  let over = 501
  let response =
    post("/api/attempts/abandon", abandon_body(uuid, "2026-10-25", over))
  should.equal(400, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"TooManyMoves\"]}",
    simulate.read_body(response),
  )
}

pub fn abandon_after_a_solve_leaves_the_solve_alone_test() {
  // The toy cannot abandon after solving (Q22), but a stale tab can still send
  // it. The store's guard wins and the route still answers ok: nothing for the
  // client to fix, and no reason to invent an error.
  let path = fresh_db("abandon-after-solve")
  let assert Ok(_) =
    store.insert_puzzle(path, "Star", "2026-10-25", dots, fixture)
  let _ = post("/api/solve", solve_body(uuid, "2026-10-25", solve_moves()))

  let response =
    post("/api/attempts/abandon", abandon_body(uuid, "2026-10-25", 9))
  should.equal(200, response.status)
  should.equal("{\"status\":\"ok\"}", simulate.read_body(response))

  let assert Ok(option.Some(attempt)) =
    store.attempt_for(path, uuid, "2026-10-25")
  should.be_true(attempt.solved)
  should.equal(2, attempt.move_count)
}

pub fn abandon_for_an_unknown_date_is_not_found_test() {
  let path = fresh_db("abandon-unknown")
  let assert Ok(_) =
    store.insert_puzzle(path, "Star", "2026-10-25", dots, fixture)

  let response =
    post("/api/attempts/abandon", abandon_body(uuid, "2026-10-26", 3))
  should.equal(404, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"UnknownPuzzle\"]}",
    simulate.read_body(response),
  )
}

// ---------- the throttle ----------

pub fn solve_is_throttled_per_uuid_test() {
  // The one integration test for the limiter: the route consults it, over-limit
  // is a 429 with a Retry-After, and the limit comes from the environment.
  let path = fresh_db("throttle-uuid")
  let assert Ok(_) =
    store.insert_puzzle(path, "Star", "2026-10-25", dots, fixture)
  helpers.set_env(throttle.uuid_limit_env, "2")

  let first = post("/api/solve", solve_body(uuid, "2026-10-25", solve_moves()))
  let second = post("/api/solve", solve_body(uuid, "2026-10-25", solve_moves()))
  let third = post("/api/solve", solve_body(uuid, "2026-10-25", solve_moves()))
  helpers.set_env(throttle.uuid_limit_env, "20")

  should.equal(200, first.status)
  should.equal(200, second.status)
  should.equal(429, third.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"RateLimited\"]}",
    simulate.read_body(third),
  )
  // Retry-After is seconds to the window's edge: real clock, so only its shape
  // is pinnable — a positive integer no larger than the window.
  let assert Ok(retry_after) = list.key_find(third.headers, "retry-after")
  let assert Ok(seconds) = int.parse(retry_after)
  should.be_true(seconds > 0)
  should.be_true(seconds <= 300)
  // One row: a re-sent solve REPLACES the player's row for that day rather than
  // adding one. The refused third request never reached the store at all.
  let assert Ok(#(attempts, solves)) = store.stats(path, 1)
  should.equal(#(1, 1), #(attempts, solves))
}

pub fn the_ip_fence_refuses_before_the_body_is_read_test() {
  // Order matters: an over-limit caller must not be able to make the server
  // parse (or reject) a megabyte of junk. The same non-JSON body is a 400 while
  // the caller is inside its budget and a 429 once it is not — which is only
  // possible if the fence answers before the body is read.
  fresh_db("throttle-order")
  helpers.set_env(throttle.ip_limit_env, "1")
  let first = post("/api/solve", "not json")
  let refused = post("/api/solve", "not json")
  helpers.set_env(throttle.ip_limit_env, "60")

  should.equal(400, first.status)
  should.equal(429, refused.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"RateLimited\"]}",
    simulate.read_body(refused),
  )
}

pub fn the_ip_fence_is_checked_on_every_write_route_test() {
  // The IP fence wraps both write routes; a single address cannot hammer either.
  fresh_db("throttle-ip")
  helpers.set_env(throttle.ip_limit_env, "1")
  let from = "203.0.113.9"

  let first =
    post_from(
      from,
      "/api/attempts/abandon",
      abandon_body(uuid, "2026-10-25", 1),
    )
  let second =
    post_from(from, "/api/solve", solve_body(uuid, "2026-10-25", solve_moves()))
  helpers.set_env(throttle.ip_limit_env, "60")

  // No puzzle exists, so the first request gets a 404 rather than a 429: the
  // fence let it through and the store had the last word.
  should.equal(404, first.status)
  should.equal(429, second.status)
}

// ---------- helpers ----------

/// A fresh database for this test, aimed at by the running routes.
///
/// The limiter is reset too: its table lives for the whole test VM, and one
/// test's counters must never decide another's.
fn fresh_db(label: String) -> String {
  let path = helpers.temp_db_path(label)
  let assert Ok(Nil) = store.init(path)
  helpers.set_env(store.database_path_env, path)
  throttle.reset()
  path
}

/// Today's date as the route computes it for `tz_offset_minutes`, read from the
/// same clock: nothing here is frozen, and a test that hard-coded a date would
/// start failing tomorrow.
fn local_date(tz_offset_minutes: Int) -> String {
  dates.visitor_local_date(clock.now_seconds(), tz_offset_minutes)
}

fn get(path: String) -> wisp.Response {
  simulate.request(http.Get, path) |> toy_admin.handle_request
}

fn post(path: String, body: String) -> wisp.Response {
  simulate.request(http.Post, path)
  |> simulate.string_body(body)
  |> toy_admin.handle_request
}

fn post_from(from: String, path: String, body: String) -> wisp.Response {
  simulate.request(http.Post, path)
  |> simulate.string_body(body)
  |> simulate.header("x-forwarded-for", from)
  |> toy_admin.handle_request
}

fn solve_moves() -> String {
  "[{\"slot\":0,\"dir\":1},{\"slot\":2,\"dir\":-1}]"
}

fn solve_body(uuid: String, puzzle_date: String, moves: String) -> String {
  "{\"uuid\":\""
  <> uuid
  <> "\",\"puzzleDate\":\""
  <> puzzle_date
  <> "\",\"moves\":"
  <> moves
  <> "}"
}

fn abandon_body(uuid: String, puzzle_date: String, moves: Int) -> String {
  "{\"uuid\":\""
  <> uuid
  <> "\",\"puzzleDate\":\""
  <> puzzle_date
  <> "\",\"moves\":"
  <> int.to_string(moves)
  <> "}"
}

fn json_array(items: List(String)) -> String {
  "[" <> string.join(items, ",") <> "]"
}

fn today_decoder() -> decode.Decoder(#(String, option.Option(#(String, Int)))) {
  use status <- decode.field("status", decode.string)
  use puzzle <- decode.field(
    "puzzle",
    decode.optional(puzzle_summary_decoder()),
  )
  decode.success(#(status, puzzle))
}

fn puzzle_summary_decoder() -> decode.Decoder(#(String, Int)) {
  use show_date <- decode.field("showDate", decode.string)
  use dots <- decode.field("dots", decode.list(decode.dynamic))
  decode.success(#(show_date, list.length(dots)))
}
