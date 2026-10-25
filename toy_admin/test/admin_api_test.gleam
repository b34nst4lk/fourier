//// The admin API (PLAN-daily-puzzles.md §2/§3/§4/§8, phase 4a): the fence, the
//// CRUD routes, and the Q23 stats numbers.
////
//// Same shape as api_test.gleam: everything goes through wisp's simulator
//// against the real route table and a real SQLite file — no mocks, because the
//// routes' job is translation and the translation is only right if the thing it
//// talks to is the thing that ships.
////
//// The fence matrix is driven HERE, through `toy_admin.handle_request`, not only
//// through access.check's own unit tests: a fence that is correct but not wired
//// into a route is not a fence.
////
//// ADMIN_ACCESS_AUD is process-global (env.get), so every test sets it
//// explicitly — blank for presence-only, the tag for the audience check — and no
//// test depends on what a previous one left behind.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleeunit/should
import helpers
import simplifile
import sketch
import toy_admin
import toy_admin/access
import toy_admin/admin_ui
import toy_admin/clock
import toy_admin/dates
import toy_admin/derivation
import toy_admin/fixture_json
import toy_admin/store
import toy_admin/throttle
import wisp
import wisp/simulate

const aud = "test-aud-tag"

const show_date = "2026-10-25"

/// A hand-drawn triangle, in the browser's own spelling (whole numbers where
/// whole): `JSON.stringify` emits ints, and the decoder accepts them.
const triangle = "[[0,0],[10,0],[10,10]]"

/// A four-point drawing, in the browser's spelling again, and far from the
/// triangle in shape — so "the fixture changed" can be asserted by equality
/// with the derivation of these very dots, not by "something moved".
const star_dots = "[[1,27.57],[-4,6.59],[6,2.93],[-14,0.54]]"

fn star_points() -> List(sketch.Dot) {
  [#(1.0, 27.57), #(-4.0, 6.59), #(6.0, 2.93), #(-14.0, 0.54)]
}

// ---------- the fence ----------

pub fn every_admin_route_is_401_without_a_token_test() {
  fresh_admin_db("admin-fence-none")
  // Presence-only mode: the token must still BE there. This is the safety
  // property — a misconfigured audience does not open the admin API.
  let requests = [
    #(http.Get, "/api/admin/puzzles", None),
    #(
      http.Post,
      "/api/admin/puzzles",
      Some(
        "{\"name\":\"S\",\"showDate\":\"2026-10-25\",\"dots\":"
        <> triangle
        <> "}",
      ),
    ),
    #(http.Get, "/api/admin/puzzles/1", None),
    #(http.Put, "/api/admin/puzzles/1", Some("{\"name\":\"S\"}")),
    #(http.Delete, "/api/admin/puzzles/1", None),
  ]
  list.each(requests, fn(one) {
    let #(method, path, body) = one
    let response = call(None, method, path, body)
    should.equal(401, response.status)
    should.equal(
      "{\"status\":\"error\",\"errors\":[\"Unauthorized\"]}",
      simulate.read_body(response),
    )
  })
}

pub fn an_unconfigured_audience_still_requires_a_token_test() {
  // ADMIN_ACCESS_AUD blank == unset == presence-only: the boot warning's mode.
  fresh_admin_db("admin-fence-presence")
  unconfigure_audience()

  let unauthorised = call(None, http.Get, "/api/admin/puzzles", None)
  should.equal(401, unauthorised.status)

  // ...and any present token passes, claims unchecked (the documented trade).
  let authorised =
    call(Some("not-even-a-jwt"), http.Get, "/api/admin/puzzles", None)
  should.equal(200, authorised.status)
}

pub fn a_wrong_audience_is_403_and_the_token_is_not_read_as_data_test() {
  fresh_admin_db("admin-fence-aud")
  configure_audience()
  let foreign = token("some-other-app", clock.now_seconds() + 300)
  let response = call(Some(foreign), http.Get, "/api/admin/puzzles", None)
  should.equal(403, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"Forbidden\"]}",
    simulate.read_body(response),
  )
}

pub fn an_expired_token_is_403_test() {
  fresh_admin_db("admin-fence-exp")
  configure_audience()
  let stale = token(aud, clock.now_seconds() - 5)
  let response = call(Some(stale), http.Get, "/api/admin/puzzles", None)
  should.equal(403, response.status)
}

pub fn a_good_token_passes_the_fence_test() {
  fresh_admin_db("admin-fence-good")
  configure_audience()
  let response = call(Some(good_token()), http.Get, "/api/admin/puzzles", None)
  should.equal(200, response.status)
  should.equal(
    "{\"status\":\"ok\",\"puzzles\":[]}",
    simulate.read_body(response),
  )
}

// ---------- POST /api/admin/puzzles ----------

