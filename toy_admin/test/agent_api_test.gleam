//// The agent API (agent drafts, 2026-10-25): the key fence, the schedule read,
//// and the undated-draft write.
////
//// Why this surface exists: a local agent (Hermes) draws puzzle shapes and
//// leaves them as DRAFTS; a human approves and dates them through the admin UI.
//// So the agent's fence is not the admin's: no Cloudflare Access in front of it
//// (the agent is on another docker network, inside the box, and has no browser),
//// and no scheduling rights either — an agent that tries to set a show date is
//// refused outright (`AgentNoScheduling`), because the calendar is the human's
//// decision, not something to be silently dropped.
////
//// Everything goes through wisp's simulator against the real route table and a
//// real SQLite file, like admin_api_test: the fence and the routes are only real
//// if the thing that ships is what is driven.

import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import helpers
import toy_admin
import toy_admin/agent
import toy_admin/derivation
import toy_admin/fixture_json
import toy_admin/store
import toy_admin/throttle
import wisp
import wisp/simulate

const key = "test-agent-key"

const agent_id = "hermes"

/// The same hand-drawn triangle the admin tests use: it derives, so it is a
/// legal drawing, and its fixture is reproducible by the test.
const triangle = "[[0,0],[10,0],[10,10]]"

// ---------- the fence ----------

pub fn every_agent_route_is_401_when_no_key_is_configured_test() {
  // Unset AGENT_API_KEY means the agent surface is OFF, announced at boot. The
  // answer is the same 401 for every path and method, and it is the FIRST thing
  // that happens: an unkeyed caller learns nothing about which methods exist.
  fresh_agent_db("agent-fence-none")
  let app = agent_app(None)
  let requests = [
    #(http.Get, "/api/agent/schedule", None),
    #(http.Post, "/api/agent/puzzle", Some(draft_body("Snail", triangle))),
  ]
  list.each(requests, fn(one) {
    let #(method, path, body) = one
    let response = call(app, None, method, path, body)
    should.equal(401, response.status)
    should.equal(
      "{\"status\":\"error\",\"errors\":[\"AgentAuth\"]}",
      simulate.read_body(response),
    )
  })
}

pub fn a_configured_key_still_refuses_anything_but_the_right_bearer_test() {
  fresh_agent_db("agent-fence-key")
  let app = agent_app(Some(key))
  // Missing header, another scheme, the bare word, a wrong key, and a key that
  // is merely a prefix of the real one: all 401. A bearer comparison that
  // accepts a prefix would be a bug you could drive a truck through.
  let presented = [
    None,
    Some("Basic " <> key),
    Some("Bearer"),
    Some("Bearer "),
    Some("Bearer wrong-key"),
    Some("Bearer " <> key <> "-and-more"),
  ]
  list.each(presented, fn(header) {
    let response = call(app, header, http.Get, "/api/agent/schedule", None)
    should.equal(401, response.status)
    should.equal(
      "{\"status\":\"error\",\"errors\":[\"AgentAuth\"]}",
      simulate.read_body(response),
    )
  })
}

pub fn the_right_bearer_passes_the_fence_test() {
  fresh_agent_db("agent-fence-ok")
  let response =
    call(
      agent_app(Some(key)),
      Some(bearer()),
      http.Get,
      "/api/agent/schedule",
      None,
    )
  should.equal(200, response.status)
}

pub fn the_fence_runs_before_the_method_test() {
  // No token: 401 even on a path/method pair that would otherwise be a 405.
  fresh_agent_db("agent-fence-order")
  let unkeyed =
    call(agent_app(Some(key)), None, http.Get, "/api/agent/puzzle", None)
  should.equal(401, unkeyed.status)

  // With the token: 405, and the `allow` header names the one method.
  let allowed =
    call(
      agent_app(Some(key)),
      Some(bearer()),
      http.Get,
      "/api/agent/puzzle",
      None,
    )
  should.equal(405, allowed.status)
  should.equal("POST", header(allowed, "allow"))
}

// ---------- configuration ----------

pub fn an_unset_or_blank_key_disables_the_agent_routes_test() {
  should.equal(agent.Disabled, agent.config_from(fn(_key) { None }))
  should.equal(agent.config_from(fn(_key) { Some("   ") }), agent.Disabled)
  should.equal(
    agent.config_from(fn(name) {
      case name {
        "AGENT_API_KEY" -> Some("secret")
        _ -> None
      }
    }),
    agent.Enabled(key: "secret", agent_id: agent.default_agent_id),
  )
}

