//// Float-closeness assertion with useful diagnostics.
//// (gleeunit 1.11 dropped `should.be_close`; the sketch's approx module is
//// the sibling convention. An `assert` failure prints the values in scope.)

import gleam/float
import gleam/int
import toy_admin/env

pub fn be_close(actual: Float, expected: Float, tolerance: Float) -> Nil {
  let diff = float.absolute_value({ actual -. expected })
  assert diff <=. tolerance
  Nil
}

// ---------- test infrastructure ----------

@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

@external(erlang, "file", "delete")
fn delete_file(path: String) -> Result(Nil, Nil)

/// A FRESH SQLite file path for one test.
///
/// `build/` is gleam's own scratch directory (gitignored) and the tests run
/// from the project root, so nothing is cleaned up afterwards; a stray database
/// there is invisible to git.
///
/// `unique_integer/0` is unique for the lifetime of the node, so two tests in
/// one run never collide. It is NOT unique across runs (it restarts from the
/// same base), and `build/` survives between runs — so the file is deleted
/// first, making every call mean "a database that does not exist yet".
pub fn temp_db_path(label: String) -> String {
  let path =
    "build/test-db-"
    <> label
    <> "-"
    <> int.to_string(int.absolute_value(unique_integer()))
    <> ".sqlite3"
  let _ = delete_file(path)
  path
}

/// Set a process environment variable, exactly as the container's entrypoint
/// does (compose passes them). Used by the route tests to point `DB_PATH` at a
/// scratch database. Goes through `toy_admin/env` because `os:putenv` wants
/// charlists and a Gleam String is a binary.
pub fn set_env(key: String, value: String) -> Nil {
  env.set(key, value)
}
