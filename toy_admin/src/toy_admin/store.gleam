//// The SQLite store (PLAN-daily-puzzles.md §3 Q14): puzzles and attempt
//// telemetry, one file in a volume.
////
//// Shape of the API
//// ----------------
//// Every function takes the database PATH and leaves the connection behind: it
//// opens, works, closes. That is the whole reason the tests can drive a scratch
//// file per test, and it keeps the route layer honest — the store has no hidden
//// global state, and the route resolves the path from the environment (see
//// `path_from_env`).
////
//// One connection per call is also the concurrency story: SQLite serialises
//// writers, and each connection sets `busy_timeout` so concurrent requests wait
//// instead of failing with SQLITE_BUSY. Writes here are single-row and rare (a
//// save, a solve), so the default rollback journal keeps it to ONE file — no
//// -wal/-shm siblings to mount and no checkpointing to reason about.
////
//// Schema (plan §3; attempts' exact shape chosen here)
//// ---------------------------------------------------
////   puzzles(
////     id         INTEGER PRIMARY KEY,
////     name       TEXT NOT NULL,
////     show_date  TEXT NOT NULL UNIQUE,   -- ISO "YYYY-MM-DD"; lexicographic
////                                        -- order == calendar order
////                                        -- (dates.gleam's convention)
////     dots       TEXT NOT NULL,          -- JSON: the drawing, source of truth
////     fixture    TEXT NOT NULL,          -- JSON: the derived fixture (Q2/Q19)
////     created_at INTEGER NOT NULL,       -- epoch seconds
////     updated_at INTEGER NOT NULL
////   )
////   attempts(
////     uuid        TEXT NOT NULL,         -- anonymous v4 identity (Q16)
////     puzzle_date TEXT NOT NULL,         -- ISO date; the puzzle's show_date
////     puzzle_id   INTEGER NOT NULL,      -- denormalised for per-puzzle stats
////                                        -- (no FK: this is telemetry, deleting
////                                        -- a puzzle keeps its rows)
////     solved      INTEGER NOT NULL,      -- 1 = solve, 0 = abandon
////     moves       TEXT,                  -- solve rows: JSON move list;
////                                        -- abandon rows: NULL
////     move_count  INTEGER NOT NULL,      -- solve: the list's length;
////                                        -- abandon: the client's count
////     created_at  INTEGER NOT NULL,
////     updated_at  INTEGER NOT NULL,
////     PRIMARY KEY (uuid, puzzle_date)    -- ONE attempt row per player per day
////   )
////
//// The plan sketched attempts with a single nullable `moves` column ("solve
//// rows carry the move list, abandon rows only the count"). Splitting it into
//// `moves` (JSON or NULL) + `move_count` (always an integer) keeps every row's
//// count as a number — the plan's uniform-stats treatment — without parsing
//// JSON inside SQL for the abandon half. `updated_at` exists because a re-sent
//// solve REPLACES its row; `created_at` keeps the attempt's first sighting.
////
//// Refusals that live here rather than in the route layer
//// -----------------------------------------------------
//// - a show_date that `dates.is_valid_date` rejects (a free-form date would
////   poison ordering and every per-date aggregate);
//// - a DUPLICATE show_date (Q17) — the UNIQUE constraint is the authority, so a
////   race cannot slip a second puzzle in;
//// - a solve/abandon for a date with no puzzle (`UnknownPuzzle`): telemetry for
////   an unpublished day would corrupt the aggregates;
//// - an abandon that would overwrite a solved row: solved stays solved.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import sqlight
import toy_admin/clock
import toy_admin/dates
import toy_admin/env

/// The environment variable the route layer and `main` read the database path
/// from. Compose sets it to `/app/data/toy_admin.sqlite3` (the named volume).
pub const database_path_env = "DB_PATH"

/// Used when `DB_PATH` is unset (a bare `gleam run` in a checkout).
pub const default_database_path = "data/toy_admin.sqlite3"