pub fn the_configured_agent_id_is_credited_and_falls_back_when_unset_test() {
  // AGENT_ID is the name on the draft ("who drew this?"); without one the
  // draft is still created, credited to the generic word rather than to "".
  let with_id =
    agent.config_from(fn(name) {
      case name {
        "AGENT_API_KEY" -> Some("secret")
        "AGENT_ID" -> Some(" hermes ")
        _ -> None
      }
    })
  should.equal(agent.Enabled(key: "secret", agent_id: "hermes"), with_id)
}

pub fn a_disabled_agent_announces_itself_at_boot_test() {
  // Same discipline as the access fence: a degraded mode says so once, through
  // the logger, instead of being discovered from a 401 in a log someone reads
  // later. The line names the variable that would switch it on.
  let warning = agent.boot_warning(agent.Disabled)
  let assert Some(line) = warning
  should.be_true(string.contains(line, "AGENT_API_KEY"))
  should.be_true(string.contains(line, "disabled"))

  // Configured: nothing to say.
  should.equal(
    None,
    agent.boot_warning(agent.Enabled(key: "secret", agent_id: "hermes")),
  )

  // And exactly one line reaches the log, through a mailbox (mutable where the
  // test body is not — access_test's shape).
  let logger = process.new_subject()
  agent.announce_at_boot(agent.Disabled, fn(line) { process.send(logger, line) })
  let assert Ok(one) = process.receive(logger, 0)
  should.equal(Some(one), warning)
  // ...and nothing else followed it.
  should.equal(Error(Nil), process.receive(logger, 0))

  // A configured key says nothing at all.
  let quiet = process.new_subject()
  agent.announce_at_boot(
    agent.Enabled(key: "secret", agent_id: "hermes"),
    fn(line) { process.send(quiet, line) },
  )
  should.equal(Error(Nil), process.receive(quiet, 0))
}

// ---------- GET /api/agent/schedule ----------

