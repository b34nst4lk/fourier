//// Ingest validation (PLAN-daily-puzzles.md §2 Q22). Pure: the route layer
//// parses the JSON payload into these moves and asks this module whether the
//// record is trustworthy. Every problem is reported in one answer — the
//// client gets a complete diagnosis rather than a game of whack-a-mole.
////
//// Rules:
//// - uuid: canonical lowercase v4 (RFC 4122): 8-4-4-4-12 hex, version nibble
////   `4`, variant nibble 8/9/a/b. `crypto.randomUUID()` emits exactly this.
////   Rejecting other spellings keeps one player from minting two identities
////   with the same uuid re-cased.
//// - puzzleDate: a real "YYYY-MM-DD" (dates.is_valid_date) — a free-form
////   string here would poison every per-date aggregate.
//// - moves: at most 500 (the client caps the list at the first solve; this is
////   the server's own bound).
//// - each move: slot is one of the four dials (0..3), dir is −1 or +1.
////   A non-integer slot/dir is already a parse failure upstream.

import gleam/list
import gleam/string
import toy_admin/dates

pub const max_moves = 500

pub const last_slot = 3

pub type Move {
  Move(slot: Int, dir: Int)
}

pub type Problem {
  BadUuid
  BadPuzzleDate
  TooManyMoves(count: Int)
  BadSlot(index: Int, slot: Int)
  BadDirection(index: Int, dir: Int)
}

/// `Ok(Nil)` when the solve record is trustworthy; otherwise every problem
/// found, in a stable order (record-level first, then moves by index).
pub fn validate_solve(
  uuid: String,
  puzzle_date: String,
  moves: List(Move),
) -> Result(Nil, List(Problem)) {
  let count = list.length(moves)
  let record_problems =
    list.append(
      case is_uuid_v4(uuid) {
        True -> []
        False -> [BadUuid]
      },
      case dates.is_valid_date(puzzle_date) {
        True -> []
        False -> [BadPuzzleDate]
      },
    )
  let move_problems = case count > max_moves {
    // Over the cap the list is not walked move-by-move: the cap alone is the
    // answer, so a megabyte of junk cannot turn into a megabyte of problems.
    True -> [TooManyMoves(count)]
    False -> move_problems(moves, 0)
  }
  case list.append(record_problems, move_problems) {
    [] -> Ok(Nil)
    problems -> Error(problems)
  }
}

fn move_problems(moves: List(Move), index: Int) -> List(Problem) {
  case moves {
    [] -> []
    [move, ..rest] -> {
      let slot_problems = case move.slot >= 0 && move.slot <= last_slot {
        True -> []
        False -> [BadSlot(index, move.slot)]
      }
      let dir_problems = case move.dir == 1 || move.dir == -1 {
        True -> []
        False -> [BadDirection(index, move.dir)]
      }
      list.append(
        list.append(slot_problems, dir_problems),
        move_problems(rest, index + 1),
      )
    }
  }
}

const hex_digits = "0123456789abcdef"

const variant_nibbles = "89ab"

/// Canonical lowercase uuid v4 check: shape, hex digits, version and RFC 4122
/// variant nibble.
pub fn is_uuid_v4(uuid: String) -> Bool {
  case string.split(uuid, "-") {
    [time_low, time_mid, time_hi_and_version, clock_seq, node] ->
      string.length(time_low) == 8
      && string.length(time_mid) == 4
      && string.length(time_hi_and_version) == 4
      && string.length(clock_seq) == 4
      && string.length(node) == 12
      && all_hex(time_low)
      && all_hex(time_mid)
      && all_hex(time_hi_and_version)
      && all_hex(clock_seq)
      && all_hex(node)
      && string.slice(time_hi_and_version, 0, 1) == "4"
      && string.contains(variant_nibbles, string.slice(clock_seq, 0, 1))
    _ -> False
  }
}

fn all_hex(text: String) -> Bool {
  text
  |> string.to_graphemes
  |> list.all(fn(grapheme) { string.contains(hex_digits, grapheme) })
}
