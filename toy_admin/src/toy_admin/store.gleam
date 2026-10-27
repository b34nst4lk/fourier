//// The SQLite store: puzzles and attempt telemetry, one file in a volume.
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
//// Schema
//// ------
////   puzzles(
////     id         INTEGER PRIMARY KEY,
////     name       TEXT NOT NULL,
////     show_date  TEXT NOT NULL,          -- ISO "YYYY-MM-DD", or '' for a
////                                        -- DRAFT (see below); lexicographic
////                                        -- order == calendar order
////                                        -- (dates.gleam's convention)
////     dots       TEXT NOT NULL,          -- JSON: the drawing, source of truth
////     fixture    TEXT NOT NULL,          -- JSON: the derived fixture
////     created_at INTEGER NOT NULL,       -- epoch seconds
////     updated_at INTEGER NOT NULL,
////     status     TEXT NOT NULL DEFAULT 'published',  -- 'published' | 'draft'
////     creator    TEXT NOT NULL DEFAULT 'human'       -- 'human' | an agent id
////   )
////   CREATE UNIQUE INDEX puzzles_published_date
////     ON puzzles (show_date) WHERE status = 'published';
////
//// Drafts
//// ------
//// A DRAFT is a puzzle with no date: a local agent (Hermes) inserts undated
//// shapes with `insert_draft`, a human approves one by giving it a date
//// (`publish`), and `unpublish` takes the date away again. The two facts are
//// kept apart on purpose — `show_date = ''` is what the schedule reads, and
//// `status` is what the row is — because every query that must not see a draft
//// filters on `status`, and every human-facing screen shows both.
////
//// The date rule is a PARTIAL unique index, not an inline `UNIQUE` on the
//// column: an inline one would make every draft collide with every other draft
//// on ''. SQLite cannot drop an inline constraint, so `migrate_puzzles` REBUILDS
//// the table and `indexes_sql` installs the rule as an index over published rows
//// only. The index stays the authority, exactly as a table constraint would: a
//// racing publish loses to it and is reported as DuplicateShowDate.
////   attempts(
////     uuid        TEXT NOT NULL,         -- anonymous v4 identity
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
//// Splitting `moves` (JSON or NULL) from `move_count` (always an integer) keeps
//// every row's count as a number — the uniform-stats treatment — without parsing
//// JSON inside SQL for the abandon half. `updated_at` exists because a re-sent
//// solve REPLACES its row; `created_at` keeps the attempt's first sighting.
////
//// Refusals that live here rather than in the route layer
//// -----------------------------------------------------
//// - a show_date that `dates.is_valid_date` rejects on the CREATE path (a
////   free-form date would poison ordering and every per-date aggregate). The
////   date-format rule is the ROUTE's for the schedule actions (publish takes
////   whatever date the route validated — see its own note);
//// - a DUPLICATE show_date among PUBLISHED puzzles — the partial unique index is
////   the authority, so a race cannot slip a second puzzle onto a day;
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
    /// See the schema note: 'published' or 'draft'.
    status: String,
    /// 'human', or the agent id that drafted the puzzle.
    creator: String,
  )
}

/// The two statuses a row can be in. Named constants because they are compared
/// in queries and in the route layer, and a typo in a string literal would be a
/// silent behaviour change rather than a compile error.
pub const status_published = "published"

pub const status_draft = "draft"

/// The creator of every puzzle a human saved. An agent's drafts carry the
/// agent's id (AGENT_ID) instead.
pub const creator_human = "human"

