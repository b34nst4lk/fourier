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
////              "centroid":[x,y], "dials":["phase","radius","k"],
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
//// Normalization (PLAN-dial-columns.md §4.1d). The board dials exactly THREE
//// terms (three columns, kinds ∈ {phase, radius, k}). A served document may
//// still carry the retired "fixed" arrangement (the shipped puzzles used to
//// end in it), so "fixed" survives only as a PRIVATE marker here: every fixed
//// slot's truth term becomes an EXTRA — a fixed-correct term IS an extra — and
//// its patch is dropped, wherever the slot sits. After that there must be
//// exactly three dialable slots with three truth terms and three patches;
//// anything else is `Error(Nil)` (the caller keeps the built-in quaver).
////
//// Everything else — a "none" envelope for an empty calendar, an "error"
//// envelope, a network failure's empty string, a document this decoder cannot
//// use — is `Error(Nil)`: the caller keeps the built-in quaver and tells no
//// telemetry (there is no puzzle identity to report against, §1).

import fourier_toy/puzzle.{type DialKind, type Patch}
import fourier_toy/shapes
import gleam/bool
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

/// The dial count every board has (puzzle.initial needs exactly three).
const slots = 3

/// A dial kind AS SERVED, "fixed" included. Private on purpose: the board has
/// no fixed slots, and normalization erases this marker before anything else
/// is built. A served kind the toy does not know is a decode failure.
type ServedKind {
  ServedPhase
  ServedRadius
  ServedK
  ServedFixed
}

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
  use kinds <- decode.field("dials", decode.list(dial_kind_decoder()))
  use dial <- decode.field("dial", decode.list(term_decoder()))
  use extras <- decode.field("extras", decode.list(term_decoder()))
  use patches <- decode.field("patches", decode.list(patch_decoder()))
  use target <- decode.field("target", decode.list(point_decoder()))

  // The three per-slot lists are parallel: a document whose counts disagree
  // contradicts itself, and normalizing it would misalign terms and patches.
  // The target trace must also be non-empty: it is what `rms_polar` — and so
  // the score — is derived from, and `shapes.from_parts` asserts a non-zero
  // count. Refusing it HERE keeps an empty list a documented fallback rather
  // than a panic inside the shape derivation.
  case
    list.length(kinds) == list.length(dial),
    list.length(kinds) == list.length(patches),
    list.length(target) > 0
  {
    True, True, True -> {
      let rows = zip3(kinds, dial, patches)
      // A fixed slot is data, not a position: its truth term is a fixed term
      // (an extra) and its patch is dropped, wherever the slot sits. The served
      // extras keep their order after it.
      let fixed_terms =
        rows
        |> list.filter(fn(row) { is_fixed(row.0) })
        |> list.map(fn(row) { row.1 })
      let dialable =
        rows
        |> list.filter(fn(row) { bool.negate(is_fixed(row.0)) })

      let dials = list.map(dialable, fn(row) { kind_of(row.0) })
      let dial = list.map(dialable, fn(row) { row.1 })
      let patches = list.map(dialable, fn(row) { row.2 })
      let extras = list.append(fixed_terms, extras)

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

      // The 3-lock: three dials, three truth terms, three starts — otherwise
      // the board cannot be opened, so it is a fallback, not a screen that
      // crashes on the first step.
      case
        list.length(dials) == slots,
        list.length(dial) == slots,
        list.length(patches) == slots
      {
        True, True, True -> decode.success(daily)
        _, _, _ ->
          decode.failure(daily, "three dials, three truth terms, three patches")
      }
    }
    _, _, _ ->
      decode.failure(
        no_puzzle(),
        "matching dial and patch counts and a non-empty target",
      )
  }
}

/// A value to carry out of a decode failure (decode needs one; the caller
/// never sees it — `decode` maps every failure to `Error(Nil)`).
fn no_puzzle() -> DailyPuzzle {
  DailyPuzzle(
    setup: puzzle.Setup(
      id: "",
      title: "",
      desc: "",
      shape: "",
      dials: [],
      patches: [],
    ),
    shape: shapes.star(),
    show_date: "",
  )
}

fn dial_kind_decoder() -> decode.Decoder(ServedKind) {
  decode.then(decode.string, fn(name) {
    case name {
      "phase" -> decode.success(ServedPhase)
      "radius" -> decode.success(ServedRadius)
      "k" -> decode.success(ServedK)
      "fixed" -> decode.success(ServedFixed)
      _ -> decode.failure(ServedPhase, "a dial kind")
    }
  })
}

fn is_fixed(kind: ServedKind) -> Bool {
  case kind {
    ServedFixed -> True
    _ -> False
  }
}

fn kind_of(kind: ServedKind) -> DialKind {
  case kind {
    ServedPhase -> puzzle.DialP
    ServedRadius -> puzzle.DialR
    ServedK -> puzzle.DialK
    // unreachable: fixed rows are filtered out before this runs
    ServedFixed -> puzzle.DialP
  }
}

/// One starting patch, told apart by its `kind` word; each kind carries its
/// own field, so a k stays an integer and a percentage a float. The words match
/// toy_admin/fixture_json.gleam and the admin UI's decoder — one vocabulary,
/// three readers. "keep" stays a parsable patch kind (harmless: it leaves the
/// slot at truth) even though the board's three dials always carry a value.
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

/// Three equal-length lists as per-slot triples (the callers check the lengths
/// first; this truncates at the shortest, like `list.zip`).
fn zip3(a: List(x), b: List(y), c: List(z)) -> List(#(x, y, z)) {
  case a, b, c {
    [x, ..xs], [y, ..ys], [z, ..zs] -> [#(x, y, z), ..zip3(xs, ys, zs)]
    _, _, _ -> []
  }
}
