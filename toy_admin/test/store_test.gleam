//// The SQLite store (PLAN-daily-puzzles.md §3 Q14/Q17): puzzles and attempts.
////
//// Every test drives its own scratch database file (helpers.temp_db_path), so
//// the store's "path in, result out" shape is what is under test — no hidden
//// global connection and no shared state between tests.
////
//// Attempt semantics pinned here:
//// - one row per (uuid, puzzle_date) — a solve resend REPLACES the row (the
////   client may retry);
//// - a solve/abandon requires the puzzle for that exact show-date to exist;
//// - an abandon never overwrites a solved row (a late abandon is a no-op).

import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/result
import gleeunit/should
import helpers
import toy_admin/store.{
  DuplicateShowDate, InvalidMoves, InvalidShowDate, UnknownPuzzle,
  UnknownPuzzleId,
}

const dots = "[[0.0,0.0],[10.0,0.0],[10.0,10.0]]"

const fixture =
  "{\"name\":\"Star\",\"showDate\":\"2026-10-25\",\"centroid\":[1.5,2.5],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[],\"extras\":[],\"target\":[]}"

// Two canonical v4 uuids (the shape crypto.randomUUID() emits).
const uuid_a = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"

const uuid_b = "9c858901-8a57-4791-81fe-4c455b099bc9"

const day = "2026-10-25"

fn setup(label: String) -> String {
  let path = helpers.temp_db_path(label)
  let assert Ok(Nil) = store.init(path)
  path
}

fn with_puzzle(label: String, show_date: String) -> #(String, store.Puzzle) {
  let path = setup(label)
  let assert Ok(puzzle) =
    store.insert_puzzle(path, "Star", show_date, dots, fixture)
  #(path, puzzle)
}

/// The attempt's (solved, moves, move count) — everything the behaviour under
/// test is about, without the timestamps.
fn attempt_shape(
  path: String,
  uuid: String,
  date: String,
) -> option.Option(#(Bool, option.Option(String), Int)) {
  let found = store.attempt_for(path, uuid, date)
  let shape =
    result.map(found, fn(attempt) {
      option.map(attempt, fn(attempt) {
        #(attempt.solved, attempt.moves_json, attempt.move_count)
      })
    })
  result.unwrap(shape, option.None)
}

// ---------- schema ----------

pub fn init_is_idempotent_test() {
  let path = helpers.temp_db_path("init")
  should.equal(Ok(Nil), store.init(path))
  // The migrations are CREATE ... IF NOT EXISTS: booting twice is normal
  // (container restart) and must not fail.
  should.equal(Ok(Nil), store.init(path))
}

pub fn empty_store_has_nothing_test() {
  let path = setup("empty")
  should.equal(Ok(0), store.count_puzzles(path))
  should.equal(Ok([]), store.list_puzzles(path))
  should.equal(Ok(option.None), store.newest_published(path))
  should.equal(Ok(option.None), store.puzzle_by_date(path, day))
}

// ---------- puzzles ----------

pub fn inserted_puzzle_reads_back_whole_test() {
  let path = setup("insert")
  let assert Ok(puzzle) = store.insert_puzzle(path, "Star", day, dots, fixture)

  should.equal("Star", puzzle.name)
  should.equal(day, puzzle.show_date)
  should.equal(dots, puzzle.dots_json)
  should.equal(fixture, puzzle.fixture_json)
  // Timestamps are epoch seconds, written once on insert.
  should.equal(True, puzzle.created_at > 0)
  should.equal(puzzle.created_at, puzzle.updated_at)

  should.equal(Ok(1), store.count_puzzles(path))
  should.equal(Ok([puzzle]), store.list_puzzles(path))
  should.equal(Ok(option.Some(puzzle)), store.puzzle_by_date(path, day))
}

pub fn duplicate_show_date_is_refused_test() {
  // Q17: one puzzle per day. The database refuses it (UNIQUE) and the store
  // answers with a domain error rather than a driver message.
  let path = setup("duplicate")
  let assert Ok(_) = store.insert_puzzle(path, "Star", day, dots, fixture)

  should.equal(
    Error(DuplicateShowDate(day)),
    store.insert_puzzle(path, "Other", day, dots, fixture),
  )
  // ...and the first puzzle is untouched.
  should.equal(Ok(1), store.count_puzzles(path))
  let found = store.puzzle_by_date(path, day)
  should.equal(
    Ok(option.Some("Star")),
    result.map(found, fn(puzzle) {
      option.map(puzzle, fn(puzzle) { puzzle.name })
    }),
  )
}

