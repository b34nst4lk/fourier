//// The stored attempt (localStorage key `j-att`): one player's progress on one
//// puzzle date, client-side (PLAN-daily-puzzles.md §1, Q21/Q24).
////
//// Schema v2 — a JSON OBJECT, one key per field, never positional:
////
////   {"v":2,
////    "date":"2026-10-26",                the show date this attempt belongs to
////    "state":[{"k":-1,"r":17.97,"phase":355}, …],
////                                        the three dial terms, slot order
////    "moves":[[0,1],[1,-1], …],          (slot, dir) pairs in play order
////    "count":7,                          the counter as shown
////    "solved":false,                     the record is FINAL once true
////    "reported":false}                   the solve POST has landed (2xx)
////
//// v2 (PLAN-dial-columns.md §3): the board dials three terms, not four,
//// so `state` is a 3-term array and `v` bumps 1→2. A
//// stored v1 document (four terms) is stale: it decodes to `Error(Nil)` and the
//// board starts fresh. The version bump is the sanctioned way to retire a
//// stored format, and only pre-change attempts are affected.
////
//// Why both the list and the count: the list is the reproducible record the
//// backend re-derives the final state from, and it stops growing at the first
//// solve (the counter-freeze boundary) plus at its 500-entry cap (Q1's cap,
//// the backend's `TooManyMoves`). The count is what the player sees. They agree
//// until one of those two boundaries separates them, and each tells its own
//// truth: "how many steps it took" vs "the steps we can replay".
////
//// Why `reported` is its own flag rather than "solved && posted": the POST is
//// asynchronous — a solve that never landed (offline, closed tab) must be
//// re-sent on the next boot, and the backend's solve is idempotent (it REPLACES
//// the row, §8), so a duplicate is free.
////
//// A document that does not decode means "start fresh": a version bump (`v`)
//// is the sanctioned way to retire this format, and a half-restored board is
//// never better than a clean one.
////
//// Not persisted, by design: the theme (its own key, f-toy-theme) and the uuid
//// (site-wide, j-uid, Q16) — an attempt is about one puzzle on one date.

import fourier_toy/shapes.{type TermState}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result

/// One dial slot's move: the slot index and the direction (−1 or +1).
pub type Move =
  #(Int, Int)

pub type Attempt {
  Attempt(
    /// The puzzle's show date (a daily puzzle's identity).
    date: String,
    /// The three dial terms as they stand.
    state: List(TermState),
    /// Steps in play order, recorded until the first solve (capped).
    moves: List(Move),
    /// The counter as shown — frozen at the first solve.
    count: Int,
    /// The record is final: a solved attempt keeps its number.
    solved: Bool,
    /// The solve POST landed. False + solved ⇒ re-send on the next boot.
    reported: Bool,
  )
}

/// The storage key: one attempt at a time, replaced on a new day.
pub const storage_key = "j-att"

/// The move-list cap (Q1: the client caps at 500; the backend refuses more).
pub const move_cap = 500

/// A brand-new attempt: nothing played, nothing solved, nothing reported.
pub fn fresh(date: String, state: List(TermState)) -> Attempt {
  Attempt(
    date: date,
    state: state,
    moves: [],
    count: 0,
    solved: False,
    reported: False,
  )
}

