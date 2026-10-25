//// toy_admin — the daily-puzzle backend (toy_admin/docs/PLAN-daily-puzzles.md).
////
//// Phase 1 scaffold: one route, `GET /api/health`, answering
//// 200 {"status":"ok"}. Everything else 404s for now; admin and ingest routes
//// arrive in later phases. Auth is Cloudflare Access at the tunnel (Q12) —
//// nothing here does authentication, and it must not start doing so.
////
//// This is the umbrella's one Erlang-native piece (Q15): it runs inside the
//// Docker image on the Erlang target, listening on $PORT (default 8080) bound
//// to 0.0.0.0 so the tunnel ingress can resolve http://toy_admin:8080 across
//// home_server-network. No host ports are published (Q13).

import envoy
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/json
import gleam/result
import mist
import wisp
import wisp/wisp_mist

const default_port = 8080

/// Placeholder until Phase 2 needs signed cookies/sessions. Nothing in the
/// current routes touches it; compose may override it with SECRET_KEY_BASE.
const dev_secret_key_base = "toy_admin-dev-key-base-no-sessions-yet"

pub fn main() -> Nil {
  let port = port()
  let assert Ok(_) =
    handle_request
    |> wisp_mist.handler(secret_key_base())
    |> mist.new
    |> mist.port(port)
    |> mist.bind("0.0.0.0")
    |> mist.start
  process.sleep_forever()
}

/// The route table. Public so the wire contract can be driven from tests
/// through wisp's simulator (test/health_test.gleam) as well as over HTTP.
pub fn handle_request(request: wisp.Request) -> wisp.Response {
  case wisp.path_segments(request) {
    ["api", "health"] ->
      wisp.require_method(request, http.Get, fn() { health() })
    _ -> wisp.not_found()
  }
}

fn health() -> wisp.Response {
  json.object([#("status", json.string("ok"))])
  |> json.to_string
  |> wisp.json_response(200)
}

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
