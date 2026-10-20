//// Versioned autosave persistence for the sketch.
////
//// Schema v1: {"v":1,"dots":[[x,y],...]}. The schema version lives inside
//// the payload so a corrupt/old blob fails decode() cleanly and the app
//// falls back to an empty sketch (presets remain one click away).
////
//// encode/decode are pure and unit-tested on Node; the storage FFI calls
//// are thin translators covered by the manual smoke checklist (Node test
//// runs have no localStorage).

import gleam/dynamic/decode
import gleam/json
import sketch.{type Dot}

const schema_version = 1

const storage_key = "fourier_sketch"

pub fn encode(dots: List(Dot)) -> String {
  json.object([
    #("v", json.int(schema_version)),
    #("dots", json.array(dots, fn(d) { json.array([d.0, d.1], json.float) })),
  ])
  |> json.to_string
}

pub fn decode(input: String) -> Result(List(Dot), Nil) {
  case json.parse(input, stored_decoder()) {
    Ok(dots) -> Ok(dots)
    Error(_) -> Error(Nil)
  }
}

fn stored_decoder() -> decode.Decoder(List(Dot)) {
  use version <- decode.field("v", decode.int)
  use dots <- decode.field("dots", decode.list(dot_decoder()))
  case version == schema_version {
    True -> decode.success(dots)
    False -> decode.failure([], "unsupported schema version")
  }
}

fn dot_decoder() -> decode.Decoder(Dot) {
  decode.list(decode.float)
  |> decode.then(fn(pair) {
    case pair {
      [x, y] -> decode.success(#(x, y))
      _ -> decode.failure(#(0.0, 0.0), "a dot is a [x, y] pair")
    }
  })
}

@external(javascript, "./fourier_sketch_ffi.mjs", "store_get")
fn ffi_get(key: String, otherwise: String) -> String

@external(javascript, "./fourier_sketch_ffi.mjs", "store_set")
fn ffi_set(key: String, value: String) -> Nil

/// Load the saved dot list, if any. A missing or corrupt store decodes to
/// Error(Nil) — callers fall back to sketch.start([]).
pub fn store_load() -> Result(List(Dot), Nil) {
  decode(ffi_get(storage_key, ""))
}

/// Persist the dot list. Best-effort: storage failures are swallowed.
pub fn store_save(dots: List(Dot)) -> Nil {
  ffi_set(storage_key, encode(dots))
}
