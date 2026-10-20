//// Worst-case timing for the live pipeline at locked scale.
//// Run: gleam run -m fourier_sketch/bench --target javascript

import complex
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import terms

@external(javascript, "../fourier_sketch_ffi.mjs", "now_ms")
fn now_ms() -> Float

const dots_count = 60

const samples = 512

pub fn main() -> Nil {
  let dots = wobbly_blob(dots_count)
  let _ = timed(dots)
  // warm-up
  let durations = repeat_time(dots, 7, [])
  let avg =
    list.fold(durations, 0.0, fn(a, d) { a +. d })
    /. int.to_float(list.length(durations))
  let fastest =
    list.fold(durations, 9.9e9, fn(a, d) {
      case d <. a {
        True -> d
        False -> a
      }
    })
  io.println(
    "pipeline: "
    <> int.to_string(dots_count)
    <> " dots -> "
    <> int.to_string(samples)
    <> " samples -> full DFT + sort",
  )
  io.println(
    "7 runs: avg "
    <> float.to_string(avg)
    <> " ms | min "
    <> float.to_string(fastest)
    <> " ms (budget: 8 ms/frame)",
  )
  let all_terms = terms.compute(dots, samples, 100_000)
  io.println("terms produced: " <> int.to_string(list.length(all_terms)))
}

fn repeat_time(
  dots: List(#(Float, Float)),
  n: Int,
  acc: List(Float),
) -> List(Float) {
  case n <= 0 {
    True -> acc
    False -> {
      let d = timed(dots)
      repeat_time(dots, n - 1, [d, ..acc])
    }
  }
}

fn timed(dots: List(#(Float, Float))) -> Float {
  let t0 = now_ms()
  let _ = terms.compute(dots, samples, 100_000)
  now_ms() -. t0
}

/// A demanding hand-drawn-ish blob: 60 vertices, wobbly radius, uneven spacing.
fn wobbly_blob(n: Int) -> List(#(Float, Float)) {
  let two_pi = 6.283_185_307_179_586
  list.repeat(Nil, n)
  |> list.index_map(fn(_, i) {
    let t = two_pi *. { int.to_float(i) /. int.to_float(n) }
    let sin3 = complex.exp_i({ 3.0 *. t }).im
    let cos7 = complex.exp_i({ 7.0 *. t }).re
    let r = { 35.0 +. { 10.0 *. sin3 } } +. { 5.0 *. cos7 }
    let c = complex.polar(r, t)
    #({ 50.0 +. c.re }, { 50.0 +. c.im })
  })
}