/// A partial update from the admin editor. `None` means "leave this column as
/// it is". A drawing change always arrives paired with its re-derived fixture —
/// the route layer owns derivation, so the store never stores dots without the
/// fixture that belongs to them.
///
/// `show_date` carries the whole schedule: `Some("")` means DRAFT (no date, and
/// the same write may still change the name, the dots and the fixture), `Some`
/// a date means PUBLISHED on it. `None` leaves the schedule untouched, so a
/// name-only edit of a draft does not silently publish it.
pub type PuzzleUpdate {
  PuzzleUpdate(
    name: option.Option(String),
    show_date: option.Option(String),
    dots_json: option.Option(String),
    fixture_json: option.Option(String),
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
  /// A puzzle for that show_date already exists.
  DuplicateShowDate(show_date: String)
  /// `dates.is_valid_date` rejected the date before it reached SQLite.
  InvalidShowDate(show_date: String)
  /// A solve payload that is not a JSON array of moves.
  InvalidMoves(detail: String)
  /// No puzzle is published for that date (nothing may be recorded for it).
  UnknownPuzzle(show_date: String)
  /// No puzzle row holds that id (admin reads/edits/deletes by id).
  UnknownPuzzleId(id: Int)
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

/// Create the tables if they are not there yet, and bring an older database up
/// to the current shape. Idempotent: a container restart runs this again
/// against the same volume.
///
/// Order matters. The tables come first (so a fresh database needs no
/// migration), then `migrate_puzzles` (which finds nothing to do on a fresh
/// one), then the indexes — the partial unique index names a `status` column
/// that only exists after the migration.
pub fn init(path: String) -> Result(Nil, Error) {
  with_connection(path, fn(connection) {
    use Nil <- result.try(exec(tables_sql(), on: connection))
    use Nil <- result.try(migrate_puzzles(connection))
    exec(indexes_sql(), on: connection)
  })
}

fn tables_sql() -> String {
  [
    "PRAGMA busy_timeout = 5000;",
    "CREATE TABLE IF NOT EXISTS puzzles (
       id INTEGER PRIMARY KEY,
       name TEXT NOT NULL,
       show_date TEXT NOT NULL,
       dots TEXT NOT NULL,
       fixture TEXT NOT NULL,
       created_at INTEGER NOT NULL,
       updated_at INTEGER NOT NULL,
       status TEXT NOT NULL DEFAULT 'published',
       creator TEXT NOT NULL DEFAULT 'human'
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
  ]
  |> string.concat
}

fn indexes_sql() -> String {
  [
    "CREATE INDEX IF NOT EXISTS attempts_by_puzzle ON attempts (puzzle_id);",
    // The date rule as a PARTIAL index: two published puzzles may not share a
    // day, but every draft shares '' — an inline table-level UNIQUE cannot
    // express that (see the header).
    "CREATE UNIQUE INDEX IF NOT EXISTS puzzles_published_date
       ON puzzles (show_date) WHERE status = 'published';",
  ]
  |> string.concat
}

/// Bring a pre-drafts database up to the current shape. A database created
/// before drafts has no `status` column; adding the two columns would be enough
/// for the data, but the inline `UNIQUE(show_date)` would keep every draft
/// colliding with every other draft, and SQLite cannot drop an inline
/// constraint. So this is the documented rebuild: rename, create the current
/// shape, copy the rows across (the new columns take their defaults in the
/// INSERT), drop the old table. The old table's indexes go with it when it is
/// dropped, and `indexes_sql` — which runs after this — installs the current
/// set.
///
/// The `status` column's presence IS the version marker: the schema is
/// otherwise declarative (CREATE ... IF NOT EXISTS), and this is the one
/// question the database has to be asked. The four statements run in ONE
/// transaction: a failure that lands between RENAME and DROP must roll fully
/// back, or the next boot would see a fresh empty `puzzles` with the `status`
/// column, treat the migration as done, and strand the data in
/// `puzzles_phase_4a` forever.
fn migrate_puzzles(connection: sqlight.Connection) -> Result(Nil, Error) {
  use columns <- result.try(puzzle_columns_of(connection))
  case list.contains(columns, "status") {
    True -> Ok(Nil)
    False -> exec("BEGIN IMMEDIATE;
         ALTER TABLE puzzles RENAME TO puzzles_phase_4a;
         CREATE TABLE puzzles (
           id INTEGER PRIMARY KEY,
           name TEXT NOT NULL,
           show_date TEXT NOT NULL,
           dots TEXT NOT NULL,
           fixture TEXT NOT NULL,
           created_at INTEGER NOT NULL,
           updated_at INTEGER NOT NULL,
           status TEXT NOT NULL DEFAULT 'published',
           creator TEXT NOT NULL DEFAULT 'human'
         );
         INSERT INTO puzzles
           (id, name, show_date, dots, fixture, created_at, updated_at,
            status, creator)
         SELECT id, name, show_date, dots, fixture, created_at, updated_at,
                '" <> status_published <> "', '" <> creator_human <> "'
         FROM puzzles_phase_4a;
         DROP TABLE puzzles_phase_4a;
         COMMIT;", on: connection)
  }
}

fn puzzle_columns_of(
  connection: sqlight.Connection,
) -> Result(List(String), Error) {
  query(
    "PRAGMA table_info(puzzles)",
    on: connection,
    with: [],
    expecting: column_name_decoder(),
  )
}

// ---------- puzzles ----------

/// Save a PUBLISHED, human-authored puzzle. Refuses an invalid date
/// (`InvalidShowDate`) and a date that is already taken (`DuplicateShowDate`).
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
          option.None ->
            insert_puzzle_row(
              connection,
              name,
              show_date,
              dots_json,
              fixture_json,
              status_published,
              creator_human,
            )
        }
      })
  }
}

