//// The admin UI's view of the wire (PLAN-daily-puzzles.md §8) — decode what
//// the backend sends, encode what it accepts.
////
//// Everything the UI knows about the API lives here, so the view and the update
//// function stay free of JSON. The envelope is the contract (§8):
////
////   {"status":"ok",   ...payload}     -> Ok(payload)
////   {"status":"none", "fallback":true} -> an empty payload, not an error
////   {"status":"error","errors":[names]} -> Error(Failure(status, names))
////
//// The names are the contract too — `DuplicateShowDate`, `BadName`,
//// `BadPuzzleDate`, `BadDrawing`, `BadRequest`, `UnknownPuzzle`, `Unauthorized`,
//// `StoreError` — and `failure_text` is the ONE place that turns them into
//// words. A name it
//// does not know is shown verbatim rather than swallowed: an unmapped error is a
//// bug in this file, and hiding it would make the bug invisible.

import admin_ui/dial
import admin_ui/score
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/result

/// A published puzzle holds its day; a draft has none (see `is_draft`).
pub const status_published = "published"

/// The store's date-less marker, as a badge and a filter.
pub const status_draft = "draft"

/// The one human author there is (the admin behind the fence). An agent's row
/// carries the agent's id instead, which is what the menu badges on.
pub const creator_human = "human"

/// One row of the menu: identity, schedule, WHO filed it, and the Q23 numbers
/// (nulls while a puzzle has no attempts).
pub type Row {
  Row(
    id: Int,
    name: String,
    show_date: String,
    status: String,
    creator: String,
    attempts: Int,
    solves: Int,
    solve_pct: Option(String),
    median_moves: Option(Float),
  )
}

/// An undated row: an agent's (or a human's) sketch waiting for a date. The
/// store derives the status from the date, so this is a reading of `show_date`,
/// not a second fact that could disagree with it.
pub fn is_draft(row: Row) -> Bool {
  row.status == status_draft
}

/// A puzzle as the editor uses it: the drawing (when the API sent one) plus the
/// derived fixture. `dials` is data, not a constant (Q19) — the editor renders
/// the dials the fixture declares.
///
/// `patches` is the puzzle's starting perturbation, one entry per dial slot,
/// derived by the backend with the fixture (fixture_json.gleam) so the editor's
/// test play opens exactly where the player's board opens. An empty list means
/// a fixture stored before the field existed: `play_from` then falls back to the
/// editor's old standard row.
pub type Fixture {
  Fixture(
    name: String,
    show_date: String,
    centroid: score.Point,
    dials: List(dial.Kind),
    dial: List(score.Term),
    extras: List(score.Term),
    target: List(score.Point),
    patches: List(dial.Patch),
    dots: Option(List(score.Point)),
  )
}

/// A refused request: the HTTP status and the envelope's error names.
pub type Failure {
  Failure(status: Int, errors: List(String))
}

// ---------- decoding ----------

pub fn decode_rows(status: Int, text: String) -> Result(List(Row), Failure) {
  decode_ok(status, text, decode.at(["puzzles"], decode.list(row_decoder())))
}

pub fn decode_fixture(status: Int, text: String) -> Result(Fixture, Failure) {
  decode_ok(status, text, decode.at(["fixture"], fixture_decoder()))
}

pub fn decode_saved_fixture(
  status: Int,
  text: String,
) -> Result(Fixture, Failure) {
  decode_ok(status, text, decode.at(["puzzle", "fixture"], fixture_decoder()))
}

/// A row's dots — the edit flow loads a puzzle's drawing so the editor can
/// reopen it.
pub fn decode_dots(
  status: Int,
  text: String,
) -> Result(List(score.Point), Failure) {
  decode_ok(status, text, decode.at(["puzzle", "dots"], points_decoder()))
}

/// For 200/204 responses with no payload worth reading (a delete).
pub fn decode_nothing(status: Int, text: String) -> Result(Nil, Failure) {
  case status {
    200 | 201 | 202 | 204 -> Ok(Nil)
    _ -> Error(failure_of(status, text))
  }
}

