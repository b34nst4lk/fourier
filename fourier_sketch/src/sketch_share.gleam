//// Sharable sketch encoding: URL query-parameter style.
////
//// The share link carries the drawing as `?v=1&sk=…`, where `sk` holds
//// semicolon-separated xy pairs, comma-separated, as INTEGERS scaled to
//// hundredths of the 0..100 sketch grid (0..10000). URL-legal characters
//// only: digits, comma, semicolon, dot in the host — nothing escapes.
//// `v=1` keeps the format versioned: unknown versions refuse to load.
////
//// This is the wire form; the localStorage autosave is the same drawing
//// in JSON. The sibling toy (phase 2) will import these sketches as
//// puzzle targets — the round trips are the contract below.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import sketch.{type Dot}

const version = "1"

const grid_max = 10_000

/// The query string (`v=1&sk=…`) for a drawing. Coordinates snap to the
/// 0.01 grid and clamp into the 0..100 box.
pub fn to_query(dots: List(Dot)) -> String {
  "v=1&sk=" <> string.join(list.map(dots, dot_out), ";")
}

pub fn from_query(text: String) -> Result(List(Dot), Nil) {
  let params = string.split(extract_query(text), "&")
  case find_param(params, "v") {
    Some(v) if v == version ->
      case find_param(params, "sk") {
        Some(sk_value) -> decode_sk(sk_value)
        None -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

/// Accepts a full URL or the bare query string; a fragment is ignored.
fn extract_query(text: String) -> String {
  let q = case string.split_once(text, "?") {
    Ok(#(_, rest)) -> rest
    Error(Nil) -> text
  }
  case string.split_once(q, "#") {
    Ok(#(before, _)) -> before
    Error(Nil) -> q
  }
}

fn decode_sk(sk_value: String) -> Result(List(Dot), Nil) {
  case sk_value {
    "" -> Ok([])
    _ ->
      sk_value
      |> string.split(";")
      |> list.try_map(pair_in)
  }
}

fn pair_in(pair: String) -> Result(Dot, Nil) {
  case string.split(pair, ",") {
    [x, y] -> {
      case int.parse(x), int.parse(y) {
        Ok(xi), Ok(yi) ->
          Ok(#(
            int.to_float(clamp_grid(xi)) /. 100.0,
            int.to_float(clamp_grid(yi)) /. 100.0,
          ))
        _, _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

fn dot_out(dot: Dot) -> String {
  let #(x, y) = dot
  int.to_string(clamp_grid({ x *. 100.0 } |> f_round))
  <> ","
  <> int.to_string(clamp_grid({ y *. 100.0 } |> f_round))
}

fn f_round(f: Float) -> Int {
  float_round(f)
}

@external(erlang, "erlang", "round")
@external(javascript, "./fourier_sketch_ffi.mjs", "round_int")
fn float_round(f: Float) -> Int

fn clamp_grid(n: Int) -> Int {
  int.max(0, int.min(grid_max, n))
}

fn find_param(params: List(String), key: String) -> Option(String) {
  case params {
    [] -> None
    [p, ..rest] ->
      case string.split_once(p, "=") {
        Ok(#(k, v)) if k == key -> Some(v)
        _ -> find_param(rest, key)
      }
  }
}
