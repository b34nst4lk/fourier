//// The wire module's tests (PLAN-daily-puzzles.md §8): the envelope, the row
//// shape the backend emits, the fixture document, and the words the editor shows
//// for each error name.
////
//// The samples here are the backend's own JSON shapes (admin.gleam's
//// `summarize` / `row_json`, fixture_json.gleam's `fixture_to_json`), copied by
//// hand — admin_ui cannot import toy_admin, and the point of the test is that a
//// THIRD party (the wire) agrees with both.

import admin_ui/dial
import admin_ui/wire
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import test_helpers.{close}

const rows_ok =
  "{\"status\":\"ok\",\"puzzles\":[{\"id\":7,\"name\":\"the star\",\"showDate\":\"2026-10-25\",\"attempts\":12,\"solves\":5,\"solvePct\":\"41.7\",\"medianMoves\":37.0},{\"id\":6,\"name\":\"untouched\",\"showDate\":\"2026-10-24\",\"attempts\":0,\"solves\":0,\"solvePct\":null,\"medianMoves\":null}]}"

const fixture_ok =
  "{\"status\":\"ok\",\"fixture\":{\"name\":\"the star\",\"showDate\":\"2026-10-25\",\"centroid\":[50.0,49.999824523925774],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":1,\"radius\":27.574653306648354,\"phase\":270.0},{\"k\":-4,\"radius\":6,\"phase\":270.0},{\"k\":6,\"radius\":3,\"phase\":270.0},{\"k\":-14,\"radius\":0.5,\"phase\":270.0}],\"extras\":[],\"target\":[[50.0,10.0],[60.0,40.0]]}}"

pub fn the_menu_rows_decode_with_and_without_stats_test() {
  let assert Ok(rows) = wire.decode_rows(200, rows_ok)
  should.equal(2, list.length(rows))

  let assert [first, second] = rows
  should.equal(7, first.id)
  should.equal("the star", first.name)
  should.equal("2026-10-25", first.show_date)
  should.equal(12, first.attempts)
  should.equal(5, first.solves)
  should.equal(Some("41.7"), first.solve_pct)
  case first.median_moves {
    Some(value) -> close(value, 37.0, 1.0e-9)
    None -> should.equal("a median", "a null")
  }

  // a puzzle nobody has played shows nulls, not zeros
  should.equal(None, second.solve_pct)
  should.equal(None, second.median_moves)
  should.equal(0, second.attempts)
}

pub fn a_fixture_carries_its_starting_patches_test() {
  // The start rides with the fixture, one object per dial slot in slot order.
  // Each kind carries its own field, so a k is an int and a percentage a float.
  let document =
    "{\"status\":\"ok\",\"fixture\":{\"name\":\"the star\",\"showDate\":\"2026-10-25\",\"centroid\":[50.0,49.9],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[],\"extras\":[],\"patches\":[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"radius\",\"pct\":73.0},{\"kind\":\"k\",\"k\":4},{\"kind\":\"keep\"}],\"target\":[]}}"
  let assert Ok(fixture) = wire.decode_fixture(200, document)
  should.equal(
    [dial.PhaseDeg(0.0), dial.RPct(73.0), dial.KSet(4), dial.Keep],
    fixture.patches,
  )

  // a document without the field (a row stored before it existed) still decodes
  let assert Ok(bare) = wire.decode_fixture(200, fixture_ok)
  should.equal([], bare.patches)
}

pub fn an_unknown_patch_kind_is_a_decode_failure_test() {
  let document =
    "{\"status\":\"ok\",\"fixture\":{\"name\":\"a\",\"showDate\":\"2026-10-25\",\"centroid\":[0.0,0.0],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[],\"extras\":[],\"patches\":[{\"kind\":\"wobble\"}],\"target\":[]}}"
  // the wire layer names failures rather than leaking decode paths: an unknown
  // kind is a refused document, same as any other malformed one
  let assert Error(wire.Failure(_, errors)) = wire.decode_fixture(200, document)
  should.equal(["BadResponse"], errors)
}

pub fn a_fixture_decodes_with_its_whole_arrangement_test() {
  let assert Ok(fixture) = wire.decode_fixture(200, fixture_ok)
  should.equal("the star", fixture.name)
  should.equal("2026-10-25", fixture.show_date)
  close(fixture.centroid.0, 50.0, 1.0e-12)
  close(fixture.centroid.1, 49.999824523925774, 1.0e-12)

  // the arrangement arrives as data — four words, in slot order
  should.equal(
    [dial.KindPhase, dial.KindRadius, dial.KindK, dial.KindFixed],
    fixture.dials,
  )

  // four dial terms; whole numbers on the wire read as floats
  should.equal(4, list.length(fixture.dial))
  let assert [first, ..] = fixture.dial
  should.equal(1, first.k)
  close(first.radius, 27.574653306648354, 1.0e-12)
  close(first.phase_deg, 270.0, 1.0e-9)

  let assert [_, second, ..] = fixture.dial
  close(second.radius, 6.0, 1.0e-12)

  should.equal([], fixture.extras)
  should.equal(2, list.length(fixture.target))
  should.equal(None, fixture.dots)
}