/// Save an UNDATED draft: no show_date at all, so it cannot be served and cannot
/// collide with a published day. `creator` is the agent id that drew it
/// (`AGENT_ID`); a human's puzzle is `creator_human`.
///
/// No date rule applies here — there is no date. Everything else the route
/// layer validated (a non-empty name, a drawing that derives a usable fixture)
/// arrives already checked, because derivation belongs to the routes.
pub fn insert_draft(
  path: String,
  name name: String,
  dots_json dots_json: String,
  fixture_json fixture_json: String,
  creator creator: String,
) -> Result(Puzzle, Error) {
  with_connection(path, fn(connection) {
    insert_puzzle_row(
      connection,
      name,
      "",
      dots_json,
      fixture_json,
      status_draft,
      creator,
    )
  })
}

/// The one INSERT for both kinds of row; returns the row it wrote. The date
/// uniqueness comes from the partial index rather than a pre-check alone, so a
/// racing insert loses to the database and is still reported as a duplicate.
fn insert_puzzle_row(
  connection: sqlight.Connection,
  name: String,
  show_date: String,
  dots_json: String,
  fixture_json: String,
  status: String,
  creator: String,
) -> Result(Puzzle, Error) {
  let now = clock.now_seconds()
  case
    sqlight.query(
      "INSERT INTO puzzles
         (name, show_date, dots, fixture, created_at, updated_at, status, creator)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      on: connection,
      with: [
        sqlight.text(name),
        sqlight.text(show_date),
        sqlight.text(dots_json),
        sqlight.text(fixture_json),
        sqlight.int(now),
        sqlight.int(now),
        sqlight.text(status),
        sqlight.text(creator),
      ],
      expecting: decode.success(Nil),
    )
  {
    Ok(_) -> row_by_rowid(connection)
    Error(error) ->
      // The partial unique index is the real guard — a racing insert can slip
      // between a check elsewhere and this statement. A duplicate is still a
      // duplicate.
      case is_unique_violation(error) {
        True -> Error(DuplicateShowDate(show_date))
        False -> Error(db_error(error))
      }
  }
}

/// The row the previous statement on this connection wrote. `last_insert_rowid()`
/// rather than RETURNING keeps the INSERT statement readable; both are read on
/// the same connection, so no other write can interleave.
fn row_by_rowid(connection: sqlight.Connection) -> Result(Puzzle, Error) {
  use rows <- result.try(query(
    puzzle_columns() <> " FROM puzzles WHERE id = last_insert_rowid()",
    on: connection,
    with: [],
    expecting: puzzle_decoder(),
  ))
  case head(rows) {
    option.Some(puzzle) -> Ok(puzzle)
    // Cannot happen: the insert just succeeded on this connection.
    option.None -> Error(Database("puzzle vanished after insert"))
  }
}

/// Every puzzle, newest show_date first (the admin menu's order).
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

/// The puzzle with exactly that id, if any.
pub fn puzzle_by_id(
  path: String,
  id: Int,
) -> Result(option.Option(Puzzle), Error) {
  with_connection(path, fn(connection) { find_puzzle_by_id(connection, id) })
}