/// A stored puzzle row. `dots_json` and `fixture_json` are the verbatim JSON
/// documents the admin saved; the store never interprets them.
pub type Puzzle {
  Puzzle(
    id: Int,
    name: String,
    show_date: String,
    dots_json: String,
    fixture_json: String,
    created_at: Int,
    updated_at: Int,
  )
}

/// A stored attempt row: one per (uuid, puzzle_date).
pub type Attempt {
  Attempt(
    uuid: String,
    puzzle_date: String,
    puzzle_id: Int,
    solved: Bool,
    /// The move list on a solve row, `None` on an abandon row.
    moves_json: option.Option(String),
    /// Solve rows: the move list's length. Abandon rows: the client's count.
    move_count: Int,
    created_at: Int,
    updated_at: Int,
  )
}

pub type Error {
  /// The database refused the work (open/close, or a statement).
  Database(message: String)
  /// A puzzle for that show_date already exists (Q17).
  DuplicateShowDate(show_date: String)
  /// `dates.is_valid_date` rejected the date before it reached SQLite.
  InvalidShowDate(show_date: String)
  /// A solve payload that is not a JSON array of moves.
  InvalidMoves(detail: String)
  /// No puzzle is published for that date (nothing may be recorded for it).
  UnknownPuzzle(show_date: String)
}

// ---------- paths ----------

/// The database path from the environment, defaulting to
/// `data/toy_admin.sqlite3`. Read per request (one `os:getenv`, cheap) so a test
/// can aim a route at a scratch file.
pub fn path_from_env() -> String {
  path_from(env.get)
}

/// The path-selection rule, with the environment lookup injected so the rule
/// itself is testable without mutating the process environment.
pub fn path_from(get: fn(String) -> option.Option(String)) -> String {
  case get(database_path_env) {
    option.Some(path) ->
      case string.trim(path) {
        "" -> default_database_path
        path -> path
      }
    option.None -> default_database_path
  }
}

// ---------- schema ----------

/// Create the tables if they are not there yet. Idempotent: a container restart
/// runs this again against the same volume.
pub fn init(path: String) -> Result(Nil, Error) {
  with_connection(path, fn(connection) { exec(schema_sql(), on: connection) })
}

fn schema_sql() -> String {
  [
    "PRAGMA busy_timeout = 5000;",
    "CREATE TABLE IF NOT EXISTS puzzles (
       id INTEGER PRIMARY KEY,
       name TEXT NOT NULL,
       show_date TEXT NOT NULL UNIQUE,
       dots TEXT NOT NULL,
       fixture TEXT NOT NULL,
       created_at INTEGER NOT NULL,
       updated_at INTEGER NOT NULL
     );",
    "CREATE TABLE IF NOT EXISTS attempts (
       uuid TEXT NOT NULL,
       puzzle_date TEXT NOT NULL,
       puzzle_id INTEGER NOT NULL,
       solved INTEGER NOT NULL,
       moves TEXT,
       move_count INTEGER NOT NULL,
       created_at INTEGER NOT NULL,
       updated_at INTEGER NOT NULL,
       PRIMARY KEY (uuid, puzzle_date)
     );",
    "CREATE INDEX IF NOT EXISTS attempts_by_puzzle ON attempts (puzzle_id);",
  ]
  |> string.concat
}

// ---------- puzzles ----------

/// Save a puzzle. Refuses an invalid date (`InvalidShowDate`) and a date that is
/// already taken (`DuplicateShowDate`, Q17).
pub fn insert_puzzle(
  path: String,
  name name: String,
  show_date show_date: String,
  dots_json dots_json: String,
  fixture_json fixture_json: String,
) -> Result(Puzzle, Error) {
  case dates.is_valid_date(show_date) {
    False -> Error(InvalidShowDate(show_date))
    True ->
      with_connection(path, fn(connection) {
        use existing <- result.try(find_puzzle(connection, show_date))
        case existing {
          option.Some(_) -> Error(DuplicateShowDate(show_date))
          option.None -> {
            use Nil <- result.try(insert_puzzle_row(
              connection,
              name,
              show_date,
              dots_json,
              fixture_json,
            ))
            use inserted <- result.try(find_puzzle(connection, show_date))
            case inserted {
              option.Some(puzzle) -> Ok(puzzle)
              // Cannot happen: the insert just succeeded on this connection.
              option.None -> Error(Database("puzzle vanished after insert"))
            }
          }
        }
      })
  }
}

