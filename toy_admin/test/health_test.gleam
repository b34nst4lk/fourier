//// The one shipped route (Phase 1 scaffold): GET /api/health -> 200
//// {"status":"ok"} JSON. Driven through wisp's simulator, so the route is
//// pinned without a socket; the container boot check proves it over HTTP.

import gleam/http
import gleam/list
import gleeunit/should
import helpers
import toy_admin
import wisp/simulate

pub fn health_returns_ok_json_test() {
  let response =
    simulate.request(http.Get, "/api/health")
    |> toy_admin.handle_request(helpers.app())

  should.equal(200, response.status)
  should.equal("{\"status\":\"ok\"}", simulate.read_body(response))
}

pub fn health_is_labelled_json_test() {
  let response =
    simulate.request(http.Get, "/api/health")
    |> toy_admin.handle_request(helpers.app())

  should.equal(
    Ok("application/json; charset=utf-8"),
    list.key_find(response.headers, "content-type"),
  )
}

pub fn health_rejects_other_methods_test() {
  let response =
    simulate.request(http.Post, "/api/health")
    |> toy_admin.handle_request(helpers.app())

  should.equal(405, response.status)
}

pub fn unknown_routes_are_not_found_test() {
  let response =
    simulate.request(http.Get, "/api/nope")
    |> toy_admin.handle_request(helpers.app())

  should.equal(404, response.status)
  should.equal("Not found", simulate.read_body(response))
}