/// Record one step. Called only while the attempt is still open (before the
/// first solve): past `move_cap` the list stops growing.
pub fn add_move(a: Attempt, slot: Int, dir: Int) -> Attempt {
  case list.length(a.moves) >= move_cap {
    True -> a
    False -> Attempt(..a, moves: list.append(a.moves, [#(slot, dir)]))
  }
}

/// The dials moved (and, at the freeze boundary, the record became final).
pub fn record(
  a: Attempt,
  state: List(TermState),
  count: Int,
  solved: Bool,
) -> Attempt {
  Attempt(..a, state: state, count: count, solved: solved)
}

/// The solve POST came back 2xx: nothing left to re-send.
pub fn mark_reported(a: Attempt) -> Attempt {
  Attempt(..a, reported: True)
}

// ---------- the two POST bodies ----------

/// `POST /api/solve`: the reproducible record — start state + these moves ⇒
/// the final dial state, which is how the backend summarises a game.
pub fn solve_body(uuid: String, a: Attempt) -> String {
  json.object([
    #("uuid", json.string(uuid)),
    #("puzzleDate", json.string(a.date)),
    #(
      "moves",
      json.array(a.moves, of: fn(move) {
        json.object([#("slot", json.int(move.0)), #("dir", json.int(move.1))])
      }),
    ),
  ])
  |> json.to_string
}

/// `POST /api/attempts/abandon`: an abandoned attempt has no list worth
/// keeping, only how far it got.
pub fn abandon_body(uuid: String, a: Attempt) -> String {
  json.object([
    #("uuid", json.string(uuid)),
    #("puzzleDate", json.string(a.date)),
    #("moves", json.int(a.count)),
  ])
  |> json.to_string
}

// ---------- the document ----------

pub fn encode(a: Attempt) -> String {
  json.object([
    #("v", json.int(2)),
    #("date", json.string(a.date)),
    #("state", json.array(a.state, of: term_json)),
    #(
      "moves",
      json.array(a.moves, of: fn(move) {
        json.array([json.int(move.0), json.int(move.1)], of: fn(n) { n })
      }),
    ),
    #("count", json.int(a.count)),
    #("solved", json.bool(a.solved)),
    #("reported", json.bool(a.reported)),
  ])
  |> json.to_string
}

pub fn decode(from text: String) -> Result(Attempt, Nil) {
  json.parse(from: text, using: attempt_decoder())
  |> result.map_error(fn(_error) { Nil })
}

fn attempt_decoder() -> decode.Decoder(Attempt) {
  use version <- decode.field("v", decode.int)
  case version {
    2 -> {
      use date <- decode.field("date", decode.string)
      use state <- decode.field("state", decode.list(term_decoder()))
      use moves <- decode.field("moves", decode.list(move_decoder()))
      use count <- decode.field("count", decode.int)
      use solved <- decode.field("solved", decode.bool)
      use reported <- decode.field("reported", decode.bool)
      case state {
        // three slots or it is not this toy's board
        [_, _, _] ->
          decode.success(Attempt(
            date: date,
            state: state,
            moves: moves,
            count: count,
            solved: solved,
            reported: reported,
          ))
        _ -> decode.failure(empty_attempt(), "three dial terms")
      }
    }
    // v1 (four terms) is stale by the bump — and so is anything newer
    _ -> decode.failure(empty_attempt(), "version 2")
  }
}

fn empty_attempt() -> Attempt {
  Attempt(
    date: "",
    state: [],
    moves: [],
    count: 0,
    solved: False,
    reported: False,
  )
}

fn term_json(t: TermState) -> json.Json {
  json.object([
    #("k", json.int(t.k)),
    #("r", json.float(t.r)),
    #("phase", json.float(t.phase_deg)),
  ])
}

fn term_decoder() -> decode.Decoder(TermState) {
  use k <- decode.field("k", decode.int)
  use r <- decode.field("r", number_decoder())
  use phase <- decode.field("phase", number_decoder())
  decode.success(shapes.TermState(k, r, phase))
}

fn move_decoder() -> decode.Decoder(Move) {
  decode.then(decode.list(decode.int), fn(values) {
    case values {
      [slot, dir] -> decode.success(#(slot, dir))
      _ -> decode.failure(#(0, 0), "a [slot, dir] pair")
    }
  })
}

/// A JSON number as a Float: whole numbers arrive as ints from JS's
/// `JSON.stringify` and from hand-edited storage alike.
fn number_decoder() -> decode.Decoder(Float) {
  decode.one_of(decode.float, or: [decode.map(decode.int, int.to_float)])
}