fn insert_puzzle_row(
  connection: sqlight.Connection,
  name: String,
  show_date: String,
  dots_json: String,
  fixture_json: String,
) -> Result(Nil, Error) {
  let now = clock.now_seconds()
  case
    sqlight.query(
      "INSERT INTO puzzles
         (name, show_date, dots, fixture, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)",
      on: connection,
      with: [
        sqlight.text(name),
        sqlight.text(show_date),
        sqlight.text(dots_json),
        sqlight.text(fixture_json),
        sqlight.int(now),
        sqlight.int(now),
      ],
      expecting: decode.success(Nil),
    )
  {
    Ok(_) -> Ok(Nil)
    Error(error) ->
      // The UNIQUE constraint is the real guard — a racing insert can slip
      // between the check above and this statement. A duplicate is still a
      // duplicate.
      case is_unique_violation(error) {
        True -> Error(DuplicateShowDate(show_date))
        False -> Error(db_error(error))
      }
  }
}

/// Every puzzle, newest show_date first (the admin menu's order, phase 4).
pub fn list_puzzles(path: String) -> Result(List(Puzzle), Error) {
  with_connection(path, fn(connection) {
    query(
      puzzle_columns() <> " FROM puzzles ORDER BY show_date DESC, id DESC",
      on: connection,
      with: [],
      expecting: puzzle_decoder(),
    )
  })
}

/// The puzzle for exactly that show_date, if any.
pub fn puzzle_by_date(
  path: String,
  show_date: String,
) -> Result(option.Option(Puzzle), Error) {
  with_connection(path, fn(connection) { find_puzzle(connection, show_date) })
}

pub fn count_puzzles(path: String) -> Result(Int, Error) {
  with_connection(path, fn(connection) {
    use rows <- result.try(query(
      "SELECT COUNT(*) AS count FROM puzzles",
      on: connection,
      with: [],
      expecting: count_decoder(),
    ))
    Ok(head(rows) |> option.unwrap(0))
  })
}

/// The newest published show_date — the never-past ceiling of the serving rule
/// (Q11). `None` when nothing is published yet.
pub fn newest_published(path: String) -> Result(option.Option(String), Error) {
  with_connection(path, fn(connection) {
    use rows <- result.try(query(
      "SELECT MAX(show_date) AS newest FROM puzzles",
      on: connection,
      with: [],
      expecting: newest_decoder(),
    ))
    Ok(head(rows) |> option.unwrap(option.None))
  })
}

// ---------- attempts ----------

/// Record a solve. Upsert on (uuid, puzzle_date): a re-sent solve REPLACES the
/// row (the client may retry; the last record wins). Refuses a date with no
/// puzzle (`UnknownPuzzle`) and a moves payload that is not a JSON array.
pub fn attempt_record_solve(
  path: String,
  uuid: String,
  puzzle_date: String,
  moves_json: String,
) -> Result(Nil, Error) {
  case move_count_of(moves_json) {
    Error(error) -> Error(error)
    Ok(move_count) ->
      with_connection(path, fn(connection) {
        use puzzle <- result.try(require_puzzle(connection, puzzle_date))
        let now = clock.now_seconds()
        execute(
          "INSERT INTO attempts
             (uuid, puzzle_date, puzzle_id, solved, moves, move_count,
              created_at, updated_at)
           VALUES (?, ?, ?, 1, ?, ?, ?, ?)
           ON CONFLICT (uuid, puzzle_date) DO UPDATE SET
             puzzle_id = excluded.puzzle_id,
             solved = 1,
             moves = excluded.moves,
             move_count = excluded.move_count,
             updated_at = excluded.updated_at",
          on: connection,
          with: [
            sqlight.text(uuid),
            sqlight.text(puzzle_date),
            sqlight.int(puzzle.id),
            sqlight.text(moves_json),
            sqlight.int(move_count),
            sqlight.int(now),
            sqlight.int(now),
          ],
        )
      })
  }
}

