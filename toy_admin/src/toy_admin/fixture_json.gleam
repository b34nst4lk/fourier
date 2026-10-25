//// The fixture's wire format (PLAN-daily-puzzles.md §3 Q2/Q19) — the JSON a
//// puzzle is stored as, and the JSON `/api/puzzle/today` serves.
////
//// Two documents, one vocabulary:
////
////   stored dots     a JSON array of [x, y] pairs: the drawing, i.e. the source
////                   of truth the admin re-derives from
////   stored fixture  {"name","showDate","centroid","dials","dial","extras",
////                   "target"} — everything the toy needs to render, derived
////                   at save time so serving never runs the DFT
////   served puzzle   the stored fixture's fields plus "dots"
////
//// Why "dots" rides along (Q19): the toy can draw the puzzle AND show the
//// player's own drawing without a second request, and the fixture it rendered
//// is one document, not a join of two.
////
//// Why "dials" is data: the arrangement of the four dial slots (which slot is
//// phase / radius / k / fixed) is per-puzzle data, not a client-side constant.
//// It is the standard pattern in v1 — one source of truth for it lives in
//// `derivation.standard_dial_arrangement`, and the client reads the array.
////
//// Floats go out in gleam_json's shortest round-trip form ("27.57", "0.0"),
//// which decodes back to the identical value: storing a fixture and serving it
//// is lossless, so a re-served puzzle matches what the admin derived.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import sketch.{type Dot}
import toy_admin/derivation.{type Dial, type DialKind, type Fixture}

/// The stored fixture document, as text.
pub fn to_string(fixture: Fixture) -> String {
  fixture_to_json(fixture) |> json.to_string
}

/// The stored fixture document. Its own function so `public_puzzle` can splice
/// the derived half in without re-parsing text.
pub fn fixture_to_json(fixture: Fixture) -> json.Json {
  json.object(list.append(
    [
      #("name", json.string(fixture.name)),
      #("showDate", json.string(fixture.show_date)),
    ],
    derived_fields(fixture),
  ))
}

/// The served puzzle document: row identity (name/show_date from the puzzle
/// row, the authority) + dots + the stored fixture's derived fields.
pub fn public_puzzle(
  name name: String,
  show_date show_date: String,
  dots dots: List(Dot),
  fixture fixture: Fixture,
) -> json.Json {
  json.object(list.append(
    [
      #("name", json.string(name)),
      #("showDate", json.string(show_date)),
      #("dots", dots_to_json(dots)),
    ],
    derived_fields(fixture),
  ))
}

/// Read a stored fixture document back.
pub fn decode(from json_text: String) -> Result(Fixture, Nil) {
  json.parse(json_text, using: fixture_decoder())
  |> result.map_error(fn(_error) { Nil })
}

/// The drawing as text: a JSON array of [x, y] pairs.
pub fn dots_to_string(dots: List(Dot)) -> String {
  dots_to_json(dots) |> json.to_string
}

pub fn dots_to_json(dots: List(Dot)) -> json.Json {
  json.array(dots, of: point_to_json)
}

/// Read a stored drawing back.
pub fn dots_from_json(from json_text: String) -> Result(List(Dot), Nil) {
  json.parse(json_text, using: dots_decoder())
  |> result.map_error(fn(_error) { Nil })
}

/// The drawing decoder, for callers holding a Dynamic (the admin body field):
/// a JSON array of [x, y] NUMBER pairs. Whole numbers arrive as ints from
/// JavaScript's `JSON.stringify`, so both spellings decode and normalise to
/// Floats; a one-element or three-element inner array is refused.
pub fn dots_decoder() -> decode.Decoder(List(Dot)) {
  decode.list(point_decoder())
}

// ---------- internals ----------

fn derived_fields(fixture: Fixture) -> List(#(String, json.Json)) {
  [
    #("centroid", point_to_json(fixture.centroid)),
    #(
      "dials",
      json.array(fixture.dials, of: fn(kind) {
        json.string(dial_kind_name(kind))
      }),
    ),
    #("dial", json.array(fixture.dial, of: dial_to_json)),
    #("extras", json.array(fixture.extras, of: dial_to_json)),
    #("target", json.array(fixture.target, of: point_to_json)),
  ]
}

fn point_to_json(point: Dot) -> json.Json {
  json.array([json.float(point.0), json.float(point.1)], of: fn(item) { item })
}

fn dial_to_json(dial: Dial) -> json.Json {
  json.object([
    #("k", json.int(dial.k)),
    #("radius", json.float(dial.radius)),
    #("phase", json.float(dial.phase_deg)),
  ])
}

/// The dial-kind spelling on the wire. Deliberately lowercase and short — it is
/// the word the toy's dial labels already use.
fn dial_kind_name(kind: DialKind) -> String {
  case kind {
    derivation.DialPhase -> "phase"
    derivation.DialRadius -> "radius"
    derivation.DialK -> "k"
    derivation.DialFixed -> "fixed"
  }
}

fn dial_kind_decoder() -> decode.Decoder(DialKind) {
  decode.then(decode.string, fn(name) {
    case name {
      "phase" -> decode.success(derivation.DialPhase)
      "radius" -> decode.success(derivation.DialRadius)
      "k" -> decode.success(derivation.DialK)
      "fixed" -> decode.success(derivation.DialFixed)
      _ ->
        decode.failure(
          derivation.DialFixed,
          "one of \"phase\", \"radius\", \"k\", \"fixed\"",
        )
    }
  })
}

fn dial_decoder() -> decode.Decoder(Dial) {
  use k <- decode.field("k", decode.int)
  use radius <- decode.field("radius", decode.float)
  use phase_deg <- decode.field("phase", decode.float)
  decode.success(derivation.Dial(k: k, radius: radius, phase_deg: phase_deg))
}

fn point_decoder() -> decode.Decoder(Dot) {
  decode.then(decode.list(number_decoder()), fn(values) {
    case values {
      [x, y] -> decode.success(#(x, y))
      _ -> decode.failure(#(0.0, 0.0), "an [x, y] pair")
    }
  })
}

/// A JSON number as a Float: ints (what `JSON.stringify` emits for whole
/// numbers) and floats both read as the sketch's coordinate type.
fn number_decoder() -> decode.Decoder(Float) {
  decode.one_of(decode.float, or: [decode.map(decode.int, int.to_float)])
}

/// The stored fixture document's decoder. Public because the admin API decodes
/// the same document out of its own responses (the editor shows what it will
/// serve) — one decoder for the format, not a second copy in the tests.
pub fn fixture_decoder() -> decode.Decoder(Fixture) {
  use name <- decode.field("name", decode.string)
  use show_date <- decode.field("showDate", decode.string)
  use centroid <- decode.field("centroid", point_decoder())
  use dials <- decode.field("dials", decode.list(dial_kind_decoder()))
  use dial <- decode.field("dial", decode.list(dial_decoder()))
  use extras <- decode.field("extras", decode.list(dial_decoder()))
  use target <- decode.field("target", decode.list(point_decoder()))
  decode.success(derivation.Fixture(
    name: name,
    show_date: show_date,
    centroid: centroid,
    dials: dials,
    dial: dial,
    extras: extras,
    target: target,
  ))
}