pub fn invalid_show_date_is_refused_test() {
  let path = setup("invalid-date")
  should.equal(
    Error(InvalidShowDate("2026-02-30")),
    store.insert_puzzle(path, "Nope", "2026-02-30", dots, fixture),
  )
  should.equal(
    Error(InvalidShowDate("25-10-2026")),
    store.insert_puzzle(path, "Nope", "25-10-2026", dots, fixture),
  )
  should.equal(Ok(0), store.count_puzzles(path))
}

pub fn newest_published_is_the_max_show_date_test() {
  // Insertion order is irrelevant: the newest PUBLISHED date wins, and the ISO
  // format makes that a string comparison (dates.gleam's convention).
  let path = setup("newest")
  let assert Ok(_) = store.insert_puzzle(path, "B", "2026-10-27", dots, fixture)
  let assert Ok(_) = store.insert_puzzle(path, "A", "2026-10-25", dots, fixture)
  let assert Ok(_) = store.insert_puzzle(path, "C", "2026-11-02", dots, fixture)
  let assert Ok(_) = store.insert_puzzle(path, "D", "2026-10-31", dots, fixture)

  should.equal(Ok(option.Some("2026-11-02")), store.newest_published(path))
}

pub fn list_puzzles_is_newest_first_test() {
  let path = setup("list")
  let assert Ok(_) = store.insert_puzzle(path, "A", "2026-10-25", dots, fixture)
  let assert Ok(_) = store.insert_puzzle(path, "C", "2026-11-02", dots, fixture)
  let assert Ok(_) = store.insert_puzzle(path, "B", "2026-10-27", dots, fixture)

  let assert Ok(puzzles) = store.list_puzzles(path)
  should.equal(
    ["2026-11-02", "2026-10-27", "2026-10-25"],
    list.map(puzzles, fn(puzzle) { puzzle.show_date }),
  )
}

pub fn puzzle_by_date_needs_the_exact_date_test() {
  let #(path, _puzzle) = with_puzzle("by-date", day)
  should.equal(Ok(option.None), store.puzzle_by_date(path, "2026-10-24"))
}

// ---------- attempts: solves ----------