/// Record an abandon: an unsolved attempt carrying the client's move count.
/// Refuses a date with no puzzle. NEVER overwrites a solved row — a solved
/// attempt stays solved with its move list, and a late abandon is a non-event
/// (`Ok`), per the plan's "the toy cannot abandon after solving" reasoning.
pub fn attempt_record_abandon(
  path: String,
  uuid: String,
  puzzle_date: String,
  move_count: Int,
) -> Result(Nil, Error) {
  with_connection(path, fn(connection) {
    use puzzle <- result.try(require_puzzle(connection, puzzle_date))
    let now = clock.now_seconds()
    execute(
      "INSERT INTO attempts
         (uuid, puzzle_date, puzzle_id, solved, moves, move_count,
          created_at, updated_at)
       VALUES (?, ?, ?, 0, NULL, ?, ?, ?)
       ON CONFLICT (uuid, puzzle_date) DO UPDATE SET
         puzzle_id = excluded.puzzle_id,
         move_count = excluded.move_count,
         updated_at = excluded.updated_at
       WHERE attempts.solved = 0",
      on: connection,
      with: [
        sqlight.text(uuid),
        sqlight.text(puzzle_date),
        sqlight.int(puzzle.id),
        sqlight.int(move_count),
        sqlight.int(now),
        sqlight.int(now),
      ],
    )
  })
}

/// The attempt row for one player and day, if this player has one.
pub fn attempt_for(
  path: String,
  uuid: String,
  puzzle_date: String,
) -> Result(option.Option(Attempt), Error) {
  with_connection(path, fn(connection) {
    use rows <- result.try(query(
      "SELECT uuid, puzzle_date, puzzle_id, solved, moves, move_count,
                created_at, updated_at
         FROM attempts WHERE uuid = ? AND puzzle_date = ?",
      on: connection,
      with: [sqlight.text(uuid), sqlight.text(puzzle_date)],
      expecting: attempt_decoder(),
    ))
    Ok(head(rows))
  })
}

