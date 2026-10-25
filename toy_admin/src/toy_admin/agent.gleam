//// The agent API (agent drafts, 2026-10-25) — the local agent's narrow door.
////
////   GET  /api/agent/schedule   the calendar, read-only (published AND drafts)
////   POST /api/agent/puzzle     leave an UNDATED draft for a human to approve
////
//// Who is on the other side: a local agent (Hermes) running in its own
//// container on another docker network, inside the box. It has no browser and
//// never passes Cloudflare Access, so it cannot use /api/admin/* — but it must
//// be able to read the calendar (draw something that fits) and to leave a draft
//// behind. That is the whole surface: TWO routes, one shared secret, no
//// scheduling rights.
////
//// The fence (AGENT_API_KEY)
//// -------------------------
//// A shared bearer key: `Authorization: Bearer <key>`. The configuration is read
//// ONCE at boot and carried in the app state (toy_admin.App.agent), not per
//// request: there is exactly one key for the process's whole life, and the boot
//// warning below is the one place a missing key is allowed to surprise anyone.
////
////   - AGENT_API_KEY unset or blank  -> `Disabled`: every agent request is 401
////     `AgentAuth`, and main logs ONE warning at boot. Fail-safe in the same
////     direction as the access fence: a compose typo closes the door.
////   - AGENT_ID unset or blank       -> drafts are credited to `"agent"`. The
////     id is the audit trail ("who drew this?"), so a default word beats an
////     empty string, but it never stops the write.
////
//// The comparison is a plain `==`. That is NOT constant-time and is therefore
//// open to a timing side channel — accepted, and worth saying plainly: the
//// credential is a single shared secret on a local bridge network, reachable
//// only from inside the box, and the worst thing it can do is insert an UNDATED
//// draft that a human must date and approve through the admin UI. Should this
//// surface ever grow beyond the box or beyond drafts, constant-time comparison
//// (or real token rotation) is the shelf item, exactly as the JWT signature is
//// for access.gleam.
////
//// No scheduling (AgentNoScheduling)
//// --------------------------------
//// A non-empty `showDate` in an agent POST is a 400 `AgentNoScheduling`, not a
//// silently dropped field. The calendar is the human's decision: an agent that
//// believes it dated a puzzle, while the store quietly left it undated, would be
//// lied to by the API it talks to — and the human would never learn that an
//// agent tried to publish. Refuse, so the attempt is observable.
////
//// Order of operations (the admin routes' order, minus the pieces that do not
//// apply): fence -> method -> body decode (400 BadRequest) -> field validation,
//// collecting ALL problems into one envelope -> derivation -> store. Derivation
//// is this layer's job (store.update_puzzle's header): dots always arrive paired
//// with their re-derived fixture, and a drawing that derives nothing (fewer than
//// three dots) is 400 BadDrawing before the store hears about it.
////
//// Stats on the schedule rows: rows.gleam's calendar row, the same document
//// /api/admin/puzzles emits (Q23 numbers included). The agent needs to know how
//// a day is doing, not just that it exists.

import gleam/dynamic
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import sketch.{type Dot}
import toy_admin/derivation
import toy_admin/envelope
import toy_admin/fixture_json
import toy_admin/rows
import toy_admin/store
import wisp

/// The shared secret's variable name (compose passes it from a gitignored
/// .env — the same discipline as ADMIN_ACCESS_AUD: deployment identifiers do
/// not belong in a public repo).
pub const api_key_env = "AGENT_API_KEY"

/// The agent's name on every draft it draws.
pub const agent_id_env = "AGENT_ID"

/// The id used when AGENT_ID is unset: an honest word instead of "".
pub const default_agent_id = "agent"

/// The authorization header's prefix.
const bearer_prefix = "Bearer "

/// The agent surface's configuration, read once at boot.
pub type Config {
  /// No AGENT_API_KEY (or a blank one): every agent request is 401 AgentAuth.
  Disabled
  /// The key to require, and the id to credit drafts to.
  Enabled(key: String, agent_id: String)
}

