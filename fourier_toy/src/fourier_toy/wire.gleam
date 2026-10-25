//// The served puzzle's decoder (PLAN-daily-puzzles.md §1 Q1): the JSON
//// `GET /api/puzzle/today` answers with becomes the toy's `Setup` + `Shape`.
////
//// Why a decoder and not a second fixture pipeline: the backend derives the
//// dial truth and the 512-point target ONCE at save time
//// (toy_admin/fixture_json.gleam). The toy reads that document, resolves the
//// starting patches against the shape it just read, and plays — no DFT on
//// boot, and no guessing which number is which.
////
//// The document (the backend's `public_puzzle`):
////
////   {"status":"ok",
////    "puzzle":{"name":…, "showDate":…, "dots":[…],   the drawing (unused here)
////              "centroid":[x,y], "dials":["phase","radius","k","fixed"],
////              "dial":[{"k":…,"radius":…,"phase":…}, …],   the dial truth
////              "extras":[…],                                the fixed spectrum
////              "patches":[{"kind":"phase","deg":…}, …],      the start
////              "target":[[x,y], …]}}                        the 512-pt metric trace
////
//// Two derivations stay client-side because the wire cannot carry them without
//// restating the shape: `dial_max_r` (the biggest DIALABLE radius — the radius
//// dial's unit and the 200% ceiling) and `rms_polar` (the metric's normalizer,
//// the target trace's polar RMS about the centroid). Both come from
//// `shapes.from_parts`, the same code the built-in shapes use on themselves.
////
//// Everything else — a "none" envelope for an empty calendar, an "error"
//// envelope, a network failure's empty string, a document this decoder cannot
//// use — is `Error(Nil)`: the caller keeps the built-in quaver and tells no
//// telemetry (there is no puzzle identity to report against, §1).

import fourier_toy/puzzle.{type DialKind, type Patch}
import fourier_toy/shapes
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list

/// One served puzzle, ready to play: the toy's `Setup` (title, dial kinds,
/// starting patches) and the `Shape` those patches resolve against, plus the
/// date that identifies the day's attempt.
pub type DailyPuzzle {
  DailyPuzzle(setup: puzzle.Setup, shape: shapes.Shape, show_date: String)
}

/// The dial count every board has (puzzle.initial needs exactly four).
const slots = 4

pub fn decode(text: String) -> Result(DailyPuzzle, Nil) {
  case json.parse(text, using: envelope_decoder()) {
    Ok(Ok(daily)) -> Ok(daily)
    // an "ok" envelope this decoder cannot use, or a document that is not
    // JSON at all (a tunnel's HTML error page, an empty body)
    _ -> Error(Nil)
  }
}

/// `{"status":…}` first: only an "ok" envelope carries a puzzle. The other
/// statuses are answers, not errors ("none" is the empty calendar the quaver
/// fallback exists for), so they decode to `Error(Nil)` rather than failing.
fn envelope_decoder() -> decode.Decoder(Result(DailyPuzzle, Nil)) {
  use status <- decode.field("status", decode.string)
  case status {
    "ok" -> decode.at(["puzzle"], decode.map(at_puzzle(), Ok))
    _ -> decode.success(Error(Nil))
  }
}

fn at_puzzle() -> decode.Decoder(DailyPuzzle) {
  use name <- decode.field("name", decode.string)
  use show_date <- decode.field("showDate", decode.string)
  use centroid <- decode.field("centroid", point_decoder())
  use dials <- decode.field("dials", decode.list(dial_kind_decoder()))
  use dial <- decode.field("dial", decode.list(term_decoder()))
  use extras <- decode.field("extras", decode.list(term_decoder()))
  use patches <- decode.field("patches", decode.list(patch_decoder()))
  use target <- decode.field("target", decode.list(point_decoder()))

  let shape =
    shapes.from_parts(
      name: name,
      centroid: centroid,
      dial: dial,
      extras: extras,
      target: target,
    )
  let setup =
    puzzle.Setup(
      id: name,
      title: name,
      desc: "the day's puzzle — match the dashed target",
      shape: name,
      dials: dials,
      patches: patches,
    )
  let daily = DailyPuzzle(setup: setup, shape: shape, show_date: show_date)
  // A board is four dials and four starts; anything else cannot be opened, so
  // it is a fallback rather than a screen that crashes on the first step.
  case
    list.length(dials) == slots,
    list.length(dial) == slots,
    list.length(patches) == slots
  {
    True, True, True -> decode.success(daily)
    _, _, _ ->
      decode.failure(daily, "four dials, four truth terms, four patches")
  }
}

fn dial_kind_decoder() -> decode.Decoder(DialKind) {
  decode.then(decode.string, fn(name) {
    case name {
      "phase" -> decode.success(puzzle.DialP)
      "radius" -> decode.success(puzzle.DialR)
      "k" -> decode.success(puzzle.DialK)
      "fixed" -> decode.success(puzzle.DialFixed)
      _ -> decode.failure(puzzle.DialFixed, "a dial kind")
    }
  })
}

/// One starting patch, told apart by its `kind` word; each kind carries its
/// own field, so a k stays an integer and a percentage a float. The words match
/// toy_admin/fixture_json.gleam and the admin UI's decoder — one vocabulary,
/// three readers.
fn patch_decoder() -> decode.Decoder(Patch) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "phase" ->
      decode.field("deg", number_decoder(), fn(deg) {
        decode.success(puzzle.PhaseDeg(deg))
      })
    "radius" ->
      decode.field("pct", number_decoder(), fn(pct) {
        decode.success(puzzle.RPct(pct))
      })
    "k" ->
      decode.field("k", decode.int, fn(k) { decode.success(puzzle.KSet(k)) })
    "keep" -> decode.success(puzzle.Keep)
    _ -> decode.failure(puzzle.Keep, "a patch kind")
  }
}

fn term_decoder() -> decode.Decoder(shapes.TermState) {
  use k <- decode.field("k", decode.int)
  use radius <- decode.field("radius", number_decoder())
  use phase <- decode.field("phase", number_decoder())
  decode.success(shapes.TermState(k, radius, phase))
}

fn point_decoder() -> decode.Decoder(#(Float, Float)) {
  decode.then(decode.list(number_decoder()), fn(values) {
    case values {
      [x, y] -> decode.success(#(x, y))
      _ -> decode.failure(#(0.0, 0.0), "an [x, y] pair")
    }
  })
}

/// A JSON number as a Float: JS's `JSON.stringify` emits whole numbers as
/// ints, and the backend's dots/target do exactly that.
fn number_decoder() -> decode.Decoder(Float) {
  decode.one_of(decode.float, or: [decode.map(decode.int, int.to_float)])
}
