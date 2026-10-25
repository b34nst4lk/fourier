//// The fixture's wire format (PLAN-daily-puzzles.md §3 Q2/Q19): the JSON a
//// puzzle is stored as and the JSON `/api/puzzle/today` serves.
////
//// Two documents, one vocabulary:
////
////   stored fixture   {"name","showDate","centroid","dials","dial","extras",
////                     "target"}
////   stored dots      a JSON array of [x, y] pairs — the drawing, the source of
////                    truth the admin re-derives from
////   served puzzle    the stored fixture's fields, with "dots" — the flat object
////                    the toy renders (it can draw the puzzle and show the
////                    player's own drawing without a second request)
////
//// `dials` carries the dial ARRANGEMENT (Q19: per-puzzle data, always the
//// standard pattern in v1), so the client never hard-codes which slot is
//// phase/radius/k/fixed.

import gleam/dynamic
import gleam/dynamic/decode as dynamic_decode
import gleam/json
import gleam/list
import gleam/result
import gleeunit/should
import helpers.{be_close}
import sketch
import toy_admin/derivation
import toy_admin/fixture_json

const name = "Star"

const show_date = "2026-10-25"

fn fixture() -> derivation.Fixture {
  derivation.Fixture(
    name: name,
    show_date: show_date,
    centroid: #(1.5, -2.25),
    dials: [
      derivation.DialPhase,
      derivation.DialRadius,
      derivation.DialK,
      derivation.DialFixed,
    ],
    dial: [derivation.Dial(k: 2, radius: 27.57, phase_deg: 90.0)],
    extras: [derivation.Dial(k: -1, radius: 0.5, phase_deg: 180.0)],
    target: [#(0.0, 0.0), #(1.5, -2.25)],
  )
}

pub fn encoded_fixture_pins_the_field_names_test() {
  // The toy is written against this exact document (Q1: it renders the fetch
  // exactly as any built-in fixture). Field names and the dial-kind spelling
  // are the contract; changing them is a client break.
  should.equal(
    "{\"name\":\"Star\",\"showDate\":\"2026-10-25\",\"centroid\":[1.5,-2.25],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":2,\"radius\":27.57,\"phase\":90.0}],\"extras\":[{\"k\":-1,\"radius\":0.5,\"phase\":180.0}],\"target\":[[0.0,0.0],[1.5,-2.25]]}",
    fixture_json.to_string(fixture()),
  )
}

pub fn fixture_round_trips_through_json_test() {
  // Storing the fixture and serving it back must not lose anything: floats
  // survive gleam_json's shortest-representation encoding exactly, so this is
  // an equality check, not a tolerance one.
  should.equal(
    Ok(fixture()),
    fixture_json.decode(fixture_json.to_string(fixture())),
  )
}

pub fn derived_fixture_round_trips_test() {
  // The real thing: a derived star fixture through encode/decode.
  let derived = derivation.derive_fixture(sketch.star(), name, show_date)
  let assert Ok(decoded) = fixture_json.decode(fixture_json.to_string(derived))

  should.equal(4, list.length(decoded.dial))
  should.equal(derivation.sample_count, list.length(decoded.target))
  list.zip(decoded.dial, derived.dial)
  |> list.each(fn(pair) {
    let #(actual, expected) = pair
    should.equal(expected.k, actual.k)
    be_close(actual.radius, expected.radius, 0.000_001)
    be_close(actual.phase_deg, expected.phase_deg, 0.000_001)
  })
}

pub fn dial_arrangement_round_trips_test() {
  let assert Ok(decoded) =
    fixture_json.decode(fixture_json.to_string(fixture()))
  should.equal(derivation.standard_dial_arrangement(), decoded.dials)
}

pub fn decode_rejects_garbage_test() {
  should.equal(Error(Nil), fixture_json.decode("not json"))
  should.equal(Error(Nil), fixture_json.decode("{}"))
  should.equal(
    Error(Nil),
    fixture_json.decode(
      "{\"name\":\"a\",\"showDate\":\"2026-10-25\",\"centroid\":[0.0,0.0],\"dials\":[\"nope\"],\"dial\":[],\"extras\":[],\"target\":[]}",
    ),
  )
}

pub fn dots_round_trip_test() {
  let dots = [#(0.0, 0.0), #(12.5, -3.25), #(100.0, 100.0)]
  should.equal(
    "[[0.0,0.0],[12.5,-3.25],[100.0,100.0]]",
    fixture_json.dots_to_string(dots),
  )
  should.equal(
    Ok(dots),
    fixture_json.dots_from_json(fixture_json.dots_to_string(dots)),
  )
}

pub fn dots_decode_rejects_non_pairs_test() {
  should.equal(Error(Nil), fixture_json.dots_from_json("[[1.0]]"))
  should.equal(Error(Nil), fixture_json.dots_from_json("[1.0,2.0]"))
  should.equal(Error(Nil), fixture_json.dots_from_json("{}"))
}

pub fn public_puzzle_carries_the_row_identity_and_dots_test() {
  // The served object is FLAT: the toy indexes fields directly. Identity comes
  // from the puzzle row (the authority), never from the stored fixture copy.
  let served =
    fixture_json.public_puzzle(
      "Star (row)",
      "2026-10-26",
      [#(3.0, 4.0)],
      fixture(),
    )
    |> json.to_string

  should.equal(
    "{\"name\":\"Star (row)\",\"showDate\":\"2026-10-26\",\"dots\":[[3.0,4.0]],\"centroid\":[1.5,-2.25],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":2,\"radius\":27.57,\"phase\":90.0}],\"extras\":[{\"k\":-1,\"radius\":0.5,\"phase\":180.0}],\"target\":[[0.0,0.0],[1.5,-2.25]]}",
    served,
  )
}

pub fn dots_decode_accepts_integer_coordinates_test() {
  // THE JAVASCRIPT BRIDGE: `JSON.stringify` of a whole-number coordinate emits
  // `10`, not `10.0`. The admin canvas sends ints for most dots, so the wire
  // reader must accept both spellings of "a number" and normalise to floats
  // (sketch.Dot is #(Float, Float)).
  should.equal(
    Ok([#(0.0, 0.0), #(10.0, 5.0)]),
    fixture_json.dots_from_json("[[0,0],[10,5]]"),
  )
  // Mixed spellings in one drawing are fine too.
  should.equal(
    Ok([#(1.0, 2.5), #(3.0, 4.0)]),
    fixture_json.dots_from_json("[[1,2.5],[3.0,4]]"),
  )
}

pub fn dots_decoder_reads_a_dynamic_value_test() {
  // The admin route decodes the body field as Dynamic first (so a malformed
  // drawing is BadDrawing, not BadRequest) and runs this decoder on it.
  let assert Ok(value) =
    json.parse("[[1,2],[3.5,4]]", using: dynamic_decode.dynamic)
  should.equal(Ok([#(1.0, 2.0), #(3.5, 4.0)]), decode_run(value))
}

pub fn dots_decoder_refuses_a_non_list_test() {
  let assert Ok(value) = json.parse("{\"x\":1}", using: dynamic_decode.dynamic)
  should.equal(Error(Nil), decode_run(value))
}

fn decode_run(value: dynamic.Dynamic) -> Result(List(sketch.Dot), Nil) {
  dynamic_decode.run(value, fixture_json.dots_decoder())
  |> result.map_error(fn(_errors) { Nil })
}