/// The configuration rule, with the environment lookup injected so the rule is
/// testable without mutating the process environment (access.audience_from's
/// shape).
pub fn config_from(get: fn(String) -> Option(String)) -> Config {
  case get(api_key_env) {
    None -> Disabled
    Some(value) ->
      case string.trim(value) {
        "" -> Disabled
        key -> Enabled(key: key, agent_id: agent_id_from(get))
      }
  }
}

/// The agent id with the environment lookup injected (see config_from).
pub fn agent_id_from(get: fn(String) -> Option(String)) -> String {
  case get(agent_id_env) {
    None -> default_agent_id
    Some(value) ->
      case string.trim(value) {
        "" -> default_agent_id
        id -> id
      }
  }
}

/// The boot line, when there is one. `None` when the key is configured — the
/// dangerous state is the one worth a line (access.boot_warning's shape).
pub fn boot_warning(config: Config) -> Option(String) {
  case config {
    Enabled(key: _, agent_id: _) -> None
    Disabled ->
      Some(
        "toy_admin: "
        <> api_key_env
        <> " is unset — the agent routes are disabled: every request to"
        <> " /api/agent/* answers 401 AgentAuth. Set "
        <> api_key_env
        <> " (and "
        <> agent_id_env
        <> ") to the key the local agent presents to switch them on.",
      )
  }
}

/// Emit the boot warning exactly once, through the caller's logger. Main calls
/// this once before the listener starts.
pub fn announce_at_boot(config: Config, log: fn(String) -> Nil) -> Nil {
  case boot_warning(config) {
    Some(line) -> log(line)
    None -> Nil
  }
}

// ---------- the two routed shapes ----------

/// `/api/agent/schedule` — the calendar, read-only.
pub fn schedule(request: wisp.Request, config: Config) -> wisp.Response {
  fenced(request, config, fn() {
    case request.method {
      http.Get -> list_schedule()
      _ -> wisp.method_not_allowed([http.Get])
    }
  })
}

/// `/api/agent/puzzle` — leave an undated draft.
pub fn puzzle(request: wisp.Request, config: Config) -> wisp.Response {
  fenced(request, config, fn() {
    case request.method {
      http.Post -> create(request, config)
      _ -> wisp.method_not_allowed([http.Post])
    }
  })
}

/// The fence, in one place so no route can forget it. Before the method check:
/// an unkeyed caller learns nothing, not even which methods a path takes.
fn fenced(
  req: wisp.Request,
  config: Config,
  next: fn() -> wisp.Response,
) -> wisp.Response {
  case authorised(req, config) {
    True -> next()
    False ->
      envelope.error_response(401, ["AgentAuth"])
      |> wisp.set_header("www-authenticate", "Bearer")
  }
}

/// `Authorization: Bearer <key>`, compared with the configured key. See the
/// header on why a plain `==` is accepted here.
fn authorised(req: wisp.Request, config: Config) -> Bool {
  case config {
    Disabled -> False
    Enabled(key: expected, agent_id: _) ->
      case request.get_header(req, "authorization") {
        Error(_) -> False
        Ok(header) ->
          case bearer_key(header) {
            None -> False
            Some(presented) -> presented == expected
          }
      }
  }
}

fn bearer_key(header: String) -> Option(String) {
  // The scheme is case-insensitive (RFC 7235); the key is taken verbatim from
  // the header, so a key that happens to start with "Bearer" is still itself.
  case string.starts_with(string.lowercase(header), "bearer ") {
    False -> None
    True ->
      case
        string.drop_start(header, string.length(bearer_prefix)) |> string.trim
      {
        "" -> None
        key -> Some(key)
      }
  }
}

// ---------- GET /api/agent/schedule ----------

fn list_schedule() -> wisp.Response {
  let path = store.path_from_env()
  case store.list_puzzles(path) {
    Error(_) -> envelope.error_response(500, ["StoreError"])
    Ok(puzzles) ->
      case rows.calendar_rows(path, puzzles) {
        Error(_) -> envelope.error_response(500, ["StoreError"])
        Ok(documents) ->
          envelope.ok_with([
            #("rows", json.array(documents, of: fn(document) { document })),
          ])
      }
  }
}

// ---------- POST /api/agent/puzzle ----------