/// Update the PROVIDED columns of one puzzle: `None` leaves a column alone.
/// `updated_at` moves, `created_at` never does.
///
/// The schedule half is `show_date` (see PuzzleUpdate): `Some("")` drafts the
/// puzzle (no date, status 'draft'), `Some(date)` publishes it on that date,
/// `None` leaves both alone.
///
/// Refusals: an unknown id (`UnknownPuzzleId`), an invalid date
/// (`InvalidShowDate` — the empty date is not an invalid date, it is the draft
/// marker), and a show_date another PUBLISHED puzzle already holds
/// (`DuplicateShowDate`, from the partial unique index). A puzzle holding its
/// own date is NOT a collision — the index only sees other rows, so a no-op
/// date change succeeds. The index is still the authority: a racing update
/// loses to it and is reported the same way.
pub fn update_puzzle(
  path: String,
  id: Int,
  changes changes: PuzzleUpdate,
) -> Result(Puzzle, Error) {
  case changes.show_date {
    option.Some("") -> write_update(path, id, changes)
    option.Some(show_date) ->
      case dates.is_valid_date(show_date) {
        False -> Error(InvalidShowDate(show_date))
        True -> write_update(path, id, changes)
      }
    option.None -> write_update(path, id, changes)
  }
}

/// Give an undated draft its show-date: the human's approval. A thin spelling
/// of `update_puzzle(id, PuzzleUpdate(show_date: Some(date)))`, so approve and
/// edit share one write path (and one uniqueness rule).
///
/// The date FORMAT is not checked here: the route layer validates the schedule
/// actions before calling (see the header's note on refusals), and publish is
/// also how an already-published puzzle moves to another day.
pub fn publish(
  path: String,
  id: Int,
  show_date: String,
) -> Result(Puzzle, Error) {
  update_puzzle(
    path,
    id,
    PuzzleUpdate(
      name: option.None,
      show_date: option.Some(show_date),
      dots_json: option.None,
      fixture_json: option.None,
    ),
  )
}

/// Take the show-date away again: the row becomes a draft. Its attempts stay
/// (telemetry is keyed by puzzle_date, and unpublishing never deletes).
pub fn unpublish(path: String, id: Int) -> Result(Puzzle, Error) {
  update_puzzle(
    path,
    id,
    PuzzleUpdate(
      name: option.None,
      show_date: option.Some(""),
      dots_json: option.None,
      fixture_json: option.None,
    ),
  )
}

/// The status a row must carry once `show_date` has the value the caller asked
/// for: a date means published, '' means draft. The two columns are derived
/// together on every write, so they cannot drift apart.
fn status_of_show_date(show_date: String) -> String {
  case show_date {
    "" -> status_draft
    _ -> status_published
  }
}

fn write_update(
  path: String,
  id: Int,
  changes: PuzzleUpdate,
) -> Result(Puzzle, Error) {
  with_connection(path, fn(connection) {
    use existing <- result.try(require_puzzle_id(connection, id))
    case
      changes.name,
      changes.show_date,
      changes.dots_json,
      changes.fixture_json
    {
      // Nothing provided: a coherent no-op. The row comes back unchanged and
      // `updated_at` does not move — nothing was edited.
      option.None, option.None, option.None, option.None -> Ok(existing)
      _, _, _, _ -> {
        let name = option.unwrap(changes.name, existing.name)
        let show_date = option.unwrap(changes.show_date, existing.show_date)
        let dots = option.unwrap(changes.dots_json, existing.dots_json)
        let fixture = option.unwrap(changes.fixture_json, existing.fixture_json)
        // The schedule and the status are written together: see
        // status_of_show_date.
        let status = status_of_show_date(show_date)
        case
          sqlight.query(
            "UPDATE puzzles
               SET name = ?, show_date = ?, dots = ?, fixture = ?, status = ?,
                   updated_at = ?
             WHERE id = ?",
            on: connection,
            with: [
              sqlight.text(name),
              sqlight.text(show_date),
              sqlight.text(dots),
              sqlight.text(fixture),
              sqlight.text(status),
              sqlight.int(clock.now_seconds()),
              sqlight.int(id),
            ],
            expecting: decode.success(Nil),
          )
        {
          Ok(_) -> {
            use updated <- result.try(find_puzzle_by_id(connection, id))
            case updated {
              option.Some(puzzle) -> Ok(puzzle)
              // Cannot happen: the UPDATE above just matched this id.
              option.None -> Error(Database("puzzle vanished after update"))
            }
          }
          Error(error) ->
            case is_unique_violation(error) {
              True -> Error(DuplicateShowDate(show_date))
              False -> Error(db_error(error))
            }
        }
      }
    }
  })
}

