//// The wire envelope, in one place (PLAN-daily-puzzles.md §8).
////
//// Every answer the backend produces is JSON with a `status` field:
////
////   200 {"status":"ok", ...}                 the work happened
////   201 {"status":"ok", ...}                 a resource was created
////   200 {"status":"none","fallback":true}   nothing published — the client
////                                           renders its built-in quaver (Q5)
////   204                                     deleted; deliberately NO body
////   4xx/5xx {"status":"error","errors":[<stable names>]}
////
//// The error names are the client's vocabulary (`BadUuid`, `BadPuzzleDate`,
//// `TooManyMoves`, `BadSlot`, `BadDirection`, `UnknownPuzzle`, `BadTimezone`,
//// `BadRequest`, `RateLimited`, `StoreError`, and phase 4a's `BadName`,
//// `BadDrawing`) and are part of the contract: the toy and the admin UI map
//// them to copy, so they never change silently.
////
//// Phase 4a moved these helpers out of toy_admin.gleam because the admin routes
//// (admin.gleam) answer in the same vocabulary as the public ones. One module,
//// not two dialects: a reviewer checking the contract checks this file.

import gleam/int
import gleam/json
import wisp

/// `{"status":"ok"}` at 200 — an action with nothing to say.
pub fn ok_empty() -> wisp.Response {
  json.object([#("status", json.string("ok"))])
  |> json.to_string
  |> wisp.json_response(200)
}

/// `{"status":"ok", <fields>}` at 200. Field order is the caller's.
pub fn ok_with(fields: List(#(String, json.Json))) -> wisp.Response {
  ok_response(200, fields)
}

/// `{"status":"ok", <fields>}` at 201, for a freshly created resource.
pub fn created_with(fields: List(#(String, json.Json))) -> wisp.Response {
  ok_response(201, fields)
}

fn ok_response(
  status: Int,
  fields: List(#(String, json.Json)),
) -> wisp.Response {
  json.object([#("status", json.string("ok")), ..fields])
  |> json.to_string
  |> wisp.json_response(status)
}

/// `{"status":"error","errors":[<names>]}`. More than one name is allowed on
/// purpose: a create body with an empty name AND an impossible date reports
/// both, so the editor can underline both fields in one round trip.
pub fn error_response(status: Int, errors: List(String)) -> wisp.Response {
  json.object([
    #("status", json.string("error")),
    #("errors", json.array(errors, of: json.string)),
  ])
  |> json.to_string
  |> wisp.json_response(status)
}

/// 429 with the wait advertised, so a well-behaved client can back off instead
/// of guessing.
pub fn rate_limited(retry_after_seconds: Int) -> wisp.Response {
  error_response(429, ["RateLimited"])
  |> wisp.set_header("retry-after", int.to_string(retry_after_seconds))
}

/// The plan's "nothing published" answer (Q5).
pub fn none_response() -> wisp.Response {
  json.object([
    #("status", json.string("none")),
    #("fallback", json.bool(True)),
  ])
  |> json.to_string
  |> wisp.json_response(200)
}