pub fn create_derives_stores_and_returns_the_row_test() {
  let path = fresh_admin_db("admin-create")
  configure_audience()
  let response = post_puzzle(create_body("Star", show_date, star_dots))
  should.equal(201, response.status)

  let assert Ok(puzzle) = response_puzzle(simulate.read_body(response))
  should.be_true(puzzle.id > 0)
  should.equal("Star", puzzle.name)
  should.equal(show_date, puzzle.show_date)
  should.equal(star_points(), puzzle.dots)
  should.equal(puzzle.created_at, puzzle.updated_at)

  // The fixture in the response IS the derivation of the drawing (Q2/Q3): no
  // second, hand-maintained copy, and the browser's int coordinates read as
  // floats.
  let expected = derivation.derive_fixture(star_points(), "Star", show_date)
  should.equal(expected, puzzle.fixture)

  // And the store agrees with what was returned — the row is the authority.
  let assert Ok(Some(row)) = store.puzzle_by_id(path, puzzle.id)
  should.equal(fixture_json.to_string(expected), row.fixture_json)
  should.equal(fixture_json.dots_to_string(star_points()), row.dots_json)
}

pub fn create_refuses_a_blank_name_test() {
  fresh_admin_db("admin-create-name")
  configure_audience()
  let response = post_puzzle(create_body("   ", show_date, triangle))
  should.equal(400, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"BadName\"]}",
    simulate.read_body(response),
  )
}

pub fn create_refuses_a_missing_name_as_a_blank_name_test() {
  // A create body without `name` is a blank name, not a broken request: the
  // editor should underline the field, not show "something went wrong".
  fresh_admin_db("admin-create-no-name")
  configure_audience()
  let response =
    post_puzzle(
      "{\"showDate\":\"" <> show_date <> "\",\"dots\":" <> triangle <> "}",
    )
  should.equal(400, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"BadName\"]}",
    simulate.read_body(response),
  )
}

pub fn create_refuses_an_impossible_date_test() {
  fresh_admin_db("admin-create-date")
  configure_audience()
  let response = post_puzzle(create_body("Star", "2026-02-30", triangle))
  should.equal(400, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"BadPuzzleDate\"]}",
    simulate.read_body(response),
  )
}

pub fn create_reports_every_bad_field_in_one_envelope_test() {
  // The editor underlines both fields in one round trip.
  fresh_admin_db("admin-create-many")
  configure_audience()
  let response = post_puzzle("{\"name\":\"\",\"showDate\":\"nope\"}")
  should.equal(400, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"BadName\",\"BadPuzzleDate\",\"BadDrawing\"]}",
    simulate.read_body(response),
  )
}

pub fn create_refuses_a_degenerate_drawing_test() {
  fresh_admin_db("admin-create-degenerate")
  configure_audience()

  // Two dots: below the core's 3-dot gate, nothing renderable can come out.
  let two_dots = post_puzzle(create_body("Star", show_date, "[[0,0],[10,0]]"))
  should.equal(400, two_dots.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"BadDrawing\"]}",
    simulate.read_body(two_dots),
  )

  // Not pairs of numbers at all.
  let nonsense = post_puzzle(create_body("Star", show_date, "[[0,0],[10]]"))
  should.equal(400, nonsense.status)
  should.equal("BadDrawing", first_error(simulate.read_body(nonsense)))

  // Not a list.
  let not_a_list = post_puzzle(create_body("Star", show_date, "{\"x\":1}"))
  should.equal(400, not_a_list.status)
  should.equal("BadDrawing", first_error(simulate.read_body(not_a_list)))
}

pub fn create_refuses_a_duplicate_show_date_test() {
  let path = fresh_admin_db("admin-create-duplicate")
  configure_audience()
  let assert Ok(_) =
    store.insert_puzzle(path, "First", show_date, triangle, fixture_text())

  let response = post_puzzle(create_body("Second", show_date, triangle))
  should.equal(409, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"DuplicateShowDate\"]}",
    simulate.read_body(response),
  )
}

pub fn create_refuses_a_body_that_is_not_json_test() {
  fresh_admin_db("admin-create-body")
  configure_audience()
  let response = post_puzzle("not json")
  should.equal(400, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"BadRequest\"]}",
    simulate.read_body(response),
  )
}

// ---------- GET /api/admin/puzzles/<id> ----------