fn create(request: wisp.Request, config: Config) -> wisp.Response {
  let agent_id = case config {
    Disabled -> default_agent_id
    Enabled(key: _, agent_id: agent_id) -> agent_id
  }
  wisp.require_string_body(request, fn(body) {
    case parse_draft(body) {
      Error(_) -> envelope.error_response(400, ["BadRequest"])
      Ok(draft) ->
        case validated(draft) {
          Error(problems) -> envelope.error_response(400, problems)
          Ok(#(name, dots)) -> save_draft(name, dots, agent_id)
        }
    }
  })
}

/// The agent body's rules. All problems are collected into one envelope, in
/// field order (the admin routes' rule): AgentNoScheduling, BadName, BadDrawing.
fn validated(draft: Draft) -> Result(#(String, List(Dot)), List(String)) {
  let scheduling = case draft.show_date {
    None -> Ok(Nil)
    Some(value) ->
      case string.trim(value) {
        // A blank date is "not picked yet" — the editor sends both fields, and
        // for an agent that is the only legal state (see the header).
        "" -> Ok(Nil)
        _ -> Error("AgentNoScheduling")
      }
  }
  let name = case draft.name {
    None -> Error("BadName")
    Some(value) ->
      case string.trim(value) {
        "" -> Error("BadName")
        trimmed -> Ok(trimmed)
      }
  }
  // The drawing is decoded with the SAME decoder the admin editor's body uses
  // (fixture_json.dots_decoder): one spelling of `[[x, y], ...]`, both fences.
  let dots = case draft.dots {
    None -> Error("BadDrawing")
    Some(value) ->
      decode.run(value, fixture_json.dots_decoder())
      |> result.map_error(fn(_) { "BadDrawing" })
  }
  case scheduling, name, dots {
    Ok(_), Ok(name), Ok(dots) -> Ok(#(name, dots))
    _, _, _ ->
      list.append(
        problem_list(scheduling),
        list.append(problem_list(name), problem_list(dots)),
      )
      |> Error
  }
}

fn problem_list(result: Result(a, String)) -> List(String) {
  case result {
    Ok(_) -> []
    Error(problem) -> [problem]
  }
}

/// Derive, then insert the draft. Derived with the date it will have — the
/// empty string — so the stored fixture's embedded copy agrees with the row the
/// human will later date (a draft has no date yet, and the fixture says so).
fn save_draft(
  name: String,
  dots: List(Dot),
  agent_id: String,
) -> wisp.Response {
  let fixture = derivation.derive_fixture(dots, name, "")
  case derivation.is_degenerate(fixture) {
    True ->
      // Fewer than three dots: nothing renderable can come out. The fixture is
      // the observable, so the check is on it rather than a second dot count.
      envelope.error_response(400, ["BadDrawing"])
    False ->
      case
        store.insert_draft(
          store.path_from_env(),
          name,
          fixture_json.dots_to_string(dots),
          fixture_json.to_string(fixture),
          agent_id,
        )
      {
        Ok(row) ->
          envelope.created_with([
            #(
              "puzzle",
              json.object([
                #("id", json.int(row.id)),
                #("name", json.string(row.name)),
                #("status", json.string(row.status)),
              ]),
            ),
          ])
        Error(_) -> envelope.error_response(500, ["StoreError"])
      }
  }
}

// ---------- bodies ----------

/// The agent's create body, decoded leniently (admin.gleam's Draft): each field
/// is `None` when ABSENT, so "missing" can be told apart from "wrong type" — a
/// wrong type fails the whole document (400 BadRequest).
type Draft {
  Draft(
    name: Option(String),
    show_date: Option(String),
    dots: Option(dynamic.Dynamic),
  )
}

fn parse_draft(body: String) -> Result(Draft, Nil) {
  json.parse(body, using: draft_decoder())
  |> result.map_error(fn(_error) { Nil })
}

fn draft_decoder() -> decode.Decoder(Draft) {
  use name <- decode.optional_field(
    "name",
    None,
    decode.optional(decode.string),
  )
  use show_date <- decode.optional_field(
    "showDate",
    None,
    decode.optional(decode.string),
  )
  use dots <- decode.optional_field(
    "dots",
    None,
    decode.optional(decode.dynamic),
  )
  decode.success(Draft(name: name, show_date: show_date, dots: dots))
}
