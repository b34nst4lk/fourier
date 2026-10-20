//// Bridge between the Lustre model and the panel-2 canvas RAF loop (FFI).
////
//// Pure pieces (top-N target slicing, slider clamping) are unit-tested; the
//// drawing itself lives in JS and is covered by the manual smoke checklist.
//// The FFI animation loop owns its own clock — Gleam pushes state on every
//// sync-worthy model change, the loop pulls per frame.

import gleam/int
import gleam/list
import terms.{type Term}

/// Document id of the panel-2 canvas element (view + FFI must agree).
pub const canvas_id = "fourier-canvas"

/// The circles slider bounds (decision #12).
const min_circles = 4

const max_circles = 256

/// Slice the amplitude-sorted terms to the top `count` and flatten to plain
/// tuples for the FFI: each becomes a [k, radius, phase] JS array.
pub fn build_targets(
  all: List(Term),
  count: Int,
) -> List(#(Int, Float, Float)) {
  all
  |> list.take(count)
  |> list.map(fn(t) { #(t.k, t.radius, t.phase) })
}

/// Sentinel for the FFI's highlight slot when no term is selected.
/// k values are bounded by ±N/2 ≤ 256, so this value is unambiguous.
pub const no_highlight = 999_999

/// Clamp the circles slider into [min_circles, max_circles].
pub fn clamp_circles(n: Int) -> Int {
  int.max(min_circles, int.min(max_circles, n))
}

@external(javascript, "./fourier_sketch_ffi.mjs", "canvas_boot")
fn boot(id: String) -> Nil

/// Push current render state to the FFI animation loop. Cheap — floats only.
pub fn sync(
  targets: List(#(Int, Float, Float)),
  show_final: Bool,
  playing: Bool,
  highlight_k: Int,
) -> Nil {
  boot(canvas_id)
  ffi_sync(targets, show_final, playing, highlight_k)
}

@external(javascript, "./fourier_sketch_ffi.mjs", "canvas_sync")
fn ffi_sync(
  targets: List(#(Int, Float, Float)),
  show_final: Bool,
  playing: Bool,
  highlight_k: Int,
) -> Nil

/// Offer a CSV file for download (browser-native blob anchor).
@external(javascript, "./fourier_sketch_ffi.mjs", "download_csv")
pub fn download_csv(name: String, csv: String) -> Nil
