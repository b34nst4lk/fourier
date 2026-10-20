//// The Lustre app: 2x2 grid — sketch (top-left), output (top-right), the
//// term table (bottom row, full width). Dark-only.
////
//// Per the TDD policy the views are thin translators: all decisions live in
//// sketch (state), store (persistence), and later dft/terms. The pointer
//// decoders are the one place that bridges events to pure messages.

import gleam/bool
import gleam/dynamic/decode
import gleam/float
import gleam/int

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
import lustre/event
import render
import sketch.{type Dot, type Sketch}
import spark
import store
import terms

// -- model -------------------------------------------------------------------

pub type Msg {
  SketchDown(button: Int, x: Float, y: Float)
  SketchMove(x: Float, y: Float)
  SketchUp
  ClearAll
  UndoMsg
  RedoMsg
  LoadStar
  LoadHeart
  LoadWobble
  SetCircles(Int)
  ToggleAnimate
  SelectTerm(Int)
  ExportCsv
  Ignored
}

pub type Model {
  Model(
    sketch: Sketch,
    drag: Option(Int),
    terms: List(terms.Term),
    circles: Int,
    animate: Bool,
    selected: Option(Int),
  )
}

/// The SVG element's document id; the FFI looks it up for coordinate
/// conversion. Shared by the view and the pointer decoder.
const svg_id = "sketch-svg"

/// Grab radius in sketch units.
const hit_radius = 3.0

/// Arc-length resample resolution for the live pipeline.
const sample_count = 512

/// Keep every signed term the DFT produces (truncation happens at render
/// time once the circles slider exists in phase 5).
const max_terms = 1024

// -- lifecycle ---------------------------------------------------------------

pub fn init(_: Nil) -> #(Model, Effect(Msg)) {
  let dots = case store.store_load() {
    Ok(dots) -> dots
    Error(_) -> []
  }
  let sk = sketch.start(dots)
  let model =
    Model(
      sketch: sk,
      drag: None,
      terms: pipeline(sk),
      circles: 64,
      animate: True,
      selected: None,
    )
  #(model, effect.batch([canvas_sync(model), keys_effect()]))
}

/// Global Ctrl/Cmd+Z undo, Ctrl+Shift+Z / Ctrl+Y redo — once, at boot, via a
/// Gleam closure so the FFI never touches message records.
fn keys_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let send = fn(is_redo: Bool) {
      dispatch(case is_redo {
        True -> RedoMsg
        False -> UndoMsg
      })
    }
    wire_keys(send)
  })
}

@external(javascript, "./fourier_sketch_ffi.mjs", "wire_keys")
fn wire_keys(send: fn(Bool) -> Nil) -> Nil

