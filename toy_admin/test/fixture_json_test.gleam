//// The fixture's wire format: the JSON a
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
//// `dials` carries the dial ARRANGEMENT , so the client never hard-codes which slot is
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
    patches: [
      derivation.PhaseDeg(0.0),
      derivation.RPct(73.0),
      derivation.KSet(-3),
      derivation.Keep,
    ],
    target: [#(0.0, 0.0), #(1.5, -2.25)],
  )
}

pub fn encoded_fixture_pins_the_field_names_test() {
  // The toy is written against this exact document . Field names and the dial-kind spelling
  // are the contract; changing them is a client break.
  should.equal(
    "{\"name\":\"Star\",\"showDate\":\"2026-10-25\",\"centroid\":[1.5,-2.25],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":2,\"radius\":27.57,\"phase\":90.0}],\"extras\":[{\"k\":-1,\"radius\":0.5,\"phase\":180.0}],\"patches\":[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"radius\",\"pct\":73.0},{\"kind\":\"k\",\"k\":-3},{\"kind\":\"keep\"}],\"target\":[[0.0,0.0],[1.5,-2.25]]}",
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
    "{\"name\":\"Star (row)\",\"showDate\":\"2026-10-26\",\"dots\":[[3.0,4.0]],\"centroid\":[1.5,-2.25],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":2,\"radius\":27.57,\"phase\":90.0}],\"extras\":[{\"k\":-1,\"radius\":0.5,\"phase\":180.0}],\"patches\":[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"radius\",\"pct\":73.0},{\"kind\":\"k\",\"k\":-3},{\"kind\":\"keep\"}],\"target\":[[0.0,0.0],[1.5,-2.25]]}",
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

// ---------- the starting patches on the wire (§1's deterministic start) -----

pub fn patches_round_trip_test() {
  // One object per dial slot, in slot order. The kind word is the vocabulary
  // the toy's dial rows already use (phase / radius / k); a slot that is not
  // perturbed says "keep". Values use each kind's own field name, so a k stays
  // an integer and a percentage stays a float — nothing is guessed by position.
  let assert Ok(read_back) =
    fixture_json.decode(fixture_json.to_string(fixture()))
  should.equal(fixture().patches, read_back.patches)
  should.equal(
    Ok(fixture()),
    fixture_json.decode(fixture_json.to_string(fixture())),
  )
}

pub fn patch_kinds_have_their_own_wire_spelling_test() {
  // The four kinds, pinned one by one — this is the string the toy decodes.
  should.equal(
    "[{\"kind\":\"phase\",\"deg\":355.0}]",
    patches_wire([derivation.PhaseDeg(355.0)]),
  )
  should.equal(
    "[{\"kind\":\"radius\",\"pct\":73.0}]",
    patches_wire([derivation.RPct(73.0)]),
  )
  should.equal(
    "[{\"kind\":\"k\",\"k\":-5}]",
    patches_wire([derivation.KSet(-5)]),
  )
  should.equal("[{\"kind\":\"keep\"}]", patches_wire([derivation.Keep]))
  // all four in slot order, exactly as a derived fixture serves them
  should.equal(
    "[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"radius\",\"pct\":73.0},{\"kind\":\"k\",\"k\":-3},{\"kind\":\"keep\"}]",
    patches_wire(fixture().patches),
  )
}

pub fn derived_fixture_serves_its_start_test() {
  // The end-to-end claim: a derived fixture's served document carries a start
  // the toy can decode — four patches, one per dial slot, in slot order.
  let derived = derivation.derive_fixture(sketch.star(), name, show_date)
  let served =
    fixture_json.public_puzzle(
      name: name,
      show_date: show_date,
      dots: sketch.star(),
      fixture: derived,
    )
    |> json.to_string
  let assert Ok(kinds) = json.parse(served, using: patch_kinds_decoder())
  should.equal(["phase", "radius", "k", "keep"], kinds)
}

pub fn a_fixture_without_a_start_is_refused_test() {
  // Strict on purpose: a served puzzle with no patches has no deterministic
  // start, and the toy's board (puzzle.initial) requires exactly four. A row
  // from before the patches field is re-derived from its dots by the admin's
  // repair path, not served half-formed.
  should.equal(
    Error(Nil),
    fixture_json.decode(
      "{\"name\":\"a\",\"showDate\":\"2026-10-25\",\"centroid\":[0.0,0.0],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[],\"extras\":[],\"target\":[]}",
    ),
  )
}

pub fn an_unknown_patch_kind_is_refused_test() {
  should.equal(
    Error(Nil),
    fixture_json.decode(
      "{\"name\":\"a\",\"showDate\":\"2026-10-25\",\"centroid\":[0.0,0.0],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[],\"extras\":[],\"patches\":[{\"kind\":\"wobble\"}],\"target\":[]}",
    ),
  )
}

fn patches_wire(patches: List(derivation.Patch)) -> String {
  fixture_json.patches_to_json(patches) |> json.to_string
}

fn patch_kinds_decoder() -> dynamic_decode.Decoder(List(String)) {
  use patches <- dynamic_decode.field(
    "patches",
    dynamic_decode.list(dynamic_decode.field(
      "kind",
      dynamic_decode.string,
      dynamic_decode.success,
    )),
  )
  dynamic_decode.success(patches)
}