/// Delete one puzzle. `Ok(False)` when no row holds that id.
///
/// Attempts are KEPT: there is no foreign key and no cascade (see the schema
/// note at the top) — telemetry outlives the puzzle it describes.
pub fn delete_puzzle(path: String, id: Int) -> Result(Bool, Error) {
  with_connection(path, fn(connection) {
    use found <- result.try(find_puzzle_by_id(connection, id))
    case found {
      option.None -> Ok(False)
      option.Some(_) ->
        case
          query(
            "DELETE FROM puzzles WHERE id = ?",
            on: connection,
            with: [sqlight.int(id)],
            expecting: decode.success(Nil),
          )
        {
          Ok(_) -> Ok(True)
          Error(error) -> Error(error)
        }
    }
  })
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

/// The newest PUBLISHED show_date — the never-past ceiling of the serving rule.
/// Drafts are invisible to it: a dateless draft has no date to be the ceiling,
/// and an approved one enters the ceiling the moment it is published. `None`
/// when nothing is published yet.
///
/// The "never newer than today" half of the rule is `dates.serve_date`'s (it
/// clamps the visitor's local date), so this query is only the maximum.
pub fn newest_published(path: String) -> Result(option.Option(String), Error) {
  with_connection(path, fn(connection) {
    use rows <- result.try(query(
      "SELECT MAX(show_date) AS newest FROM puzzles WHERE status = ?",
      on: connection,
      with: [sqlight.text(status_published)],
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
/// (`Ok`): the toy cannot abandon after solving.
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

/// (attempts, solves) for one puzzle — the attempts / solves / solve % stats.
/// Median moves comes from `move_counts` (computed in `stats.gleam`), not SQL.
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

/// The raw move counts of every attempt for one puzzle, ascending. The median
/// is computed in Gleam (`stats.gleam`) because SQLite has no median
/// aggregate; this primitive keeps the calculation testable and the SQL trivial.
pub fn move_counts(path: String, puzzle_id: Int) -> Result(List(Int), Error) {
  with_connection(path, fn(connection) {
    query(
      "SELECT move_count FROM attempts
        WHERE puzzle_id = ?
        ORDER BY move_count ASC",
      on: connection,
      with: [sqlight.int(puzzle_id)],
      expecting: move_count_decoder(),
    )
  })
}

fn puzzle_columns() -> String {
  "SELECT id, name, show_date, dots, fixture, created_at, updated_at, status, creator"
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

fn find_puzzle_by_id(
  connection: sqlight.Connection,
  id: Int,
) -> Result(option.Option(Puzzle), Error) {
  use rows <- result.try(query(
    puzzle_columns() <> " FROM puzzles WHERE id = ?",
    on: connection,
    with: [sqlight.int(id)],
    expecting: puzzle_decoder(),
  ))
  Ok(head(rows))
}

fn require_puzzle_id(
  connection: sqlight.Connection,
  id: Int,
) -> Result(Puzzle, Error) {
  use found <- result.try(find_puzzle_by_id(connection, id))
  case found {
    option.Some(puzzle) -> Ok(puzzle)
    option.None -> Error(UnknownPuzzleId(id))
  }
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
  use status <- decode.field(7, decode.string)
  use creator <- decode.field(8, decode.string)
  decode.success(Puzzle(
    id: id,
    name: name,
    show_date: show_date,
    dots_json: dots,
    fixture_json: fixture,
    created_at: created_at,
    updated_at: updated_at,
    status: status,
    creator: creator,
  ))
}

fn column_name_decoder() -> decode.Decoder(String) {
  // PRAGMA table_info: column 1 is the column's name.
  use name <- decode.field(1, decode.string)
  decode.success(name)
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

fn move_count_decoder() -> decode.Decoder(Int) {
  use move_count <- decode.field(0, decode.int)
  decode.success(move_count)
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