pub fn the_schedule_lists_published_and_draft_rows_with_stats_test() {
  let path = fresh_agent_db("agent-schedule")
  let assert Ok(published) =
    store.insert_puzzle(
      path,
      "Published",
      "2026-10-25",
      triangle,
      fixture_json.to_string(derivation.derive_fixture(
        [#(0.0, 0.0), #(10.0, 0.0), #(10.0, 10.0)],
        "Published",
        "2026-10-25",
      )),
    )
  let assert Ok(draft) =
    store.insert_draft(path, "Drawn", triangle, "{}", agent_id)
  let assert Ok(Nil) =
    store.attempt_record_solve(path, uuid(1), published.show_date, moves(3))
  let assert Ok(Nil) =
    store.attempt_record_abandon(path, uuid(2), published.show_date, 5)

  let response =
    call(
      agent_app(Some(key)),
      Some(bearer()),
      http.Get,
      "/api/agent/schedule",
      None,
    )
  should.equal(200, response.status)
  let assert Ok(rows) = schedule_rows(simulate.read_body(response))
  should.equal(
    [
      Row(
        id: published.id,
        name: "Published",
        show_date: "2026-10-25",
        status: store.status_published,
        creator: store.creator_human,
        attempts: 2,
        solves: 1,
        solve_pct: Some("50.0"),
        median_moves: Some(4.0),
      ),
      Row(
        id: draft.id,
        name: "Drawn",
        show_date: "",
        status: store.status_draft,
        creator: agent_id,
        attempts: 0,
        solves: 0,
        solve_pct: None,
        median_moves: None,
      ),
    ],
    rows,
  )
}

pub fn the_schedule_of_an_empty_calendar_is_an_empty_list_test() {
  fresh_agent_db("agent-schedule-empty")
  let response =
    call(
      agent_app(Some(key)),
      Some(bearer()),
      http.Get,
      "/api/agent/schedule",
      None,
    )
  should.equal(200, response.status)
  should.equal(Ok([]), schedule_rows(simulate.read_body(response)))
}

// ---------- POST /api/agent/puzzle ----------

pub fn an_agent_creates_an_undated_draft_test() {
  let path = fresh_agent_db("agent-create")
  let response =
    call(
      agent_app(Some(key)),
      Some(bearer()),
      http.Post,
      "/api/agent/puzzle",
      Some(draft_body("The Snail", triangle)),
    )
  should.equal(201, response.status)

  let assert Ok(created) = created_puzzle(simulate.read_body(response))
  should.equal("The Snail", created.name)
  should.equal(store.status_draft, created.status)

  // The row is a real draft: no date, the agent's id as creator, and the
  // fixture is the derivation of ITS dots (the route derived, the store stored).
  let assert Ok(Some(row)) = store.puzzle_by_id(path, created.id)
  should.equal("", row.show_date)
  should.equal(store.status_draft, row.status)
  should.equal(agent_id, row.creator)
  should.equal("The Snail", row.name)
  should.equal(
    fixture_json.to_string(derivation.derive_fixture(
      [#(0.0, 0.0), #(10.0, 0.0), #(10.0, 10.0)],
      "The Snail",
      "",
    )),
    row.fixture_json,
  )
}

pub fn a_draft_never_touches_the_schedule_test() {
  // The whole point of the draft: the serving ceiling is unmoved, so a draft
  // cannot be served to a visitor before a human approves it.
  let path = fresh_agent_db("agent-draft-ceiling")
  let _ =
    call(
      agent_app(Some(key)),
      Some(bearer()),
      http.Post,
      "/api/agent/puzzle",
      Some(draft_body("The Snail", triangle)),
    )
  should.equal(Ok(None), store.newest_published(path))
}

pub fn an_agent_that_sets_a_show_date_is_refused_test() {
  // Refuse, do not ignore: a silently dropped date would look like a scheduled
  // puzzle to the agent and like nothing at all to the human.
  let path = fresh_agent_db("agent-no-scheduling")
  let body =
    "{\"name\":\"The Snail\",\"showDate\":\"2026-11-01\",\"dots\":"
    <> triangle
    <> "}"
  let response =
    call(
      agent_app(Some(key)),
      Some(bearer()),
      http.Post,
      "/api/agent/puzzle",
      Some(body),
    )
  should.equal(400, response.status)
  should.equal(["AgentNoScheduling"], errors(simulate.read_body(response)))
  // Nothing was written.
  should.equal(Ok(0), store.count_puzzles(path))
}

pub fn a_blank_show_date_is_not_scheduling_test() {
  // The editor always sends both fields; blank is "not picked yet", which for
  // an agent is the only legal state. It is a draft, not a refusal.
  let path = fresh_agent_db("agent-blank-date")
  let body =
    "{\"name\":\"The Snail\",\"showDate\":\"\",\"dots\":" <> triangle <> "}"
  let response =
    call(
      agent_app(Some(key)),
      Some(bearer()),
      http.Post,
      "/api/agent/puzzle",
      Some(body),
    )
  should.equal(201, response.status)
  should.equal(Ok(1), store.count_puzzles(path))
}

pub fn an_agent_draft_needs_a_name_test() {
  fresh_agent_db("agent-bad-name")
  let response =
    call(
      agent_app(Some(key)),
      Some(bearer()),
      http.Post,
      "/api/agent/puzzle",
      Some(draft_body("   ", triangle)),
    )
  should.equal(400, response.status)
  should.equal(["BadName"], errors(simulate.read_body(response)))
}

pub fn an_agent_draft_needs_a_drawable_drawing_test() {
  fresh_agent_db("agent-bad-drawing")
  // Two dots cannot render: the fixture is degenerate, which is the observable
  // the admin's create path checks too.
  let response =
    call(
      agent_app(Some(key)),
      Some(bearer()),
      http.Post,
      "/api/agent/puzzle",
      Some(draft_body("Two Dots", "[[0,0],[10,10]]")),
    )
  should.equal(400, response.status)
  should.equal(["BadDrawing"], errors(simulate.read_body(response)))

  // ...and rubbish that is not a dot list at all is the same answer.
  let rubbish =
    call(
      agent_app(Some(key)),
      Some(bearer()),
      http.Post,
      "/api/agent/puzzle",
      Some(draft_body("Rubbish", "\"nope\"")),
    )
  should.equal(400, rubbish.status)
  should.equal(["BadDrawing"], errors(simulate.read_body(rubbish)))
}

pub fn an_agent_body_that_is_not_json_is_bad_request_test() {
  fresh_agent_db("agent-bad-request")
  let response =
    call(
      agent_app(Some(key)),
      Some(bearer()),
      http.Post,
      "/api/agent/puzzle",
      Some("not json at all"),
    )
  should.equal(400, response.status)
  should.equal(["BadRequest"], errors(simulate.read_body(response)))
}

pub fn a_body_with_two_problems_reports_both_test() {
  // The envelope's rule, kept here as on the admin routes: one round trip tells
  // the caller everything that is wrong with the FIELDS it sent.
  //
  // A bad drawing is absent from this list on purpose: a drawing that DECODES
  // but derives nothing (fewer than three dots) is a DERIVATION refusal, which
  // is a later step of the route order than field validation — the admin's
  // create path draws the same line. So a two-dot drawing is reported only once
  // the scheduling attempt and the name are fixed
  // (an_agent_draft_needs_a_drawable_drawing_test drives that case alone).
  fresh_agent_db("agent-two-problems")
  let body =
    "{\"name\":\"\",\"showDate\":\"2026-11-01\",\"dots\":[[0,0],[10,10]]}"
  let response =
    call(
      agent_app(Some(key)),
      Some(bearer()),
      http.Post,
      "/api/agent/puzzle",
      Some(body),
    )
  should.equal(400, response.status)
  should.equal(
    ["AgentNoScheduling", "BadName"],
    errors(simulate.read_body(response)),
  )
}

// ---------- infrastructure ----------

fn fresh_agent_db(label: String) -> String {
  let path = helpers.temp_db_path(label)
  let assert Ok(Nil) = store.init(path)
  helpers.set_env(store.database_path_env, path)
  throttle.reset()
  path
}

/// The app state a request runs against: no admin bundle, and the agent fence
/// in the mode the test is about (`None` = AGENT_API_KEY unset).
fn agent_app(key: Option(String)) -> toy_admin.App {
  let config = case key {
    None -> agent.Disabled
    Some(key) -> agent.Enabled(key: key, agent_id: agent_id)
  }
  toy_admin.App(admin_ui: None, agent: config)
}

fn bearer() -> String {
  "Bearer " <> key
}

fn call(
  app: toy_admin.App,
  presented: Option(String),
  method: http.Method,
  path: String,
  body: Option(String),
) -> wisp.Response {
  let base = simulate.request(method, path)
  let with_auth = case presented {
    Some(value) -> simulate.header(base, "authorization", value)
    None -> base
  }
  let with_body = case body {
    Some(body) -> simulate.string_body(with_auth, body)
    None -> with_auth
  }
  toy_admin.handle_request(with_body, app)
}

fn header(response: wisp.Response, name: String) -> String {
  case list.key_find(response.headers, name) {
    Ok(value) -> value
    Error(_) -> ""
  }
}

fn draft_body(name: String, dots: String) -> String {
  "{\"name\":\"" <> name <> "\",\"dots\":" <> dots <> "}"
}

/// A v4-shaped uuid, distinct per attempt (attempts upsert on uuid + date).
fn uuid(n: Int) -> String {
  "2f1c8e1a-1a2b-4c3d-8e4f-" <> int.to_string(100_000_000_000 + n)
}

fn moves(count: Int) -> String {
  let one = "{\"slot\":0,\"dir\":1}"
  "[" <> string.join(list.repeat(one, count), ",") <> "]"
}

// ---------- decoders ----------

type Row {
  Row(
    id: Int,
    name: String,
    show_date: String,
    status: String,
    creator: String,
    attempts: Int,
    solves: Int,
    solve_pct: Option(String),
    median_moves: Option(Float),
  )
}

fn schedule_rows(body: String) -> Result(List(Row), Nil) {
  json.parse(body, using: rows_decoder()) |> result_map_error()
}

fn rows_decoder() -> decode.Decoder(List(Row)) {
  use rows <- decode.field("rows", decode.list(row_decoder()))
  decode.success(rows)
}

fn row_decoder() -> decode.Decoder(Row) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use show_date <- decode.field("showDate", decode.string)
  use status <- decode.field("status", decode.string)
  use creator <- decode.field("creator", decode.string)
  use attempts <- decode.field("attempts", decode.int)
  use solves <- decode.field("solves", decode.int)
  use solve_pct <- decode.optional_field(
    "solvePct",
    None,
    decode.optional(decode.string),
  )
  use median_moves <- decode.optional_field(
    "medianMoves",
    None,
    decode.optional(decode.float),
  )
  decode.success(Row(
    id: id,
    name: name,
    show_date: show_date,
    status: status,
    creator: creator,
    attempts: attempts,
    solves: solves,
    solve_pct: solve_pct,
    median_moves: median_moves,
  ))
}

type Created {
  Created(id: Int, name: String, status: String)
}

fn created_puzzle(body: String) -> Result(Created, Nil) {
  json.parse(body, using: envelope_puzzle_decoder()) |> result_map_error()
}

fn envelope_puzzle_decoder() -> decode.Decoder(Created) {
  use puzzle <- decode.field("puzzle", created_decoder())
  decode.success(puzzle)
}

fn created_decoder() -> decode.Decoder(Created) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use status <- decode.field("status", decode.string)
  decode.success(Created(id: id, name: name, status: status))
}

fn errors(body: String) -> List(String) {
  case json.parse(body, using: errors_decoder()) {
    Ok(names) -> names
    Error(_) -> ["not an error envelope: " <> body]
  }
}

fn errors_decoder() -> decode.Decoder(List(String)) {
  use names <- decode.field("errors", decode.list(decode.string))
  decode.success(names)
}

fn result_map_error(result: Result(a, b)) -> Result(a, Nil) {
  case result {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}