pub fn read_returns_the_full_row_for_the_editor_test() {
  let path = fresh_admin_db("admin-read")
  configure_audience()
  let assert Ok(row) =
    store.insert_puzzle(
      path,
      "Star",
      show_date,
      fixture_json.dots_to_string(star_points()),
      fixture_json.to_string(derivation.derive_fixture(
        star_points(),
        "Star",
        show_date,
      )),
    )

  let response =
    call(
      Some(good_token()),
      http.Get,
      "/api/admin/puzzles/" <> int.to_string(row.id),
      None,
    )
  should.equal(200, response.status)
  let assert Ok(puzzle) = response_puzzle(simulate.read_body(response))
  should.equal(row.id, puzzle.id)
  should.equal(star_points(), puzzle.dots)
  should.equal(
    derivation.derive_fixture(star_points(), "Star", show_date),
    puzzle.fixture,
  )
  should.equal(row.created_at, puzzle.created_at)
}

pub fn read_of_an_unknown_or_nonsense_id_is_404_test() {
  fresh_admin_db("admin-read-unknown")
  configure_audience()

  let absent =
    call(Some(good_token()), http.Get, "/api/admin/puzzles/999", None)
  should.equal(404, absent.status)
  should.equal("UnknownPuzzle", first_error(simulate.read_body(absent)))

  let nonsense =
    call(Some(good_token()), http.Get, "/api/admin/puzzles/tomorrow", None)
  should.equal(404, nonsense.status)
  should.equal("UnknownPuzzle", first_error(simulate.read_body(nonsense)))
}

// ---------- PUT /api/admin/puzzles/<id> ----------

pub fn update_a_name_only_keeps_the_drawing_and_the_numbers_test() {
  let path = fresh_admin_db("admin-update-name")
  configure_audience()
  let assert Ok(row) =
    store.insert_puzzle(
      path,
      "Star",
      show_date,
      fixture_json.dots_to_string(star_points()),
      fixture_json.to_string(derivation.derive_fixture(
        star_points(),
        "Star",
        show_date,
      )),
    )

  let response = put_puzzle(row.id, "{\"name\":\"The Star\"}")
  should.equal(200, response.status)
  let assert Ok(puzzle) = response_puzzle(simulate.read_body(response))
  should.equal("The Star", puzzle.name)
  should.equal(show_date, puzzle.show_date)
  should.equal(star_points(), puzzle.dots)

  // The numbers are untouched; the labels in the fixture's embedded copy are
  // rewritten so the stored document does not disagree with its row.
  let assert Ok(Some(stored)) = store.puzzle_by_id(path, row.id)
  let assert Ok(fixture) = fixture_json.decode(stored.fixture_json)
  should.equal("The Star", fixture.name)
  let expected = derivation.derive_fixture(star_points(), "The Star", show_date)
  should.equal(expected.dial, fixture.dial)
  should.equal(expected.target, fixture.target)
}

pub fn update_a_drawing_rederives_the_fixture_test() {
  let path = fresh_admin_db("admin-update-dots")
  configure_audience()
  let assert Ok(row) =
    store.insert_puzzle(path, "Star", show_date, triangle, fixture_text())

  // Same fixture document as create would build from the triangle, so the change
  // is visible: the star's dial geometry is nothing like a right triangle's.
  let before = fixture_json.decode(row.fixture_json)
  let assert Ok(before_fixture) = before

  let response = put_puzzle(row.id, "{\"dots\":" <> star_dots <> "}")
  should.equal(200, response.status)
  let assert Ok(puzzle) = response_puzzle(simulate.read_body(response))
  should.equal(star_points(), puzzle.dots)

  let expected = derivation.derive_fixture(star_points(), "Star", show_date)
  should.equal(expected, puzzle.fixture)
  should.be_true(before_fixture.dial != puzzle.fixture.dial)

  let assert Ok(Some(stored)) = store.puzzle_by_id(path, row.id)
  should.equal(fixture_json.to_string(expected), stored.fixture_json)
  should.equal(fixture_json.dots_to_string(star_points()), stored.dots_json)
}

pub fn update_allows_its_own_show_date_but_not_another_puzzles_test() {
  let path = fresh_admin_db("admin-update-collision")
  configure_audience()
  let assert Ok(first) =
    store.insert_puzzle(path, "First", "2026-10-01", triangle, fixture_text())
  let assert Ok(_) =
    store.insert_puzzle(path, "Second", "2026-10-02", triangle, fixture_text())

  // Its own date is not a collision with itself.
  let own =
    put_puzzle(first.id, "{\"showDate\":\"2026-10-01\",\"name\":\"First!\"}")
  should.equal(200, own.status)

  // Another puzzle's date is.
  let clash = put_puzzle(first.id, "{\"showDate\":\"2026-10-02\"}")
  should.equal(409, clash.status)
  should.equal("DuplicateShowDate", first_error(simulate.read_body(clash)))

  // And nothing changed under the refusal.
  let assert Ok(Some(stored)) = store.puzzle_by_id(path, first.id)
  should.equal("2026-10-01", stored.show_date)
  should.equal("First!", stored.name)
}

