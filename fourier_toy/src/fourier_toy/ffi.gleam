//// External bindings for the canvas animation shell and page routing.

import fourier_toy/shapes.{type TermState}
import gleam/list

/// Push a shape's static data to the canvas: centroid, target trace, extras.
/// Runs once per puzzle switch (cache-deduped on the JS side).
pub fn canvas_shape(shape: shapes.Shape) -> Nil {
  let extras = list.map(shape.extras, row)
  let target = shape.target
  // the centroid crosses as a tuple (JS array); the lists normalize inside
  js_canvas_shape(shape.centroid, target, extras)
}

@external(javascript, "../fourier_toy_ffi.mjs", "canvas_shape")
fn js_canvas_shape(
  centroid: #(Float, Float),
  target: List(#(Float, Float)),
  extras: List(#(Int, Float, Float)),
) -> Nil

/// Push the current four dial terms (cache-deduped on the JS side).
pub fn canvas_terms(dial: List(TermState)) -> Nil {
  js_canvas_terms(list.map(dial, row))
}

@external(javascript, "../fourier_toy_ffi.mjs", "canvas_terms")
fn js_canvas_terms(rows: List(#(Int, Float, Float))) -> Nil

pub fn canvas_theme(dark: Bool) -> Nil {
  js_canvas_theme(dark)
}

@external(javascript, "../fourier_toy_ffi.mjs", "canvas_theme")
fn js_canvas_theme(dark: Bool) -> Nil

fn row(t: TermState) -> #(Int, Float, Float) {
  #(t.k, t.r, t.phase_deg)
}

/// Mirror the toggle onto the body's data-theme so the page CSS follows.
pub fn set_dark(dark: Bool) -> Nil {
  js_set_dark(dark)
}

@external(javascript, "../fourier_toy_ffi.mjs", "set_dark")
fn js_set_dark(dark: Bool) -> Nil

/// Bind the hold-to-repeat input driver for the stepper buttons. Call once
/// at app start; delegates via document listeners, so rows re-rendered by
/// any later change are covered without re-binding.
pub fn hold_init() -> Nil {
  js_hold_init()
}

@external(javascript, "../fourier_toy_ffi.mjs", "hold_init")
fn js_hold_init() -> Nil
