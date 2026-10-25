//// toy_admin — the daily-puzzle backend (toy_admin/docs/PLAN-daily-puzzles.md).
////
//// Phase 2/3: the public API the toys call, on top of the SQLite store.
////
////   GET  /api/health            liveness, unchanged since Phase 1
////   GET  /api/puzzle/today      which puzzle to serve this visitor
////   POST /api/solve             record a solve
////   POST /api/attempts/abandon  record an abandoned attempt
////
//// Auth is Cloudflare Access at the tunnel (Q12). The PUBLIC routes above
//// authenticate nothing and must not start doing so — they serve a puzzle and
//// record an anonymous attempt. The /api/admin/* routes are fenced by
//// toy_admin/access.gleam before any work happens there: a Cf-Access-Jwt-
//// Assertion must be present, and when ADMIN_ACCESS_AUD is configured its
//// audience and expiry are checked. That module does NOT verify the token's
//// signature — its header explains why the tunnel is the wall and what the
//// shelf item is. The admin UI page (`GET /api/admin`) sits behind the SAME
//// fence as the JSON API it drives: the page is the control panel, not a
//// public artifact.
////
//// This is the umbrella's one Erlang-native piece (Q15): it runs inside the
//// Docker image on the Erlang target, listening on $PORT (default 8080) bound
//// to 0.0.0.0 so the tunnel ingress can resolve http://toy_admin:8080 across
//// home_server-network. No host ports are published (Q13).
////
//// Wire contract
//// --------------
//// The envelope itself lives in toy_admin/envelope.gleam (one module for both
//// the public and the admin routes). In brief: `{"status":"ok", ...}` on
//// success, `{"status":"none","fallback":true}` when nothing is published (Q5),
//// `{"status":"error","errors":[<stable names>]}` otherwise, and 204 with no
//// body for a delete. The error names are the client's vocabulary and part of
//// the contract; the list, with phase 4a's additions, is in envelope.gleam.
////
//// The timezone offset travels as `?tz=<minutes>` (the offset to ADD to UTC,
//// i.e. the NEGATION of JavaScript's `getTimezoneOffset()`), as an explicit
//// query parameter rather than a header. Rationale: it is part of the request's
//// meaning (the answer depends on it), it shows up in logs and in a curl
//// reproduction, and it cannot be mangled or dropped by an intermediary.
//// Absent means UTC (offset 0); unparsable is a 400, never a silent UTC guess.
////
//// Request order on the write routes is deliberate:
////   1. method,
////   2. IP fence (headers only — no body read, so an over-limit caller cannot
////      make the server parse a megabyte of junk),
////   3. body read + decode,
////   4. validation,
////   5. uuid fence,
////   6. the store.

import envoy
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import logging
import mist
import toy_admin/access
import toy_admin/admin
import toy_admin/admin_ui
import toy_admin/clock
import toy_admin/dates
import toy_admin/envelope
import toy_admin/fixture_json
import toy_admin/ingest
import toy_admin/store
import toy_admin/throttle
import wisp
import wisp/wisp_mist

const default_port = 8080

/// Placeholder until a later phase needs signed cookies/sessions. Nothing in the
/// current routes touches it; compose may override it with SECRET_KEY_BASE.
const dev_secret_key_base = "toy_admin-dev-key-base-no-sessions-yet"

/// The client's `moves` array on a solve: `[{"slot":0,"dir":1}, ...]`.
type Solve {
  Solve(uuid: String, puzzle_date: String, moves: List(ingest.Move))
}

/// The client's abandon payload: the same identity, the count instead of the
/// list (the toy sends the count it kept locally).
type Abandon {
  Abandon(uuid: String, puzzle_date: String, move_count: Int)
}

/// The app state: what the process knows that the request does not.
///
/// Today that is exactly the embedded admin UI bundle, read ONCE at boot
/// (admin_ui.gleam explains why boot and not per-request). It is a value passed
/// to `handle_request` rather than module-level state so the route tests can say
/// "the bundle was missing" — a boot state, not a filesystem accident.
pub type App {
  App(admin_ui: Option(String))
}