/// The live pipeline: dots -> resample -> DFT -> sorted (k, radius, phase).
/// Runs on every sketch change, exactly as decision #8 demands.
fn pipeline(sk: Sketch) -> List(terms.Term) {
  terms.compute(sketch.dots(sk), sample_count, max_terms)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SketchDown(button, x, y) ->
      case button {
        2 ->
          // right-click: delete the nearest dot within reach
          case
            sketch.nearest_dot(sketch.dots(model.sketch), #(x, y), hit_radius)
          {
            Ok(index) -> commit(model, fn(s) { sketch.remove_dot(s, index) })
            Error(_) -> #(model, effect.none())
          }
        0 ->
          case
            sketch.nearest_dot(sketch.dots(model.sketch), #(x, y), hit_radius)
          {
            Ok(index) ->
              drag_commit(
                model,
                fn(s) { sketch.grab_dot(s, index) },
                Some(index),
              )
            Error(_) ->
              drag_commit(model, fn(s) { sketch.add_dot(s, #(x, y)) }, None)
          }
        _ -> #(model, effect.none())
      }
    SketchMove(x, y) ->
      case model.drag {
        Some(index) ->
          drag_commit(
            model,
            fn(s) { sketch.set_dot(s, index, #(x, y)) },
            Some(index),
          )
        None -> #(model, effect.none())
      }
    SketchUp ->
      case model.drag {
        // mouseup (and mouseleave) close the drag; a click-without-drag gets
        // its grab cancelled, a real move keeps its single undo step
        Some(_) -> drag_commit(model, sketch.cancel_grab, None)
        None -> #(model, effect.none())
      }
    ClearAll -> commit(model, sketch.clear)
    UndoMsg -> commit(model, sketch.undo)
    RedoMsg -> commit(model, sketch.redo)
    LoadStar -> preset(model, sketch.star())
    LoadHeart -> preset(model, sketch.heart())
    LoadWobble -> preset(model, sketch.wobble())
    Ignored -> #(model, effect.none())
    SetCircles(n) -> {
      let n = render.clamp_circles(n)
      // the selection survives only while its term sits inside the cut
      let sel = case model.selected {
        Some(k) ->
          case terms.index_of_k(model.terms, k) {
            -1 -> None
            i ->
              case i < n {
                True -> model.selected
                False -> None
              }
          }
        None -> None
      }
      let m = Model(..model, circles: n, selected: sel)
      #(m, canvas_sync(m))
    }
    ToggleAnimate -> {
      let m = Model(..model, animate: !model.animate)
      #(m, canvas_sync(m))
    }
    SelectTerm(k) -> {
      // click the selected row again to clear it
      let sel = case model.selected {
        Some(k2) ->
          case k2 == k {
            True -> None
            False -> Some(k)
          }
        None -> Some(k)
      }
      let m = Model(..model, selected: sel)
      #(m, canvas_sync(m))
    }
    ExportCsv -> #(
      model,
      effect.from(fn(_dispatch) {
        render.download_csv("f-sketch-terms.csv", terms.to_csv(model.terms))
      }),
    )
  }
}

fn preset(model: Model, dots: List(Dot)) -> #(Model, Effect(Msg)) {
  commit(model, fn(s) { sketch.load_dots(s, dots) })
}

/// Apply a sketch change (drag state untouched) and autosave. Every
/// sketch-affecting message flows through here.
fn commit(model: Model, change: fn(Sketch) -> Sketch) -> #(Model, Effect(Msg)) {
  let sk = change(model.sketch)
  let m = Model(..model, sketch: sk, terms: pipeline(sk))
  #(m, effect.batch([autosave(sk), canvas_sync(m)]))
}

/// Apply a sketch change together with a new drag state, then autosave.
fn drag_commit(
  model: Model,
  change: fn(Sketch) -> Sketch,
  drag: Option(Int),
) -> #(Model, Effect(Msg)) {
  let sk = change(model.sketch)
  let m =
    Model(
      sketch: sk,
      drag: drag,
      terms: pipeline(sk),
      circles: model.circles,
      animate: model.animate,
      selected: model.selected,
    )
  #(m, effect.batch([autosave(sk), canvas_sync(m)]))
}

/// Push the current render state (top-N targets + mode flags) into the
/// FFI animation loop.
fn canvas_sync(model: Model) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    render.sync(
      render.build_targets(model.terms, model.circles),
      bool.negate(model.animate),
      model.animate,
      case model.selected {
        Some(k) -> k
        None -> render.no_highlight
      },
    )
  })
}

fn autosave(sk: Sketch) -> Effect(Msg) {
  effect.from(fn(_dispatch) { store.store_save(sketch.dots(sk)) })
}

// -- event decoding ----------------------------------------------------------
// The lustre v5 `event.on` handlers are decoders over the event object.
// Coordinates need the SVG element's bounding rect, so the raw event is
// passed through a primitive decoder into the FFI, which returns sketch-space
// coords (a sentinel value flags conversion failure, e.g. non-browsers).

fn down_decoder() -> decode.Decoder(Msg) {
  pointer_decoder(fn(button, x, y) { SketchDown(button, x, y) })
}

fn move_decoder() -> decode.Decoder(Msg) {
  pointer_decoder(fn(_button, x, y) { SketchMove(x, y) })
}

const point_sentinel_x = -999.0