pub fn solve_records_a_solved_attempt_test() {
  let #(path, puzzle) = with_puzzle("solve", day)
  let moves =
    "[{\"slot\":0,\"dir\":1},{\"slot\":2,\"dir\":-1},{\"slot\":1,\"dir\":1}]"

  should.equal(Ok(Nil), store.attempt_record_solve(path, uuid_a, day, moves))

  let assert Ok(option.Some(attempt)) = store.attempt_for(path, uuid_a, day)
  should.equal(uuid_a, attempt.uuid)
  should.equal(day, attempt.puzzle_date)
  should.equal(puzzle.id, attempt.puzzle_id)
  should.equal(True, attempt.solved)
  should.equal(option.Some(moves), attempt.moves_json)
  should.equal(3, attempt.move_count)
  should.equal(True, attempt.created_at > 0)
  should.equal(attempt.created_at, attempt.updated_at)

  should.equal(Ok(#(1, 1)), store.stats(path, puzzle.id))
}

pub fn solve_resend_replaces_the_row_test() {
  // The client may retry (Wordle-style resume): the second solve for the same
  // (uuid, date) replaces the first row instead of appending.
  let #(path, puzzle) = with_puzzle("solve-resend", day)
  let first = "[{\"slot\":0,\"dir\":1}]"
  let second = "[{\"slot\":0,\"dir\":1},{\"slot\":3,\"dir\":-1}]"

  should.equal(Ok(Nil), store.attempt_record_solve(path, uuid_a, day, first))
  should.equal(Ok(Nil), store.attempt_record_solve(path, uuid_a, day, second))

  should.equal(
    option.Some(#(True, option.Some(second), 2)),
    attempt_shape(path, uuid_a, day),
  )
  // One attempt, one solve — never two rows.
  should.equal(Ok(#(1, 1)), store.stats(path, puzzle.id))
}

pub fn solve_for_an_unknown_date_is_refused_test() {
  let path = setup("solve-unknown")
  should.equal(
    Error(UnknownPuzzle(day)),
    store.attempt_record_solve(path, uuid_a, day, "[]"),
  )
  should.equal(option.None, attempt_shape(path, uuid_a, day))
}

pub fn solve_for_a_different_published_date_is_refused_test() {
  // The date in the payload must be a puzzle that EXISTS, not merely a valid
  // date: telemetry for an unpublished day would corrupt every aggregate.
  let #(path, _puzzle) = with_puzzle("solve-wrong-date", "2026-10-25")
  should.equal(
    Error(UnknownPuzzle("2026-10-26")),
    store.attempt_record_solve(path, uuid_a, "2026-10-26", "[]"),
  )
}

pub fn solve_rejects_a_moves_payload_that_is_not_a_list_test() {
  let #(path, _puzzle) = with_puzzle("solve-bad-moves", day)
  should.equal(
    Error(InvalidMoves("not a JSON array")),
    store.attempt_record_solve(path, uuid_a, day, "{\"slot\":0}"),
  )
  should.equal(option.None, attempt_shape(path, uuid_a, day))
}

// ---------- attempts: abandons ----------

pub fn abandon_records_an_unsolved_attempt_test() {
  let #(path, puzzle) = with_puzzle("abandon", day)
  should.equal(Ok(Nil), store.attempt_record_abandon(path, uuid_a, day, 7))

  should.equal(
    option.Some(#(False, option.None, 7)),
    attempt_shape(path, uuid_a, day),
  )
  should.equal(Ok(#(1, 0)), store.stats(path, puzzle.id))
}

pub fn abandon_for_an_unknown_date_is_refused_test() {
  let path = setup("abandon-unknown")
  should.equal(
    Error(UnknownPuzzle(day)),
    store.attempt_record_abandon(path, uuid_a, day, 3),
  )
}

pub fn abandon_after_solve_never_overwrites_the_solve_test() {
  // The toy cannot abandon after solving, but a replayed or stale request
  // might. A solved row stays solved with its move list intact, and the store
  // answers ok — a late abandon is a non-event, not an error.
  let #(path, puzzle) = with_puzzle("abandon-after-solve", day)
  let moves = "[{\"slot\":0,\"dir\":1}]"
  should.equal(Ok(Nil), store.attempt_record_solve(path, uuid_a, day, moves))
  should.equal(Ok(Nil), store.attempt_record_abandon(path, uuid_a, day, 42))

  should.equal(
    option.Some(#(True, option.Some(moves), 1)),
    attempt_shape(path, uuid_a, day),
  )
  should.equal(Ok(#(1, 1)), store.stats(path, puzzle.id))
}

pub fn abandon_then_solve_upgrades_the_row_test() {
  let #(path, puzzle) = with_puzzle("abandon-then-solve", day)
  let moves = "[{\"slot\":1,\"dir\":-1}]"
  should.equal(Ok(Nil), store.attempt_record_abandon(path, uuid_a, day, 4))
  should.equal(Ok(Nil), store.attempt_record_solve(path, uuid_a, day, moves))

  should.equal(
    option.Some(#(True, option.Some(moves), 1)),
    attempt_shape(path, uuid_a, day),
  )
  should.equal(Ok(#(1, 1)), store.stats(path, puzzle.id))
}

pub fn abandon_resend_replaces_the_count_test() {
  let #(path, _puzzle) = with_puzzle("abandon-resend", day)
  should.equal(Ok(Nil), store.attempt_record_abandon(path, uuid_a, day, 4))
  should.equal(Ok(Nil), store.attempt_record_abandon(path, uuid_a, day, 9))

  should.equal(
    option.Some(#(False, option.None, 9)),
    attempt_shape(path, uuid_a, day),
  )
}

// ---------- stats ----------

pub fn stats_count_attempts_and_solves_per_puzzle_test() {
  let path = setup("stats")
  let assert Ok(first) =
    store.insert_puzzle(path, "A", "2026-10-25", dots, fixture)
  let assert Ok(second) =
    store.insert_puzzle(path, "B", "2026-10-26", dots, fixture)

  // Two players on the first puzzle, one solve; one player on the second.
  let assert Ok(Nil) =
    store.attempt_record_solve(path, uuid_a, "2026-10-25", "[]")
  let assert Ok(Nil) =
    store.attempt_record_abandon(path, uuid_b, "2026-10-25", 12)
  let assert Ok(Nil) =
    store.attempt_record_abandon(path, uuid_a, "2026-10-26", 1)

  should.equal(Ok(#(2, 1)), store.stats(path, first.id))
  should.equal(Ok(#(1, 0)), store.stats(path, second.id))
  // A puzzle id with no attempts at all is (0, 0), not an error.
  should.equal(Ok(#(0, 0)), store.stats(path, first.id + 100))
}

// ---------- phase 4a: admin CRUD primitives ----------

pub fn puzzle_by_id_reads_the_row_test() {
  let #(path, puzzle) = with_puzzle("by-id", day)
  should.equal(Ok(option.Some(puzzle)), store.puzzle_by_id(path, puzzle.id))
  // An id nobody holds is a `None`, not a driver error: the route turns it
  // into a 404.
  should.equal(Ok(option.None), store.puzzle_by_id(path, puzzle.id + 100))
}

pub fn update_changes_only_the_provided_fields_test() {
  // Partial update is the editor's contract: a name-only rename must leave the
  // drawing and the derived fixture byte-identical.
  let #(path, puzzle) = with_puzzle("update-partial", day)
  let assert Ok(updated) =
    store.update_puzzle(
      path,
      puzzle.id,
      store.PuzzleUpdate(
        name: option.Some("Renamed"),
        show_date: option.None,
        dots_json: option.None,
        fixture_json: option.None,
      ),
    )

  should.equal("Renamed", updated.name)
  should.equal(puzzle.show_date, updated.show_date)
  should.equal(puzzle.dots_json, updated.dots_json)
  should.equal(puzzle.fixture_json, updated.fixture_json)
  should.equal(puzzle.created_at, updated.created_at)
  should.equal(Ok(option.Some(updated)), store.puzzle_by_id(path, puzzle.id))
}

pub fn update_replaces_the_drawing_and_fixture_test() {
  let #(path, puzzle) = with_puzzle("update-dots", day)
  let new_dots = "[[5.0,5.0],[15.0,5.0],[15.0,15.0],[5.0,15.0]]"
  let new_fixture = "{\"name\":\"Star\",\"showDate\":\"2026-10-25\"}"
  let assert Ok(updated) =
    store.update_puzzle(
      path,
      puzzle.id,
      store.PuzzleUpdate(
        name: option.None,
        show_date: option.None,
        dots_json: option.Some(new_dots),
        fixture_json: option.Some(new_fixture),
      ),
    )

  should.equal(new_dots, updated.dots_json)
  should.equal(new_fixture, updated.fixture_json)
}

pub fn update_bumps_updated_at_but_not_created_at_test() {
  // Wall-clock seconds: the strict bump needs a real second to pass, so this
  // one test sleeps. The distinction matters — "solved at" reads created_at,
  // "last edited" reads updated_at.
  let #(path, puzzle) = with_puzzle("update-bump", day)
  process.sleep(1050)
  let assert Ok(updated) =
    store.update_puzzle(
      path,
      puzzle.id,
      store.PuzzleUpdate(
        name: option.Some("Renamed"),
        show_date: option.None,
        dots_json: option.None,
        fixture_json: option.None,
      ),
    )

  should.equal(puzzle.created_at, updated.created_at)
  should.be_true(updated.updated_at > puzzle.created_at)
}

pub fn update_may_keep_its_own_show_date_test() {
  // A no-op date change must not trip the UNIQUE constraint against itself:
  // the constraint is on other rows.
  let #(path, puzzle) = with_puzzle("update-self-date", day)
  should.equal(
    Ok(day),
    result.map(
      store.update_puzzle(
        path,
        puzzle.id,
        store.PuzzleUpdate(
          name: option.None,
          show_date: option.Some(day),
          dots_json: option.None,
          fixture_json: option.None,
        ),
      ),
      fn(updated) { updated.show_date },
    ),
  )
}

pub fn update_refuses_another_puzzles_show_date_test() {
  // Q17 applies to edits too: two puzzles on one day would make "the day's
  // puzzle" ambiguous.
  let path = setup("update-duplicate")
  let assert Ok(first) =
    store.insert_puzzle(path, "A", "2026-10-25", dots, fixture)
  let assert Ok(second) =
    store.insert_puzzle(path, "B", "2026-10-26", dots, fixture)

  should.equal(
    Error(DuplicateShowDate("2026-10-25")),
    store.update_puzzle(
      path,
      second.id,
      store.PuzzleUpdate(
        name: option.None,
        show_date: option.Some("2026-10-25"),
        dots_json: option.None,
        fixture_json: option.None,
      ),
    ),
  )
  // ...and the first puzzle still owns the date.
  should.equal(Ok(option.Some(first)), store.puzzle_by_id(path, first.id))
}

pub fn update_refuses_an_invalid_show_date_test() {
  let #(path, puzzle) = with_puzzle("update-invalid-date", day)
  should.equal(
    Error(InvalidShowDate("2026-02-30")),
    store.update_puzzle(
      path,
      puzzle.id,
      store.PuzzleUpdate(
        name: option.None,
        show_date: option.Some("2026-02-30"),
        dots_json: option.None,
        fixture_json: option.None,
      ),
    ),
  )
}

pub fn update_of_an_unknown_id_is_refused_test() {
  let #(path, puzzle) = with_puzzle("update-unknown", day)
  should.equal(
    Error(UnknownPuzzleId(puzzle.id + 100)),
    store.update_puzzle(
      path,
      puzzle.id + 100,
      store.PuzzleUpdate(
        name: option.Some("Nope"),
        show_date: option.None,
        dots_json: option.None,
        fixture_json: option.None,
      ),
    ),
  )
}

pub fn delete_removes_the_puzzle_but_keeps_telemetry_test() {
  // No FK, by design: the attempts table outlives the puzzle it describes
  // (store header). Deleting is not a cascade.
  let #(path, puzzle) = with_puzzle("delete", day)
  let assert Ok(Nil) = store.attempt_record_solve(path, uuid_a, day, "[]")

  should.equal(Ok(True), store.delete_puzzle(path, puzzle.id))
  should.equal(Ok(option.None), store.puzzle_by_id(path, puzzle.id))
  should.equal(Ok(0), store.count_puzzles(path))
  // The telemetry row is still there, under its original puzzle_id.
  should.equal(Ok(#(1, 1)), store.stats(path, puzzle.id))
}

pub fn delete_of_an_unknown_id_says_so_test() {
  let path = setup("delete-absent")
  should.equal(Ok(False), store.delete_puzzle(path, 42))
}

pub fn move_counts_are_sorted_and_include_abandons_test() {
  // The median is computed in Gleam from this raw list (SQLite has no median):
  // every attempt counts, and an abandon brings its own move_count.
  let #(path, puzzle) = with_puzzle("move-counts", day)
  let assert Ok(Nil) =
    store.attempt_record_solve(path, uuid_a, day, three_moves())
  let assert Ok(Nil) = store.attempt_record_abandon(path, uuid_b, day, 2)
  let assert Ok(Nil) =
    store.attempt_record_solve(
      path,
      "3f2504e0-4f89-41d3-9a0c-0305e82c3302",
      day,
      one_move(),
    )

  should.equal(Ok([1, 2, 3]), store.move_counts(path, puzzle.id))
}

pub fn move_counts_of_a_single_attempt_test() {
  let #(path, puzzle) = with_puzzle("move-counts-single", day)
  let assert Ok(Nil) = store.attempt_record_abandon(path, uuid_a, day, 7)
  should.equal(Ok([7]), store.move_counts(path, puzzle.id))
}

pub fn move_counts_of_no_attempts_is_empty_test() {
  let #(path, puzzle) = with_puzzle("move-counts-empty", day)
  should.equal(Ok([]), store.move_counts(path, puzzle.id))
  should.equal(Ok([]), store.move_counts(path, puzzle.id + 100))
}

fn one_move() -> String {
  "[{\"slot\":0,\"dir\":1}]"
}

fn three_moves() -> String {
  "[{\"slot\":0,\"dir\":1},{\"slot\":2,\"dir\":-1},{\"slot\":1,\"dir\":1}]"
}