fn decode_ok(
  status: Int,
  text: String,
  read: decode.Decoder(value),
) -> Result(value, Failure) {
  case status {
    200 | 201 | 202 -> {
      case json_parse(text, read) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(Failure(status, ["BadResponse"]))
      }
    }
    _ -> Error(failure_of(status, text))
  }
}

fn json_parse(text: String, read: decode.Decoder(value)) -> Result(value, Nil) {
  json.parse(text, using: read)
  |> result.map_error(fn(_) { Nil })
}

/// The names in an error envelope; an unparseable body still yields the status.
fn failure_of(status: Int, text: String) -> Failure {
  let names = case json_parse(text, names_decoder()) {
    Ok(names) -> names
    Error(_) -> ["BadResponse"]
  }
  Failure(status, names)
}

fn names_decoder() -> decode.Decoder(List(String)) {
  decode.at(["errors"], decode.list(decode.string))
}

fn row_decoder() -> decode.Decoder(Row) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use show_date <- decode.field("showDate", decode.string)
  use status <- decode.field("status", decode.string)
  use creator <- decode.field("creator", decode.string)
  use attempts <- decode.field("attempts", decode.int)
  use solves <- decode.field("solves", decode.int)
  use solve_pct <- decode.field("solvePct", decode.optional(decode.string))
  use median_moves <- decode.field(
    "medianMoves",
    decode.optional(number_decoder()),
  )
  decode.success(Row(
    id,
    name,
    show_date,
    status,
    creator,
    attempts,
    solves,
    solve_pct,
    median_moves,
  ))
}

pub fn fixture_decoder() -> decode.Decoder(Fixture) {
  use name <- decode.field("name", decode.string)
  use show_date <- decode.field("showDate", decode.string)
  use centroid <- decode.field("centroid", point_decoder())
  use dials <- decode.field("dials", decode.list(kind_decoder()))
  use dial_terms <- decode.field("dial", decode.list(term_decoder()))
  use extras <- decode.field("extras", decode.list(term_decoder()))
  use target <- decode.field("target", points_decoder())
  use patches <- decode.optional_field(
    "patches",
    [],
    decode.list(patch_decoder()),
  )
  use dots <- decode.optional_field(
    "dots",
    None,
    decode.optional(points_decoder()),
  )
  decode.success(Fixture(
    name: name,
    show_date: show_date,
    centroid: centroid,
    dials: dials,
    dial: dial_terms,
    extras: extras,
    target: target,
    patches: patches,
    dots: dots,
  ))
}

/// One starting patch, told apart by its `kind` word; each kind carries its own
/// field, so a k stays an integer and a percentage a float. The words match
/// fixture_json.gleam and the toy's decoder — one vocabulary, three readers.
fn patch_decoder() -> decode.Decoder(dial.Patch) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "phase" ->
      decode.field("deg", number_decoder(), fn(deg) {
        decode.success(dial.PhaseDeg(deg))
      })
    "radius" ->
      decode.field("pct", number_decoder(), fn(pct) {
        decode.success(dial.RPct(pct))
      })
    "k" -> decode.field("k", decode.int, fn(k) { decode.success(dial.KSet(k)) })
    "keep" -> decode.success(dial.Keep)
    _ -> decode.failure(dial.Keep, "a patch kind")
  }
}

fn kind_decoder() -> decode.Decoder(dial.Kind) {
  decode.then(decode.string, fn(name) {
    case dial.parse_kind(name) {
      Ok(kind) -> decode.success(kind)
      Error(_) ->
        decode.failure(dial.KindFixed, "one of phase, radius, k, fixed")
    }
  })
}

fn term_decoder() -> decode.Decoder(score.Term) {
  use k <- decode.field("k", decode.int)
  use radius <- decode.field("radius", number_decoder())
  use phase_deg <- decode.field("phase", number_decoder())
  decode.success(score.Term(k, radius, phase_deg))
}

