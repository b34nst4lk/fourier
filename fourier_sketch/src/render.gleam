//// Bridge between the Lustre model and the panel-2 canvas RAF loop (FFI).
////
//// Pure pieces (top-N target slicing, slider clamping) are unit-tested; the
//// drawing itself lives in JS and is covered by the manual smoke checklist.
//// The FFI animation loop owns its own clock — Gleam pushes state on every
//// sync-worthy model change, the loop pulls per frame.

import gleam/dynamic/decode
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

/// Speed slider bounds, as percents of the animation's max speed
/// (SPEED in the FFI): 100% = the designed pace, 25% = slowest.
pub const min_speed_percent = 25

pub const max_speed_percent = 100

/// Clamp the speed slider into [min_speed_percent, max_speed_percent].
pub fn clamp_speed(n: Int) -> Int {
  int.max(min_speed_percent, int.min(max_speed_percent, n))
}

/// The FFI advances the pen by dt * SPEED * speed_factor each drawn frame —
/// the frame rate is untouched, only the distance moved per frame is.
pub fn speed_factor(percent: Int) -> Float {
  int.to_float(percent) /. 100.0
}

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
  speed_factor: Float,
) -> Nil {
  boot(canvas_id)
  ffi_sync(targets, show_final, playing, highlight_k, speed_factor)
}

@external(javascript, "./fourier_sketch_ffi.mjs", "canvas_sync")
fn ffi_sync(
  targets: List(#(Int, Float, Float)),
  show_final: Bool,
  playing: Bool,
  highlight_k: Int,
  speed_factor: Float,
) -> Nil

/// The share link: the app's URL plus the versioned sketch query.
@external(javascript, "./fourier_sketch_ffi.mjs", "share_url")
pub fn share_url(query: String) -> String

/// The boot-time share query, or the empty string.
@external(javascript, "./fourier_sketch_ffi.mjs", "read_shared_query")
pub fn read_shared_query() -> String

/// Consume (strip) the share query after a successful boot load.
@external(javascript, "./fourier_sketch_ffi.mjs", "consume_shared_query")
pub fn consume_shared_query() -> Nil

/// Best-effort clipboard copy; on_done reports success.
@external(javascript, "./fourier_sketch_ffi.mjs", "clipboard_copy")
pub fn copy_text(text: String, on_done: fn(Bool) -> a) -> a

/// Read an input element's current string value.
@external(javascript, "./fourier_sketch_ffi.mjs", "event_text")
pub fn event_text(event: decode.Dynamic, otherwise: String) -> String

/// Offer a CSV file for download (browser-native blob anchor).
@external(javascript, "./fourier_sketch_ffi.mjs", "download_csv")
pub fn download_csv(name: String, csv: String) -> Nil