pub fn main() -> Nil {
  let port = port()
  let database = store.path_from_env()
  // Fail at boot, not at the first request: a store that cannot open is a
  // container that should not be accepting traffic.
  let assert Ok(Nil) = store.init(database)
  // One table for the limiter, created before any request can race for it.
  throttle.setup()
  // The one place the access fence's configuration speaks up: an unset
  // ADMIN_ACCESS_AUD downgrades the admin fence to presence-only, and that must
  // not be a silent surprise discovered during an incident (access.gleam).
  access.announce_at_boot(access.configured_audience(), fn(line) {
    logging.log(logging.Warning, line)
  })
  let app = load(admin_ui.bundle_path)
  let assert Ok(_) =
    fn(request: wisp.Request) { handle_request(request, app) }
    |> wisp_mist.handler(secret_key_base())
    |> mist.new
    |> mist.port(port)
    |> mist.bind("0.0.0.0")
    |> mist.start
  process.sleep_forever()
}

/// Read the embedded admin UI and build the boot state.
///
/// A missing bundle is not fatal: the API keeps working, the page answers 500,
/// and this warning is the one place the operator learns why. Same discipline as
/// access.announce_at_boot — a degraded mode announces itself once, at boot,
/// instead of being discovered from a broken page in a browser.
pub fn load(admin_ui_path: String) -> App {
  let bundle = admin_ui.load(admin_ui_path)
  case bundle {
    option.None ->
      logging.log(
        logging.Warning,
        "admin UI bundle not found at "
          <> admin_ui_path
          <> " — GET /api/admin will answer 500. Run scripts/build-admin-ui.sh, or build the image with its `ui` stage.",
      )
    option.Some(_) -> Nil
  }
  App(admin_ui: bundle)
}

/// The route table. Public so the wire contract can be driven from tests
/// through wisp's simulator (test/api_test.gleam, test/health_test.gleam) as well
/// as over HTTP.
pub fn handle_request(request: wisp.Request, app: App) -> wisp.Response {
  case wisp.path_segments(request) {
    ["api", "health"] ->
      wisp.require_method(request, http.Get, fn() { health() })
    ["api", "puzzle", "today"] ->
      wisp.require_method(request, http.Get, fn() { today(request) })
    ["api", "solve"] ->
      wisp.require_method(request, http.Post, fn() { solve(request) })
    ["api", "attempts", "abandon"] ->
      wisp.require_method(request, http.Post, fn() { abandon(request) })
    // Admin (phase 4a). Both handlers run the access fence FIRST — before the
    // method check, so an unfenced caller learns nothing, not even which
    // methods exist.
    ["api", "admin", "puzzles"] -> admin.puzzles(request)
    ["api", "admin", "puzzles", id] -> admin.puzzle(request, id)
    // Phase 4b: the admin UI itself and the derive-without-saving route. Same
    // fence, same order (the bundle is handed in, never read here).
    ["api", "admin"] -> admin.ui(request, app.admin_ui)
    ["api", "admin", ""] -> admin.ui(request, app.admin_ui)
    ["api", "admin", "preview"] -> admin.preview(request)
    _ -> wisp.not_found()
  }
}

fn health() -> wisp.Response {
  envelope.ok_empty()
}

// ---------- GET /api/puzzle/today ----------

fn today(request: wisp.Request) -> wisp.Response {
  let path = store.path_from_env()
  case tz_offset(request) {
    Error(_) -> envelope.error_response(400, ["BadTimezone"])
    Ok(tz) ->
      case store.newest_published(path) {
        Error(_) -> envelope.error_response(500, ["StoreError"])
        Ok(newest) -> {
          let local = dates.visitor_local_date(clock.now_seconds(), tz)
          case dates.serve_date(local, newest) {
            option.None -> envelope.none_response()
            option.Some(show_date) -> serve_puzzle(path, show_date)
          }
        }
      }
  }
}

fn serve_puzzle(path: String, show_date: String) -> wisp.Response {
  case store.puzzle_by_date(path, show_date) {
    Error(_) -> envelope.error_response(500, ["StoreError"])
    Ok(option.None) ->
      // Nothing is scheduled for that date (a gap in the calendar): the visitor
      // gets the fallback, exactly as if nothing were published.
      envelope.none_response()
    Ok(option.Some(puzzle)) -> serve_stored(puzzle)
  }
}