/// A `[x, y]` pair — the sketch's coordinate type on the wire.
fn point_decoder() -> decode.Decoder(score.Point) {
  decode.then(decode.list(number_decoder()), fn(values) {
    case values {
      [x, y] -> decode.success(#(x, y))
      _ -> decode.failure(#(0.0, 0.0), "an [x, y] pair")
    }
  })
}

fn points_decoder() -> decode.Decoder(List(score.Point)) {
  decode.then(decode.list(point_decoder()), decode.success)
}

/// A JSON number as a Float: whole numbers arrive as ints (JavaScript's
/// `JSON.stringify`), and the fixture rounds nothing.
fn number_decoder() -> decode.Decoder(Float) {
  decode.one_of(decode.float, or: [decode.map(decode.int, int.to_float)])
}

// ---------- encoding ----------

/// The create/update body: `{name, showDate, dots}`.
pub fn puzzle_body(
  name: String,
  show_date: String,
  dots: List(score.Point),
) -> String {
  json.object([
    #("name", json.string(name)),
    #("showDate", json.string(show_date)),
    #("dots", json.array(dots, of: point_json)),
  ])
  |> json.to_string
}

/// The preview body: the same shape, both fields optional to the backend (a
/// preview is drawn before a name or a date is chosen).
pub fn preview_body(
  name: String,
  show_date: String,
  dots: List(score.Point),
) -> String {
  puzzle_body(name, show_date, dots)
}

/// The approve body: ONE field. A PUT that mentions only `showDate` dates a
/// draft without touching its name or its drawing (admin.gleam's schedule rule)
/// — the row keeps its author, so the agent that filed it stays on the record
/// after the human signs off.
pub fn approve_body(show_date: String) -> String {
  json.object([#("showDate", json.string(show_date))])
  |> json.to_string
}

fn point_json(point: score.Point) -> json.Json {
  json.array([json.float(point.0), json.float(point.1)], of: fn(item) { item })
}

// ---------- names -> words ----------

/// One banner line for a failure. Names map to what the editor should say; the
/// 409 on a taken date is the case the whole save flow is built around.
pub fn failure_text(failure: Failure) -> String {
  case failure.errors {
    [] ->
      case failure.status {
        401 | 403 -> expired
        _ -> "the server said " <> int.to_string(failure.status)
      }
    names -> name_joined(names)
  }
}

const expired = "your session has expired — reload the page and sign in again"

fn name_joined(names: List(String)) -> String {
  list.map(names, name_text)
  |> list.unique
  |> join_with("; ")
}

fn join_with(parts: List(String), separator: String) -> String {
  list.fold(
    list.drop(parts, 1),
    case parts {
      [first, ..] -> first
      [] -> ""
    },
    fn(acc, part) { acc <> separator <> part },
  )
}

fn name_text(name: String) -> String {
  case name {
    "DuplicateShowDate" -> "that date is taken"
    "BadName" -> "the name needs 2–40 characters"
    "BadPuzzleDate" -> "that date is not a real date (YYYY-MM-DD)"
    "BadDrawing" -> "that drawing does not make a puzzle — try a rounder shape"
    "BadRequest" -> "the editor sent something the server could not read"
    "UnknownPuzzle" -> "that puzzle is gone"
    "Unauthorized" -> expired
    "StoreError" -> "the server could not reach its database"
    _ -> name
  }
}

/// The name field's inline complaint, if the failure is about the name.
pub fn name_problem(failure: Failure) -> Bool {
  list.contains(failure.errors, "BadName")
}

/// The date field's inline complaint — a taken date is the same red underline
/// as an impossible one, because both are about that field.
pub fn date_problem(failure: Failure) -> Bool {
  list.any(failure.errors, fn(name) {
    name == "DuplicateShowDate" || name == "BadPuzzleDate"
  })
}

pub fn drawing_problem(failure: Failure) -> Bool {
  list.contains(failure.errors, "BadDrawing")
}