pub fn update_refuses_a_degenerate_drawing_and_keeps_the_row_test() {
  let path = fresh_admin_db("admin-update-degenerate")
  configure_audience()
  let assert Ok(row) =
    store.insert_puzzle(path, "Star", show_date, triangle, fixture_text())

  let response = put_puzzle(row.id, "{\"dots\":[[0,0],[1,1]]}")
  should.equal(400, response.status)
  should.equal(
    "{\"status\":\"error\",\"errors\":[\"BadDrawing\"]}",
    simulate.read_body(response),
  )

  let assert Ok(Some(stored)) = store.puzzle_by_id(path, row.id)
  should.equal(triangle, stored.dots_json)
}

pub fn update_of_an_unknown_id_is_404_test() {
  fresh_admin_db("admin-update-unknown")
  configure_audience()
  let response = put_puzzle(424_242, "{\"name\":\"Nope\"}")
  should.equal(404, response.status)
  should.equal("UnknownPuzzle", first_error(simulate.read_body(response)))
}

pub fn an_empty_update_is_a_no_op_test() {
  // The store's coherent no-op: nothing mentioned, nothing written.
  let path = fresh_admin_db("admin-update-noop")
  configure_audience()
  let assert Ok(row) =
    store.insert_puzzle(path, "Star", show_date, triangle, fixture_text())

  let response = put_puzzle(row.id, "{}")
  should.equal(200, response.status)
  let assert Ok(puzzle) = response_puzzle(simulate.read_body(response))
  should.equal(row.updated_at, puzzle.updated_at)
}

pub fn restating_the_same_values_is_also_a_no_op_test() {
  // `{}` is the obvious no-op; a body that re-sends what the row already says
  // is the same thing from the editor's point of view (it PUTs the whole form
  // it just loaded). Nothing changed -> nothing written -> `updated_at` still.
  // Needs a real second to be meaningful (store keeps wall-clock seconds).
  let path = fresh_admin_db("admin-update-restate")
  configure_audience()
  let assert Ok(row) =
    store.insert_puzzle(path, "Star", show_date, triangle, fixture_text())
  process.sleep(1050)

  let response =
    put_puzzle(
      row.id,
      "{\"name\":\"  Star  \",\"showDate\":\"" <> show_date <> "\"}",
    )
  should.equal(200, response.status)
  let assert Ok(puzzle) = response_puzzle(simulate.read_body(response))
  should.equal("Star", puzzle.name)
  should.equal(row.updated_at, puzzle.updated_at)
  let assert Ok(Some(stored)) = store.puzzle_by_id(path, row.id)
  should.equal(triangle, stored.dots_json)
}

// ---------- DELETE /api/admin/puzzles/<id> ----------