/// Turn a stored row into the served puzzle document. The row's JSON is
/// re-decoded rather than re-derived: serving must not run a DFT, and a row that
/// no longer decodes is a server-side fault — say so plainly instead of serving
/// half a puzzle.
fn serve_stored(puzzle: store.Puzzle) -> wisp.Response {
  case
    fixture_json.decode(puzzle.fixture_json),
    fixture_json.dots_from_json(puzzle.dots_json)
  {
    Ok(fixture), Ok(dots) ->
      json.object([
        #("status", json.string("ok")),
        #(
          "puzzle",
          fixture_json.public_puzzle(
            name: puzzle.name,
            show_date: puzzle.show_date,
            dots: dots,
            fixture: fixture,
          ),
        ),
      ])
      |> json.to_string
      |> wisp.json_response(200)
    _, _ -> envelope.error_response(500, ["StoreError"])
  }
}

/// The `tz` query parameter, in minutes-added-to-UTC. Absent means UTC.
fn tz_offset(request: wisp.Request) -> Result(Int, Nil) {
  case list.key_find(wisp.get_query(request), "tz") {
    Error(_) -> Ok(0)
    Ok(minutes) -> int.parse(minutes)
  }
}

// ---------- POST /api/solve ----------

fn solve(request: wisp.Request) -> wisp.Response {
  case ip_fence(request) {
    Error(retry_after) -> envelope.rate_limited(retry_after)
    Ok(Nil) ->
      wisp.require_string_body(request, fn(body) {
        case parse_solve(body) {
          Error(_) -> envelope.error_response(400, ["BadRequest"])
          Ok(Solve(uuid, puzzle_date, moves)) ->
            case ingest.validate_solve(uuid, puzzle_date, moves) {
              Error(problems) ->
                envelope.error_response(400, list.map(problems, problem_name))
              Ok(Nil) ->
                case uuid_fence(uuid) {
                  Error(retry_after) -> envelope.rate_limited(retry_after)
                  Ok(Nil) -> record_solve(uuid, puzzle_date, moves)
                }
            }
        }
      })
  }
}

fn record_solve(
  uuid: String,
  puzzle_date: String,
  moves: List(ingest.Move),
) -> wisp.Response {
  // The move list is stored verbatim (the plan's "solve rows carry the move
  // list"): the toy's replay/debug story depends on it, and it is already parsed
  // and validated by here.
  let moves_json = json.array(moves, of: move_to_json) |> json.to_string
  case
    store.attempt_record_solve(
      store.path_from_env(),
      uuid,
      puzzle_date,
      moves_json,
    )
  {
    Ok(Nil) -> envelope.ok_empty()
    Error(store.UnknownPuzzle(_)) ->
      envelope.error_response(404, ["UnknownPuzzle"])
    Error(store.InvalidMoves(_)) -> envelope.error_response(400, ["BadRequest"])
    Error(_) -> envelope.error_response(500, ["StoreError"])
  }
}