fn pointer_decoder(build: fn(Int, Float, Float) -> Msg) -> decode.Decoder(Msg) {
  decode.new_primitive_decoder("pointer", fn(data) {
    let point = event_point(data, svg_id, #(point_sentinel_x, point_sentinel_x))
    case point.0 == point_sentinel_x {
      True -> Error(Ignored)
      False ->
        case
          decode.run(data, decode.field("button", decode.int, decode.success))
        {
          Ok(button) -> Ok(build(button, point.0, point.1))
          Error(_) -> Error(Ignored)
        }
    }
  })
}

fn up_decoder() -> decode.Decoder(Msg) {
  decode.new_primitive_decoder("up", fn(_) { Ok(SketchUp) })
}

fn ignored_decoder() -> decode.Decoder(Msg) {
  decode.new_primitive_decoder("ignored", fn(_) { Ok(Ignored) })
}

@external(javascript, "./fourier_sketch_ffi.mjs", "event_point")
fn event_point(event: decode.Dynamic, svg_id: String, otherwise: Dot) -> Dot

// -- view --------------------------------------------------------------------

pub fn view(model: Model) -> Element(Msg) {
  let sk = model.sketch
  let ready = sketch.gate_ready(sk)
  html.div([attr.class("app")], [
    sketch_panel(sk),
    case ready {
      True -> fourier_panel(model)
      False ->
        html.div([attr.class("panel")], [
          html.div([attr.class("panel-label")], [html.text("fourier")]),
          html.div([attr.class("placeholder")], [
            html.text("Add at least 3 dots to summon the Fourier view."),
          ]),
        ])
    },
    html.div([attr.class("panel"), attr.class("terms")], [
      html.div([attr.class("panel-label")], [html.text("terms")]),
      html.div([attr.class("toolbar")], [
        html.button(
          [
            attr.class("export-btn"),
            attr.disabled(bool.negate(ready)),
            event.on_click(ExportCsv),
          ],
          [html.text("export csv")],
        ),
      ]),
      case ready {
        True -> term_table(model)
        False ->
          html.div([attr.class("placeholder")], [
            html.text("No terms yet."),
          ])
      },
    ]),
  ])
}

/// Panel 3: every computed term, amplitude-descending, with its x-projection
/// sparkline. Rows below the circles-slider cut render dimmed.
fn term_table(model: Model) -> Element(Msg) {
  html.div([attr.class("terms-scroll")], [
    html.table([attr.class("term-table")], [
      html.thead([], [
        // Title row: lives INSIDE the table so it scrolls-sticks with the
        // column header beneath it — no overlay, by construction.
        html.tr([], [
          html.th([attr.attribute("colspan", "4")], [
            html.span([attr.class("terms-title")], [html.text("Terms")]),
            html.button([attr.class("export-btn"), event.on_click(ExportCsv)], [
              html.text("export csv"),
            ]),
          ]),
        ]),
        html.tr([], [
          html.th([], [html.text("k")]),
          html.th([], [html.text("radius")]),
          html.th([], [html.text("phase")]),
          html.th([], [html.text("wave")]),
        ]),
      ]),
      html.tbody([], term_rows(model)),
    ]),
  ])
}

/// Panel 2: live epicycle canvas + mode toggles + circles slider.
fn fourier_panel(model: Model) -> Element(Msg) {
  html.div([attr.class("panel")], [
    html.div([attr.class("panel-label")], [html.text("fourier")]),
    html.div([attr.class("fourier-body")], [
      fourier_toolbar(model),
      html.canvas([
        attr.attribute("id", render.canvas_id),
        attr.class("fourier-canvas"),
      ]),
    ]),
  ])
}

fn fourier_toolbar(model: Model) -> Element(Msg) {
  html.div([attr.class("toolbar")], [
    html.button(
      [
        event.on_click(ToggleAnimate),
        attr.classes([#("active", model.animate)]),
      ],
      [
        html.text(case model.animate {
          True -> "pause"
          False -> "play"
        }),
      ],
    ),
    html.span([attr.class("slider-label")], [html.text("circles")]),
    html.input([
      attr.type_("range"),
      attr.attribute("min", "4"),
      attr.attribute("max", "256"),
      attr.attribute("step", "1"),
      attr.attribute("value", int.to_string(model.circles)),
      attr.class("circles-slider"),
      event.on("input", circles_decoder()),
    ]),
    html.span([attr.class("count-label")], [
      html.text(int.to_string(model.circles)),
    ]),
  ])
}

/// One table row per computed term. The sparkline column holds a small SVG
/// with integer coordinates (see spark module for the normalisation story).
fn term_rows(model: Model) -> List(Element(Msg)) {
  model.terms
  |> list.index_map(fn(t, i) {
    html.tr(
      [
        attr.classes([
          #("cut", i >= model.circles),
          #("selected", case model.selected {
            Some(k) -> k == t.k
            None -> False
          }),
        ]),
        event.on_click(SelectTerm(t.k)),
      ],
      [
        html.td([], [html.text(int.to_string(t.k))]),
        html.td([], [html.text(spark.format_float2(t.radius))]),
        html.td([], [html.text(spark.format_float2(t.phase))]),
        html.td([], [
          svg.svg(
            [
              attr.class("spark"),
              attr.attribute(
                "viewBox",
                "0 0 "
                  <> int.to_string(spark.columns)
                  <> " "
                  <> int.to_string(spark.box_height),
              ),
            ],
            [svg.path([attr.attribute("d", spark.path(t))])],
          ),
        ]),
      ],
    )
  })
}

fn sketch_panel(sk: Sketch) -> Element(Msg) {
  html.div([attr.class("panel")], [
    html.div([attr.class("panel-label")], [html.text("sketch")]),
    toolbar(sk),
    svg.svg(
      [
        attr.attribute("id", svg_id),
        attr.attribute("viewBox", "0 0 100 100"),
        attr.class("sketch-svg"),
        event.on("mousedown", down_decoder()),
        event.on("mousemove", move_decoder()),
        event.on("mouseup", up_decoder()),
        event.on("mouseleave", up_decoder()),
        event.prevent_default(event.on("contextmenu", ignored_decoder())),
      ],
      list.flatten([
        [
          svg.rect([
            attr.class("sketch-bg"),
            attr.attribute("x", "0"),
            attr.attribute("y", "0"),
            attr.attribute("width", "100"),
            attr.attribute("height", "100"),
          ]),
          svg.path([
            attr.class("sketch-path"),
            attr.attribute("d", closed_path(sketch.dots(sk))),
          ]),
        ],
        dots_elems(sketch.dots(sk)),
      ]),
    ),
  ])
}

fn toolbar(sk: Sketch) -> Element(Msg) {
  html.div([attr.class("toolbar")], [
    html.button([event.on_click(UndoMsg), attr.disabled(!sketch.can_undo(sk))], [
      html.text("undo"),
    ]),
    html.button([event.on_click(RedoMsg), attr.disabled(!sketch.can_redo(sk))], [
      html.text("redo"),
    ]),
    html.button(
      [event.on_click(ClearAll), attr.disabled(sketch.dot_count(sk) == 0)],
      [html.text("clear")],
    ),
    html.button([event.on_click(LoadStar)], [html.text("\u{2605} star")]),
    html.button([event.on_click(LoadHeart)], [html.text("\u{2665} heart")]),
    html.button([event.on_click(LoadWobble)], [html.text("\u{25CB} wobble")]),
  ])
}

fn dots_elems(dots: List(Dot)) -> List(Element(Msg)) {
  dots
  |> list.index_map(fn(d, _i) {
    svg.circle([
      attr.class("dot"),
      attr.attribute("cx", float.to_string(d.0)),
      attr.attribute("cy", float.to_string(d.1)),
      attr.attribute("r", "1.4"),
    ])
  })
}

fn closed_path(dots: List(Dot)) -> String {
  case dots {
    [] -> ""
    [first, ..rest] -> {
      let rest_str =
        rest
        |> list.map(fn(p) { " L " <> point_str(p) })
        |> string.join("")
      "M " <> point_str(first) <> rest_str <> " Z"
    }
  }
}

fn point_str(p: Dot) -> String {
  float.to_string(p.0) <> " " <> float.to_string(p.1)
}

@external(javascript, "./fourier_sketch_ffi.mjs", "event_value")
fn event_value(event: decode.Dynamic, otherwise: Float) -> Float

fn circles_decoder() -> decode.Decoder(Msg) {
  decode.new_primitive_decoder("circles-slider", fn(data) {
    let v = event_value(data, -1.0)
    case v >=. 0.0 {
      True -> Ok(SetCircles(float.round(v)))
      False -> Error(Ignored)
    }
  })
}