pub fn a_puzzle_full_row_decodes_its_dots_test() {
  let text =
    "{\"status\":\"ok\",\"puzzle\":{\"id\":7,\"name\":\"n\",\"showDate\":\"2026-10-25\",\"dots\":[[10.0,10.0],[20,10]],\"fixture\":{},\"createdAt\":1,\"updatedAt\":2}}"
  let assert Ok(dots) = wire.decode_dots(200, text)
  should.equal([#(10.0, 10.0), #(20.0, 10.0)], dots)
}

pub fn a_taken_date_reads_as_that_date_is_taken_test() {
  let failure = wire.Failure(409, ["DuplicateShowDate"])
  should.equal("that date is taken", wire.failure_text(failure))
  // it underlines the DATE field, not the name or the drawing
  should.equal(True, wire.date_problem(failure))
  should.equal(False, wire.name_problem(failure))
  should.equal(False, wire.drawing_problem(failure))
}

pub fn every_name_in_the_contract_has_words_test() {
  should.equal(
    "the name needs 2–40 characters",
    wire.failure_text(wire.Failure(400, ["BadName"])),
  )
  should.equal(
    "that date is not a real date (YYYY-MM-DD)",
    wire.failure_text(wire.Failure(400, ["BadPuzzleDate"])),
  )
  should.equal(
    "that drawing does not make a puzzle — try a rounder shape",
    wire.failure_text(wire.Failure(400, ["BadDrawing"])),
  )
  should.equal(
    "the editor sent something the server could not read",
    wire.failure_text(wire.Failure(400, ["BadRequest"])),
  )
  should.equal(
    "that puzzle is gone",
    wire.failure_text(wire.Failure(404, ["UnknownPuzzle"])),
  )
  should.equal(
    "the server could not reach its database",
    wire.failure_text(wire.Failure(500, ["StoreError"])),
  )

  // two problems in one envelope: both are said, once each
  let both = wire.Failure(400, ["BadName", "BadPuzzleDate", "BadName"])
  should.equal(
    "the name needs 2–40 characters; that date is not a real date (YYYY-MM-DD)",
    wire.failure_text(both),
  )

  // an unmapped name is shown verbatim — an unknown error must not vanish
  should.equal(
    "WeirdNewError",
    wire.failure_text(wire.Failure(418, ["WeirdNewError"])),
  )
}

pub fn a_refused_fence_says_the_session_expired_test() {
  let expired = "your session has expired — reload the page and sign in again"
  should.equal(expired, wire.failure_text(wire.Failure(401, ["Unauthorized"])))
  // a 401 with no envelope at all still says the right thing
  should.equal(expired, wire.failure_text(wire.Failure(401, [])))
  // ...and a bare 500 does not pretend to be an auth problem
  should.equal("the server said 500", wire.failure_text(wire.Failure(500, [])))
}

pub fn a_body_the_server_cannot_read_is_not_a_failure_of_ours_test() {
  should.equal(
    Error(wire.Failure(400, ["BadResponse"])),
    wire.decode_rows(400, "<html>not json</html>"),
  )
  // a 200 that is not the shape we expected is also an error, not a crash
  should.equal(
    Error(wire.Failure(200, ["BadResponse"])),
    wire.decode_fixture(200, "{\"status\":\"ok\"}"),
  )
}

pub fn a_delete_is_204_with_nothing_to_read_test() {
  should.equal(Ok(Nil), wire.decode_nothing(204, ""))
  should.equal(
    Error(wire.Failure(404, ["UnknownPuzzle"])),
    wire.decode_nothing(
      404,
      "{\"status\":\"error\",\"errors\":[\"UnknownPuzzle\"]}",
    ),
  )
}

pub fn the_create_body_is_what_the_route_reads_test() {
  let body =
    wire.puzzle_body("the star", "2026-10-25", [#(50.0, 10.0), #(60.0, 40.5)])
  // gleam_json prints the shortest round-trip form, so a whole coordinate goes
  // out as `50` — the backend's number decoder reads ints and floats alike
  should.equal(
    "{\"name\":\"the star\",\"showDate\":\"2026-10-25\",\"dots\":[[50,10],[60,40.5]]}",
    body,
  )
  // preview speaks the same body: the route reads one shape for both
  should.equal(
    body,
    wire.preview_body("the star", "2026-10-25", [#(50.0, 10.0), #(60.0, 40.5)]),
  )
}

pub fn a_saved_fixture_is_read_from_the_rows_puzzle_document_test() {
  // GET /api/admin/puzzles/<id> nests the fixture INSIDE "puzzle": the menu's
  // TEST button reads that shape — live-probed (probe-single-get.sh), the
  // document has NO top-level fixture key. The edit flow already reads this
  // document's dots at ["puzzle","dots"]; the test read is its sibling.
  let document =
    "{\"status\":\"ok\",\"puzzle\":{\"id\":3,\"name\":\"review star\",\"showDate\":\"2026-10-25\",\"dots\":[[10.0,10.0],[90.0,10.0],[50.0,90.0]],\"fixture\":{\"name\":\"review star\",\"showDate\":\"2026-10-25\",\"centroid\":[49.9,37.3],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[],\"extras\":[],\"patches\":[],\"target\":[]},\"createdAt\":1,\"updatedAt\":2}}"
  let assert Ok(fixture) = wire.decode_saved_fixture(200, document)
  should.equal("review star", fixture.name)

  // a top-level fixture is the PREVIEW's shape, not the saved row's: the
  // two readers stay separate so a shape regression names itself
  let assert Error(wire.Failure(_, ["BadResponse"])) =
    wire.decode_saved_fixture(200, "{\"status\":\"ok\",\"fixture\":{}}")
}
