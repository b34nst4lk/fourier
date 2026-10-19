//// Row sparklines + number formatting for the term table.
////
//// Each term's sparkline draws its x-axis projection x(u) = radius *
//// cos(2 pi k u + phase) as an integer-coordinate path in a 36x16 viewBox:
//// peak = the term's radius scaled into the box (per-row normalisation —
//// absolute amplitudes span two orders of magnitude and would flatten low
//// rows), cycles visible = |k|, horizontal shift = phase. The row's signed k
//// is used directly, so negative-k rows draw their time-mirrored wave; sign
//// stays legible in the k column. Rows are dimmed below the slider cut in
//// the table itself (see app view).
////
//// Note (correcting an earlier claim): x-projections of (k, r, phi) and
//// (-k, r, phi) are identical only when phi is 0 — otherwise one is the
//// time-mirror of the other. That nuance is why sparklines read exact.

import gleam/float
import gleam/int
import gleam/list
import gleam/string
import terms.{type Term}

@external(erlang, "math", "cos")
@external(javascript, "./fourier_sketch_ffi.mjs", "cos")
fn cos(x: Float) -> Float

pub const columns = 36

pub const box_height = 16

pub const amplitude = 6

pub const mid = 8

const two_pi = 6.283_185_307_179_586

/// Whole-path sparkline for one term: "M0,y L1,y ... L35,y".
pub fn path(term: Term) -> String {
  let cols = int.to_float(columns)
  indices(columns)
  |> list.map(fn(i) {
    let u = int.to_float(i) /. cols
    let y =
      { int.to_float(mid) }
      -. { int.to_float(amplitude) *. cos({ two_pi *. int.to_float(term.k) *. u } +. term.phase) }
    let yi = float.round(y)
    point(i, yi, i == 0)
  })
  |> string.join("")
}

fn point(x: Int, y: Int, first: Bool) -> String {
  let prefix = case first {
    True -> "M"
    False -> "L"
  }
  prefix <> int.to_string(x) <> "," <> int.to_string(y)
}

/// Fixed-two-decimal table formatting ("12.34", "-1.24", "2.00").
pub fn format_float2(x: Float) -> String {
  let v = float.round({ x *. 100.0 })
  let sign = case v < 0 {
    True -> "-"
    False -> ""
  }
  let v = int.absolute_value(v)
  sign
  <> int.to_string({ v / 100 })
  <> "."
  <> string.pad_start(int.to_string({ v % 100 }), 2, "0")
}

fn indices(n: Int) -> List(Int) {
  list.repeat(Nil, n)
  |> list.index_map(fn(_, i) { i })
}