/// (attempts, solves) for one puzzle. The plan's minimal stats (Q23) are
/// attempts / solves / solve %; median moves is deferred with the rest of the
/// aggregate endpoint.
pub fn stats(path: String, puzzle_id: Int) -> Result(#(Int, Int), Error) {
  with_connection(path, fn(connection) {
    use rows <- result.try(query(
      "SELECT COUNT(*) AS attempts, COALESCE(SUM(solved), 0) AS solves
         FROM attempts WHERE puzzle_id = ?",
      on: connection,
      with: [sqlight.int(puzzle_id)],
      expecting: stats_decoder(),
    ))
    Ok(head(rows) |> option.unwrap(#(0, 0)))
  })
}

// ---------- internals ----------

fn puzzle_columns() -> String {
  "SELECT id, name, show_date, dots, fixture, created_at, updated_at"
}

fn find_puzzle(
  connection: sqlight.Connection,
  show_date: String,
) -> Result(option.Option(Puzzle), Error) {
  use rows <- result.try(query(
    puzzle_columns() <> " FROM puzzles WHERE show_date = ?",
    on: connection,
    with: [sqlight.text(show_date)],
    expecting: puzzle_decoder(),
  ))
  Ok(head(rows))
}

fn require_puzzle(
  connection: sqlight.Connection,
  puzzle_date: String,
) -> Result(Puzzle, Error) {
  use found <- result.try(find_puzzle(connection, puzzle_date))
  case found {
    option.Some(puzzle) -> Ok(puzzle)
    option.None -> Error(UnknownPuzzle(puzzle_date))
  }
}

/// Rows arrive as tuples (sqlight's shape), so decoders index positionally and
/// every SELECT lists its columns in this exact order — see `puzzle_columns`.
fn puzzle_decoder() -> decode.Decoder(Puzzle) {
  use id <- decode.field(0, decode.int)
  use name <- decode.field(1, decode.string)
  use show_date <- decode.field(2, decode.string)
  use dots <- decode.field(3, decode.string)
  use fixture <- decode.field(4, decode.string)
  use created_at <- decode.field(5, decode.int)
  use updated_at <- decode.field(6, decode.int)
  decode.success(Puzzle(
    id: id,
    name: name,
    show_date: show_date,
    dots_json: dots,
    fixture_json: fixture,
    created_at: created_at,
    updated_at: updated_at,
  ))
}

fn attempt_decoder() -> decode.Decoder(Attempt) {
  use uuid <- decode.field(0, decode.string)
  use puzzle_date <- decode.field(1, decode.string)
  use puzzle_id <- decode.field(2, decode.int)
  use solved <- decode.field(
    3,
    decode.map(decode.int, fn(value) { value != 0 }),
  )
  use moves <- decode.field(4, decode.optional(decode.string))
  use move_count <- decode.field(5, decode.int)
  use created_at <- decode.field(6, decode.int)
  use updated_at <- decode.field(7, decode.int)
  decode.success(Attempt(
    uuid: uuid,
    puzzle_date: puzzle_date,
    puzzle_id: puzzle_id,
    solved: solved,
    moves_json: moves,
    move_count: move_count,
    created_at: created_at,
    updated_at: updated_at,
  ))
}

fn count_decoder() -> decode.Decoder(Int) {
  use count <- decode.field(0, decode.int)
  decode.success(count)
}

fn newest_decoder() -> decode.Decoder(option.Option(String)) {
  use newest <- decode.field(0, decode.optional(decode.string))
  decode.success(newest)
}

fn stats_decoder() -> decode.Decoder(#(Int, Int)) {
  use attempts <- decode.field(0, decode.int)
  use solves <- decode.field(1, decode.int)
  decode.success(#(attempts, solves))
}

/// A solve payload's length, after checking it really is a JSON array of moves.
fn move_count_of(moves_json: String) -> Result(Int, Error) {
  case json.parse(moves_json, decode.list(decode.dynamic)) {
    Ok(moves) -> Ok(list.length(moves))
    Error(_) -> Error(InvalidMoves("not a JSON array"))
  }
}

fn is_unique_violation(error: sqlight.Error) -> Bool {
  case error {
    sqlight.SqlightError(code, _, _) ->
      case code {
        sqlight.Constraint
        | sqlight.ConstraintUnique
        | sqlight.ConstraintPrimarykey
        | sqlight.ConstraintNotnull -> True
        _ -> False
      }
  }
}

/// The first row, if the query returned any.
fn head(rows: List(a)) -> option.Option(a) {
  case rows {
    [first, ..] -> option.Some(first)
    [] -> option.None
  }
}

fn query(
  sql: String,
  on connection: sqlight.Connection,
  with arguments: List(sqlight.Value),
  expecting decoder: decode.Decoder(a),
) -> Result(List(a), Error) {
  sqlight.query(sql, on: connection, with: arguments, expecting: decoder)
  |> result.map_error(db_error)
}

fn exec(sql: String, on connection: sqlight.Connection) -> Result(Nil, Error) {
  sqlight.exec(sql, on: connection) |> result.map_error(db_error)
}

/// A statement whose rows nobody wants (INSERT/UPSERT).
fn execute(
  sql: String,
  on connection: sqlight.Connection,
  with arguments: List(sqlight.Value),
) -> Result(Nil, Error) {
  query(sql, on: connection, with: arguments, expecting: decode.success(Nil))
  |> result.replace(Nil)
}

fn with_connection(
  path: String,
  work: fn(sqlight.Connection) -> Result(a, Error),
) -> Result(a, Error) {
  use connection <- result.try(sqlight.open(path) |> result.map_error(db_error))
  let outcome = work(connection)
  // Closing a connection we are done with is not a failure mode worth
  // surfacing; the work's answer (or its error) is.
  let _ = sqlight.close(connection)
  outcome
}

fn db_error(error: sqlight.Error) -> Error {
  case error {
    sqlight.SqlightError(_, message, _) -> Database(message)
  }
}