pub fn delete_removes_the_puzzle_but_keeps_its_telemetry_test() {
  let path = fresh_admin_db("admin-delete")
  configure_audience()
  let assert Ok(row) =
    store.insert_puzzle(path, "Star", show_date, triangle, fixture_text())
  let assert Ok(Nil) =
    store.attempt_record_solve(path, uuid(1), show_date, moves(4))

  let response =
    call(
      Some(good_token()),
      http.Delete,
      "/api/admin/puzzles/" <> int.to_string(row.id),
      None,
    )
  should.equal(204, response.status)
  should.equal("", simulate.read_body(response))

  let assert Ok(None) = store.puzzle_by_id(path, row.id)
  let gone =
    call(
      Some(good_token()),
      http.Get,
      "/api/admin/puzzles/" <> int.to_string(row.id),
      None,
    )
  should.equal(404, gone.status)

  // No FK, no cascade: history is not rewritten by a calendar edit.
  let assert Ok(#(attempts, _solves)) = store.stats(path, row.id)
  should.equal(1, attempts)
}

pub fn delete_of_an_unknown_id_is_404_test() {
  fresh_admin_db("admin-delete-unknown")
  configure_audience()
  let response =
    call(Some(good_token()), http.Delete, "/api/admin/puzzles/77", None)
  should.equal(404, response.status)
  should.equal("UnknownPuzzle", first_error(simulate.read_body(response)))
}

// ---------- GET /api/admin/puzzles (stats) ----------

pub fn the_list_is_newest_first_with_the_q23_numbers_test() {
  let path = fresh_admin_db("admin-list-stats")
  configure_audience()

  // Newest first: 01-03, 01-02, 01-01 whatever the insert order.
  let assert Ok(_oldest) =
    store.insert_puzzle(path, "Oldest", "2026-01-01", triangle, fixture_text())
  let assert Ok(newest) =
    store.insert_puzzle(path, "Newest", "2026-01-03", triangle, fixture_text())
  let assert Ok(middle) =
    store.insert_puzzle(path, "Middle", "2026-01-02", triangle, fixture_text())

  // Newest: two solves (7 and 14 moves) and two abandons (6 and 10 moves):
  //   attempts 4, solves 2, 50.0%, median of [6,7,10,14] = 8.5 (even -> mean).
  // An abandon counts with its own reported count (Q23), so the median is not
  // "the winners' median".
  seed_solve(path, uuid(11), newest.show_date, 7)
  seed_solve(path, uuid(12), newest.show_date, 14)
  seed_abandon(path, uuid(13), newest.show_date, 6)
  seed_abandon(path, uuid(14), newest.show_date, 10)

  // Middle: one solve (5 moves) and two abandons (3 and 9):
  //   attempts 3, solves 1, 33.3%, median of [3,5,9] = 5.0 (odd -> middle).
  seed_solve(path, uuid(21), middle.show_date, 5)
  seed_abandon(path, uuid(22), middle.show_date, 3)
  seed_abandon(path, uuid(23), middle.show_date, 9)

  // Oldest: untouched -> nulls, not zeros ("no data" is not "0%").

  let response = call(Some(good_token()), http.Get, "/api/admin/puzzles", None)
  should.equal(200, response.status)
  let assert Ok(#("ok", rows)) =
    json.parse(simulate.read_body(response), using: list_decoder())
  assert_row(rows, 0, "Newest", 4, 2, Some("50.0"), Some(8.5))
  assert_row(rows, 1, "Middle", 3, 1, Some("33.3"), Some(5.0))
  assert_row(rows, 2, "Oldest", 0, 0, None, None)
}

pub fn an_empty_calendar_lists_nothing_test() {
  fresh_admin_db("admin-list-empty")
  configure_audience()
  let response = call(Some(good_token()), http.Get, "/api/admin/puzzles", None)
  should.equal(200, response.status)
  should.equal(
    "{\"status\":\"ok\",\"puzzles\":[]}",
    simulate.read_body(response),
  )
}

pub fn the_list_serves_a_puzzle_the_public_route_can_read_test() {
  // The admin writes what the toy reads: one vocabulary end to end. A puzzle
  // created through the admin API for today is what /api/puzzle/today serves.
  fresh_admin_db("admin-list-serves")
  configure_audience()
  let today = today_date()
  let created = post_puzzle(create_body("Star", today, star_dots))
  should.equal(201, created.status)
  let assert Ok(puzzle) = response_puzzle(simulate.read_body(created))
  should.equal("Star", puzzle.name)

  let served =
    simulate.request(http.Get, "/api/puzzle/today?tz=0")
    |> toy_admin.handle_request(helpers.app())
  should.equal(200, served.status)
  let body = simulate.read_body(served)
  should.be_true(string.contains(body, "\"showDate\":\"" <> today <> "\""))
  should.be_true(string.contains(body, "\"name\":\"Star\""))
}

// ---------- methods ----------

pub fn the_collection_answers_405_with_an_accurate_allow_header_test() {
  fresh_admin_db("admin-methods")
  configure_audience()
  let response =
    call(Some(good_token()), http.Patch, "/api/admin/puzzles", None)
  should.equal(405, response.status)
  // wisp's plain-text 405, as on the public routes; the `allow` header must
  // advertise the methods this path really takes.
  should.equal("GET, POST", header(response, "allow"))

  let item = call(Some(good_token()), http.Patch, "/api/admin/puzzles/1", None)
  should.equal(405, item.status)
  should.equal("DELETE, GET, PUT", header(item, "allow"))
}

// ---------- phase 4b: the embedded admin UI + the preview route ----------

/// A stand-in for the bundled single file (scripts/build-admin-ui.sh's output).
/// Deliberately NOT read from `priv/`: the suite must not depend on the UI build
/// (the Docker test stage runs before the UI stage), and "verbatim" is a
/// property of the response, not of the file on disk.
const ui_html =
  "<!doctype html>\n<title>admin · puzzles</title>\n<p data-x=\"1\">ünïcode ✓ &amp; </p>\n"

fn ui_state() -> toy_admin.App {
  toy_admin.App(admin_ui: Some(ui_html))
}

pub fn the_admin_ui_is_fenced_like_the_api_it_drives_test() {
  fresh_admin_db("ui-fence")
  configure_audience()
  // The page and the preview are admin routes: no token, no answer. The fence
  // runs before the method check, so an unfenced caller cannot even learn that
  // /api/admin is a page rather than a JSON route.
  list.each(["/api/admin", "/api/admin/", "/api/admin/preview"], fn(path) {
    let response = call(None, http.Get, path, None)
    should.equal(401, response.status)
    should.equal(
      "{\"status\":\"error\",\"errors\":[\"Unauthorized\"]}",
      simulate.read_body(response),
    )
  })
}

pub fn the_admin_ui_is_served_verbatim_from_both_spellings_test() {
  fresh_admin_db("ui-serve")
  configure_audience()
  // `/api/admin` and `/api/admin/` are one page: a trailing slash is how a
  // browser spells a directory, and the Access policy covers the prefix.
  list.each(["/api/admin", "/api/admin/"], fn(path) {
    let response = call(Some(good_token()), http.Get, path, None)
    should.equal(200, response.status)
    should.equal(ui_html, simulate.read_body(response))
    should.be_true(string.starts_with(
      header(response, "content-type"),
      "text/html",
    ))
  })
}

pub fn a_failed_boot_read_is_a_500_not_a_blank_page_test() {
  // `load` already logged its one warning at boot; the route's job is to say
  // "broken build" plainly rather than serve half a page.
  fresh_admin_db("ui-missing")
  configure_audience()
  let response =
    call_with(
      toy_admin.App(admin_ui: None),
      Some(good_token()),
      http.Get,
      "/api/admin",
      None,
    )
  should.equal(500, response.status)
  // wisp's plain-text 500, like its plain-text 405: a browser asking for a page
  // has no use for the JSON envelope.
  should.equal("Internal server error", simulate.read_body(response))
}

pub fn the_admin_ui_takes_no_writes_test() {
  fresh_admin_db("ui-methods")
  configure_audience()
  let response = call(Some(good_token()), http.Post, "/api/admin", None)
  should.equal(405, response.status)
  should.equal("GET", header(response, "allow"))
}

pub fn the_bundle_is_read_from_disk_and_a_missing_file_is_not_an_error_test() {
  // The boot read, in isolation: bytes in, bytes out (no decoding, no
  // templating — the bundle is already a complete document) and `None`, not a
  // crash, when the build never ran.
  let path = helpers.temp_path("admin-ui") <> ".html"
  let assert Ok(Nil) = simplifile.write(path, ui_html)
  should.equal(Some(ui_html), admin_ui.load(path))
  should.equal(None, admin_ui.load(path <> ".absent"))
}

pub fn preview_derives_the_fixture_and_leaves_the_store_alone_test() {
  let path = fresh_admin_db("ui-preview")
  configure_audience()
  // A puzzle already occupies the date the admin is previewing for: a preview
  // is not a create, so the taken date is not a 409 and the row must not move.
  let created = post_puzzle(create_body("Star", show_date, star_dots))
  should.equal(201, created.status)
  let assert Ok(Some(before)) =
    store.puzzle_by_id(path, created_id(simulate.read_body(created)))

  let response =
    call(
      Some(good_token()),
      http.Post,
      "/api/admin/preview",
      Some(create_body("", show_date, triangle)),
    )
  should.equal(200, response.status)

  // The fixture is the create route's derivation, field for field: a preview
  // the admin reads and a save the toy reads are one document (asserted against
  // the derivation itself, not by counting keys). A blank name borrows the
  // date it was previewed for — the labels are the editor's, not the row's.
  let expected =
    derivation.derive_fixture(triangle_points(), show_date, show_date)
  let assert Ok(previewed) = response_fixture(simulate.read_body(response))
  should.equal(expected, previewed)

  should.equal(1, store.count_puzzles(path) |> result.unwrap(0))
  let assert Ok(Some(after)) = store.puzzle_by_id(path, before.id)
  should.equal(before.dots_json, after.dots_json)
  should.equal(before.fixture_json, after.fixture_json)
  should.equal(before.updated_at, after.updated_at)
}

pub fn preview_asks_for_a_drawing_but_not_for_a_name_or_a_date_test() {
  fresh_admin_db("ui-preview-bare")
  configure_audience()
  // Still drawing: no name, no date picked yet. The fixture is named "preview"
  // and dated empty — the editor shows it, the store never sees it.
  let response =
    call(
      Some(good_token()),
      http.Post,
      "/api/admin/preview",
      Some("{\"dots\":" <> triangle <> "}"),
    )
  should.equal(200, response.status)
  let assert Ok(previewed) = response_fixture(simulate.read_body(response))
  should.equal(
    derivation.derive_fixture(triangle_points(), "preview", ""),
    previewed,
  )

  // A name that is only spaces is a blank name (the create route's rule).
  let blank =
    call(
      Some(good_token()),
      http.Post,
      "/api/admin/preview",
      Some(create_body("   ", show_date, triangle)),
    )
  should.equal(200, blank.status)
  let assert Ok(named) = response_fixture(simulate.read_body(blank))
  should.equal(show_date, named.name)
}

pub fn preview_validates_the_drawing_and_the_date_like_create_test() {
  fresh_admin_db("ui-preview-bad")
  configure_audience()
  // Fewer than three dots: nothing renderable, exactly as on create.
  let thin = preview_of(create_body("S", show_date, "[[0,0],[10,0]]"))
  should.equal(400, thin.status)
  should.equal("BadDrawing", first_error(simulate.read_body(thin)))

  // A date that is present but impossible is a typo, not "not picked yet".
  let bad_date = preview_of(create_body("S", "2026-13-45", triangle))
  should.equal(400, bad_date.status)
  should.equal("BadPuzzleDate", first_error(simulate.read_body(bad_date)))

  // No drawing at all is the same BadDrawing as an unusable one.
  let none = preview_of("{\"name\":\"S\"}")
  should.equal(400, none.status)
  should.equal("BadDrawing", first_error(simulate.read_body(none)))

  // An undecodable body is the request's fault, not a field's.
  let junk = preview_of("not json")
  should.equal(400, junk.status)
  should.equal("BadRequest", first_error(simulate.read_body(junk)))

  // A read is not a preview: derive-only, POST-only.
  let read = call(Some(good_token()), http.Get, "/api/admin/preview", None)
  should.equal(405, read.status)
  should.equal("POST", header(read, "allow"))
}

fn preview_of(body: String) -> wisp.Response {
  call(Some(good_token()), http.Post, "/api/admin/preview", Some(body))
}

fn triangle_points() -> List(sketch.Dot) {
  [#(0.0, 0.0), #(10.0, 0.0), #(10.0, 10.0)]
}

fn response_fixture(body: String) -> Result(derivation.Fixture, Nil) {
  json.parse(body, using: fixture_doc_decoder())
  |> result.map_error(fn(_error) { Nil })
}

fn fixture_doc_decoder() -> decode.Decoder(derivation.Fixture) {
  use status <- decode.field("status", decode.string)
  case status {
    "ok" -> {
      use fixture <- decode.field("fixture", fixture_json.fixture_decoder())
      decode.success(fixture)
    }
    _ -> decode.failure(derivation.derive_fixture([], "", ""), "status ok")
  }
}

/// The created row's id, read from its own document (the store row is what the
/// preview must leave alone, and the document is how the test learns its id).
fn created_id(body: String) -> Int {
  case response_puzzle(body) {
    Ok(puzzle) -> puzzle.id
    Error(_) -> 0
  }
}

// ---------- infrastructure ----------

fn fresh_admin_db(label: String) -> String {
  let path = helpers.temp_db_path(label)
  let assert Ok(Nil) = store.init(path)
  helpers.set_env(store.database_path_env, path)
  // Presence-only by default; the fence tests opt into the audience check.
  unconfigure_audience()
  throttle.reset()
  path
}

fn configure_audience() -> Nil {
  helpers.set_env(access.audience_env, aud)
}

fn unconfigure_audience() -> Nil {
  helpers.set_env(access.audience_env, "")
}

fn token(audience: String, exp: Int) -> String {
  let claims =
    "{\"aud\":[\"" <> audience <> "\"],\"exp\":" <> int.to_string(exp) <> "}"
  "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9."
  <> bit_array.base64_url_encode(bit_array.from_string(claims), False)
  <> ".bm90LWEtc2lnbmF0dXJl"
}

fn good_token() -> String {
  token(aud, clock.now_seconds() + 300)
}

fn call(
  presented_token: Option(String),
  method: http.Method,
  path: String,
  body: Option(String),
) -> wisp.Response {
  call_with(ui_state(), presented_token, method, path, body)
}

/// The same request against an explicit app state, so the phase 4b tests can
/// drive "the boot read found nothing" without touching the filesystem.
fn call_with(
  app: toy_admin.App,
  presented_token: Option(String),
  method: http.Method,
  path: String,
  body: Option(String),
) -> wisp.Response {
  let base = simulate.request(method, path)
  let with_token = case presented_token {
    Some(presented) -> simulate.header(base, access.token_header, presented)
    None -> base
  }
  let with_body = case body {
    Some(body) -> simulate.string_body(with_token, body)
    None -> with_token
  }
  toy_admin.handle_request(with_body, app)
}

fn post_puzzle(body: String) -> wisp.Response {
  call(Some(good_token()), http.Post, "/api/admin/puzzles", Some(body))
}

fn put_puzzle(id: Int, body: String) -> wisp.Response {
  call(
    Some(good_token()),
    http.Put,
    "/api/admin/puzzles/" <> int.to_string(id),
    Some(body),
  )
}

fn create_body(name: String, show_date: String, dots: String) -> String {
  "{\"name\":\""
  <> name
  <> "\",\"showDate\":\""
  <> show_date
  <> "\",\"dots\":"
  <> dots
  <> "}"
}

fn header(response: wisp.Response, name: String) -> String {
  case list.key_find(response.headers, name) {
    Ok(value) -> value
    Error(_) -> ""
  }
}

fn first_error(body: String) -> String {
  case json.parse(body, using: error_decoder()) {
    Ok(problem) -> problem
    Error(_) -> "not an error envelope: " <> body
  }
}

fn error_decoder() -> decode.Decoder(String) {
  use errors <- decode.field("errors", decode.list(decode.string))
  case errors {
    [problem, ..] -> decode.success(problem)
    [] -> decode.failure("no errors", "a non-empty errors array")
  }
}

fn fixture_text() -> String {
  fixture_json.to_string(derivation.derive_fixture(
    [#(0.0, 0.0), #(10.0, 0.0), #(10.0, 10.0)],
    "Star",
    "2026-10-25",
  ))
}

/// A v4-shaped uuid, distinct per attempt (the attempts table upserts on
/// uuid + date, so seeded attempts must differ).
fn uuid(n: Int) -> String {
  // Canonical lowercase v4, distinct per call: 8-4-4-4-12 hex.
  "2f1c8e1a-1a2b-4c3d-8e4f-" <> int.to_string(100_000_000_000 + n)
}

fn moves(count: Int) -> String {
  let one = "{\"slot\":0,\"dir\":1}"
  "[" <> string.join(list.repeat(one, count), ",") <> "]"
}

fn seed_solve(path: String, uuid: String, date: String, count: Int) -> Nil {
  let assert Ok(Nil) =
    store.attempt_record_solve(path, uuid, date, moves(count))
  Nil
}

fn seed_abandon(path: String, uuid: String, date: String, count: Int) -> Nil {
  let assert Ok(Nil) = store.attempt_record_abandon(path, uuid, date, count)
  Nil
}

fn today_date() -> String {
  dates.visitor_local_date(clock.now_seconds(), 0)
}

// ---------- decoders ----------

type AdminPuzzle {
  AdminPuzzle(
    id: Int,
    name: String,
    show_date: String,
    dots: List(sketch.Dot),
    fixture: derivation.Fixture,
    created_at: Int,
    updated_at: Int,
  )
}

fn response_puzzle(body: String) -> Result(AdminPuzzle, Nil) {
  json.parse(body, using: puzzle_doc_decoder())
  |> result_map_error()
}

fn puzzle_doc_decoder() -> decode.Decoder(AdminPuzzle) {
  use puzzle <- decode.field("puzzle", puzzle_decoder())
  decode.success(puzzle)
}

fn puzzle_decoder() -> decode.Decoder(AdminPuzzle) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use show_date <- decode.field("showDate", decode.string)
  use dots <- decode.field("dots", fixture_json.dots_decoder())
  use fixture <- decode.field("fixture", fixture_json.fixture_decoder())
  use created_at <- decode.field("createdAt", decode.int)
  use updated_at <- decode.field("updatedAt", decode.int)
  decode.success(AdminPuzzle(
    id: id,
    name: name,
    show_date: show_date,
    dots: dots,
    fixture: fixture,
    created_at: created_at,
    updated_at: updated_at,
  ))
}

type MenuRow {
  MenuRow(
    id: Int,
    name: String,
    show_date: String,
    attempts: Int,
    solves: Int,
    solve_pct: Option(String),
    median_moves: Option(Float),
  )
}

fn list_decoder() -> decode.Decoder(#(String, List(MenuRow))) {
  use status <- decode.field("status", decode.string)
  use rows <- decode.field("puzzles", decode.list(row_decoder()))
  decode.success(#(status, rows))
}

fn row_decoder() -> decode.Decoder(MenuRow) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use show_date <- decode.field("showDate", decode.string)
  use attempts <- decode.field("attempts", decode.int)
  use solves <- decode.field("solves", decode.int)
  use solve_pct <- decode.field("solvePct", decode.optional(decode.string))
  use median_moves <- decode.field("medianMoves", decode.optional(decode.float))
  decode.success(MenuRow(
    id: id,
    name: name,
    show_date: show_date,
    attempts: attempts,
    solves: solves,
    solve_pct: solve_pct,
    median_moves: median_moves,
  ))
}

fn assert_row(
  rows: List(MenuRow),
  index: Int,
  name: String,
  attempts: Int,
  solves: Int,
  solve_pct: Option(String),
  median_moves: Option(Float),
) -> Nil {
  let assert Ok(row) = list_at(rows, index)
  should.equal(name, row.name)
  should.equal(attempts, row.attempts)
  should.equal(solves, row.solves)
  should.equal(solve_pct, row.solve_pct)
  should.equal(median_moves, row.median_moves)
  should.be_true(row.id > 0)
}

fn list_at(rows: List(a), index: Int) -> Result(a, Nil) {
  case list.drop(from: rows, up_to: index) {
    [row, ..] -> Ok(row)
    [] -> Error(Nil)
  }
}

fn result_map_error(result: Result(a, b)) -> Result(a, Nil) {
  case result {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}
