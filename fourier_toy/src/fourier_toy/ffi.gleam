//// External bindings: the canvas animation shell, the page theme, the
//// hold-to-repeat input driver, and the daily puzzle's network/storage/
//// telemetry.

import fourier_toy/puzzle
import fourier_toy/shapes.{type TermState}
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/result

/// Push a shape's static data to the canvas: centroid, target trace, extras,
/// and `dial_max_r`. Runs once per puzzle switch (cache-deduped on the JS
/// side).
///
/// `dial_max_r` is the radius dial's STATIC unit — the biggest dialable radius.
/// The radius column scales its ring by `r / (2 · dial_max_r)` of its space,
/// and recomputing that unit from the live dial rows on the JS side would move
/// the ceiling with the dial.
pub fn canvas_shape(shape: shapes.Shape) -> Nil {
  let extras = list.map(shape.extras, row)
  let target = shape.target
  // the centroid crosses as a tuple (JS array); the lists normalize inside
  js_canvas_shape(shape.centroid, target, extras, shape.dial_max_r)
}

@external(javascript, "../fourier_toy_ffi.mjs", "canvas_shape")
fn js_canvas_shape(
  centroid: #(Float, Float),
  target: List(#(Float, Float)),
  extras: List(#(Int, Float, Float)),
  dial_max_r: Float,
) -> Nil

/// Push the current three dial terms and their KINDS. The canvas reads the
/// kinds for BEHAVIOR (which symbology a column draws: start marker / ring
/// size / arm speed) and the slot ORDINAL (the array index) for COLOUR — colour
/// answers "which wheel in the chain", never "what does it do". The kind codes
/// are a local wire detail of this module, not part of the core vocabulary.
/// Cache-deduped on the JS side, terms and kinds alike.
pub fn canvas_terms(
  dial: List(TermState),
  kinds: List(puzzle.DialKind),
) -> Nil {
  js_canvas_terms(list.map(dial, row), list.map(kinds, kind_code))
}

/// The behavior code the canvas dispatches on — not an ink lookup. The numbers
/// are private to this boundary (behaviour on the JS side reads them), so a
/// future kind can be added without touching the palette.
fn kind_code(kind: puzzle.DialKind) -> Int {
  case kind {
    puzzle.DialP -> 0
    puzzle.DialR -> 1
    puzzle.DialK -> 2
  }
}

@external(javascript, "../fourier_toy_ffi.mjs", "canvas_terms")
fn js_canvas_terms(rows: List(#(Int, Float, Float)), kinds: List(Int)) -> Nil

pub fn canvas_theme(dark: Bool) -> Nil {
  js_canvas_theme(dark)
}

@external(javascript, "../fourier_toy_ffi.mjs", "canvas_theme")
fn js_canvas_theme(dark: Bool) -> Nil

/// Press-highlight: pulse the slot that just stepped
/// — its term circle and its column ring emphasis for ~600ms, then fade back.
/// Draw-state only: the payload, the score and the wire are untouched, and a
/// repeat that re-pushes the same slot simply re-arms the window.
pub fn canvas_pulse(slot: Int) -> Nil {
  js_canvas_pulse(slot)
}

@external(javascript, "../fourier_toy_ffi.mjs", "canvas_pulse")
fn js_canvas_pulse(slot: Int) -> Nil

/// Solve reveal: the comet goes solid over the
/// dashed target for ~2s at the solve crossing. Fired BESIDE the solve POST in
/// the same effect list — it never gates, delays or retries it.
pub fn canvas_reveal() -> Nil {
  js_canvas_reveal()
}

@external(javascript, "../fourier_toy_ffi.mjs", "canvas_reveal")
fn js_canvas_reveal() -> Nil

fn row(t: TermState) -> #(Int, Float, Float) {
  #(t.k, t.r, t.phase_deg)
}

/// Mirror the toggle onto the body's data-theme so the page CSS follows.
pub fn set_dark(dark: Bool) -> Nil {
  js_set_dark(dark)
}

@external(javascript, "../fourier_toy_ffi.mjs", "set_dark")
fn js_set_dark(dark: Bool) -> Nil

/// The boot-time theme: the stored choice ("dark"/"light"), falling back to
/// the system preference; "light" when neither is available.
pub fn theme_load() -> String {
  js_theme_load()
}

@external(javascript, "../fourier_toy_ffi.mjs", "theme_load")
fn js_theme_load() -> String

/// Persist the theme choice (best-effort — storage may be unavailable).
pub fn theme_save(dark: Bool) -> Nil {
  js_theme_save(dark)
}

@external(javascript, "../fourier_toy_ffi.mjs", "theme_save")
fn js_theme_save(dark: Bool) -> Nil

/// Bind the hold-to-repeat input driver for the stepper buttons. Call once
/// at app start; delegates via document listeners, so rows re-rendered by
/// any later change are covered without re-binding.
pub fn hold_init() -> Nil {
  js_hold_init()
}

@external(javascript, "../fourier_toy_ffi.mjs", "hold_init")
fn js_hold_init() -> Nil

// ---------- the daily puzzle ----------
// Four concerns the pure core cannot own: reaching the API, the anonymous
// identity, the stored attempt, and the two fire-and-forget POSTs. Each is a
// thin binding over a guarded JS function — a toy with no storage, no fetch and
// no network still boots into the quaver.

/// The API's `tz` parameter: minutes to ADD to the visitor's UTC offset
/// (UTC+2 ⇒ 120). The backend resolves the visitor's local date from it.
pub fn tz_offset_minutes() -> Int {
  js_tz_offset_minutes()
}

@external(javascript, "../fourier_toy_ffi.mjs", "tz_offset_minutes")
fn js_tz_offset_minutes() -> Int

/// Reading storage: `Error(Nil)` when the key is absent or storage is
/// unavailable (private mode) — the caller treats both as "nothing stored".
pub fn ls_get(key: String) -> Result(String, Nil) {
  decode.run(js_ls_get(key), decode.string)
  |> result.map_error(fn(_not_a_string) { Nil })
}

@external(javascript, "../fourier_toy_ffi.mjs", "ls_get")
fn js_ls_get(key: String) -> dynamic.Dynamic

/// Writing storage: False means it did not stick (private mode, quota). Every
/// caller is best-effort, so nothing depends on the answer — but the smoke
/// pins that the attempt is written at all.
pub fn ls_set(key: String, value: String) -> Bool {
  js_ls_set(key, value)
}

@external(javascript, "../fourier_toy_ffi.mjs", "ls_set")
fn js_ls_set(key: String, value: String) -> Bool

pub fn ls_del(key: String) -> Nil {
  js_ls_del(key)
}

@external(javascript, "../fourier_toy_ffi.mjs", "ls_del")
fn js_ls_del(key: String) -> Nil

/// The site-wide anonymous identity (`j-uid`): the stored v4 uuid, or
/// a fresh one that is stored for next time. Always v4-shaped — the backend
/// validates it, and a rejected identity would silently lose every solve.
pub fn uuid_ensure() -> String {
  js_uuid_ensure()
}

@external(javascript, "../fourier_toy_ffi.mjs", "uuid_ensure")
fn js_uuid_ensure() -> String

/// `GET /api/puzzle/today?tz=…`, resolved as a message rather than returned:
/// the answer has to travel through `update`. `on_error` fires on any failure
/// (no fetch, network, non-2xx, unreadable body) and the toy falls back to the
/// built-in quaver.
pub fn fetch_puzzle(
  tz_offset_min: Int,
  on_ok: fn(String) -> Nil,
  on_error: fn() -> Nil,
) -> Nil {
  js_fetch_puzzle(tz_offset_min, on_ok, on_error)
}

@external(javascript, "../fourier_toy_ffi.mjs", "fetch_puzzle")
fn js_fetch_puzzle(
  tz_offset_min: Int,
  on_ok: fn(String) -> Nil,
  on_error: fn() -> Nil,
) -> Nil

/// POST a telemetry body to `path`, calling `on_sent` only on a 2xx. Nothing
/// retries here: an unsent solve is re-sent by the next boot from the stored
/// attempt (`reported: false`), and an abandoned attempt is simply gone.
pub fn post_telemetry(path: String, body: String, on_sent: fn() -> Nil) -> Nil {
  js_post_telemetry(path, body, on_sent)
}

@external(javascript, "../fourier_toy_ffi.mjs", "post_telemetry")
fn js_post_telemetry(path: String, body: String, on_sent: fn() -> Nil) -> Nil