fn move_to_json(move: ingest.Move) -> json.Json {
  json.object([#("slot", json.int(move.slot)), #("dir", json.int(move.dir))])
}

// ---------- POST /api/attempts/abandon ----------

fn abandon(request: wisp.Request) -> wisp.Response {
  case ip_fence(request) {
    Error(retry_after) -> envelope.rate_limited(retry_after)
    Ok(Nil) ->
      wisp.require_string_body(request, fn(body) {
        case parse_abandon(body) {
          Error(_) -> envelope.error_response(400, ["BadRequest"])
          Ok(Abandon(uuid, puzzle_date, move_count)) ->
            case abandon_problems(uuid, puzzle_date, move_count) {
              [] ->
                case uuid_fence(uuid) {
                  Error(retry_after) -> envelope.rate_limited(retry_after)
                  Ok(Nil) -> record_abandon(uuid, puzzle_date, move_count)
                }
              problems -> envelope.error_response(400, problems)
            }
        }
      })
  }
}

fn record_abandon(
  uuid: String,
  puzzle_date: String,
  move_count: Int,
) -> wisp.Response {
  case
    store.attempt_record_abandon(
      store.path_from_env(),
      uuid,
      puzzle_date,
      move_count,
    )
  {
    Ok(Nil) -> envelope.ok_empty()
    Error(store.UnknownPuzzle(_)) ->
      envelope.error_response(404, ["UnknownPuzzle"])
    Error(_) -> envelope.error_response(500, ["StoreError"])
  }
}

/// The abandon payload's own rules: the identity is the same as a solve's, and
/// the count must be a number a player could have played — non-negative and
/// within the same cap as a move list (ingest.max_moves).
fn abandon_problems(
  uuid: String,
  puzzle_date: String,
  move_count: Int,
) -> List(String) {
  list.append(
    case ingest.is_uuid_v4(uuid) {
      True -> []
      False -> ["BadUuid"]
    },
    list.append(
      case dates.is_valid_date(puzzle_date) {
        True -> []
        False -> ["BadPuzzleDate"]
      },
      case move_count >= 0 && move_count <= ingest.max_moves {
        True -> []
        False -> ["TooManyMoves"]
      },
    ),
  )
}

// ---------- fences ----------

/// The outer fence: one address, so many requests per window. Headers only —
/// this runs before the body is read.
fn ip_fence(request: wisp.Request) -> Result(Nil, Int) {
  let key = "ip-" <> client_ip(request)
  case throttle.hit(key, throttle.ip_limit(), clock.now_seconds()) {
    throttle.Allowed -> Ok(Nil)
    throttle.Limited(retry_after_seconds) -> Error(retry_after_seconds)
  }
}

/// The inner fence: one uuid, so many solves per window. Needs the body, so it
/// runs after decoding.
fn uuid_fence(uuid: String) -> Result(Nil, Int) {
  case
    throttle.hit("uuid-" <> uuid, throttle.uuid_limit(), clock.now_seconds())
  {
    throttle.Allowed -> Ok(Nil)
    throttle.Limited(retry_after_seconds) -> Error(retry_after_seconds)
  }
}

/// The caller's address as the tunnel reports it. Cloudflare sets
/// `cf-connecting-ip`; behind a plain proxy it is the first entry of
/// `x-forwarded-for`. With neither (a direct local call) every such request
/// shares one bucket — a documented, accepted collapse: the fence is a nuisance
/// control, not a security boundary.
fn client_ip(request: wisp.Request) -> String {
  case request.get_header(request, "cf-connecting-ip") {
    Ok(ip) ->
      case string.trim(ip) {
        "" -> forwarded_ip(request)
        ip -> ip
      }
    Error(_) -> forwarded_ip(request)
  }
}

fn forwarded_ip(request: wisp.Request) -> String {
  case request.get_header(request, "x-forwarded-for") {
    Ok(value) ->
      case string.split(value, ",") {
        [first, ..] -> {
          let ip = string.trim(first)
          case ip {
            "" -> "unknown"
            ip -> ip
          }
        }
        [] -> "unknown"
      }
    Error(_) -> "unknown"
  }
}

// ---------- decoding ----------

fn parse_solve(body: String) -> Result(Solve, Nil) {
  json.parse(body, using: solve_decoder())
  |> result.map_error(fn(_error) { Nil })
}

fn solve_decoder() -> decode.Decoder(Solve) {
  use uuid <- decode.field("uuid", decode.string)
  use puzzle_date <- decode.field("puzzleDate", decode.string)
  use moves <- decode.field("moves", decode.list(move_decoder()))
  decode.success(Solve(uuid: uuid, puzzle_date: puzzle_date, moves: moves))
}

fn move_decoder() -> decode.Decoder(ingest.Move) {
  use slot <- decode.field("slot", decode.int)
  use dir <- decode.field("dir", decode.int)
  decode.success(ingest.Move(slot: slot, dir: dir))
}

fn parse_abandon(body: String) -> Result(Abandon, Nil) {
  json.parse(body, using: abandon_decoder())
  |> result.map_error(fn(_error) { Nil })
}

fn abandon_decoder() -> decode.Decoder(Abandon) {
  use uuid <- decode.field("uuid", decode.string)
  use puzzle_date <- decode.field("puzzleDate", decode.string)
  use move_count <- decode.field("moves", decode.int)
  decode.success(Abandon(
    uuid: uuid,
    puzzle_date: puzzle_date,
    move_count: move_count,
  ))
}

fn problem_name(problem: ingest.Problem) -> String {
  case problem {
    ingest.BadUuid -> "BadUuid"
    ingest.BadPuzzleDate -> "BadPuzzleDate"
    ingest.TooManyMoves(_) -> "TooManyMoves"
    ingest.BadSlot(_, _) -> "BadSlot"
    ingest.BadDirection(_, _) -> "BadDirection"
  }
}

// ---------- configuration ----------

/// PORT from the environment, 8080 when unset or unparsable.
fn port() -> Int {
  envoy.get("PORT")
  |> result.try(int.parse)
  |> result.unwrap(default_port)
}

fn secret_key_base() -> String {
  envoy.get("SECRET_KEY_BASE")
  |> result.unwrap(dev_secret_key_base)
}
