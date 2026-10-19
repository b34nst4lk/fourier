//// The Lustre app: 2x2 grid — sketch (top-left), output (top-right), the
//// term table (bottom row, full width). Dark-only.
////
//// Per the TDD policy the views are thin translators: all decisions live in
//// sketch (state), store (persistence), and later dft/terms. The pointer
//// decoders are the one place that bridges events to pure messages.

import gleam/dynamic/decode
import gleam/float

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
import lustre/event
import sketch.{type Dot, type Sketch}
import store

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
  Ignored
}

pub type Model {
  Model(sketch: Sketch, drag: Option(Int))
}

/// The SVG element's document id; the FFI looks it up for coordinate
/// conversion. Shared by the view and the pointer decoder.
const svg_id = "sketch-svg"

/// Grab radius in sketch units.
const hit_radius = 3.0

// -- lifecycle ---------------------------------------------------------------

pub fn init(_: Nil) -> #(Model, Effect(Msg)) {
  let dots = case store.store_load() {
    Ok(dots) -> dots
    Error(_) -> []
  }
  #(Model(sketch: sketch.start(dots), drag: None), effect.none())
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
  }
}

fn preset(model: Model, dots: List(Dot)) -> #(Model, Effect(Msg)) {
  commit(model, fn(s) { sketch.load_dots(s, dots) })
}

/// Apply a sketch change (drag state untouched) and autosave. Every
/// sketch-affecting message flows through here.
fn commit(model: Model, change: fn(Sketch) -> Sketch) -> #(Model, Effect(Msg)) {
  let sk = change(model.sketch)
  #(Model(..model, sketch: sk), autosave(sk))
}

/// Apply a sketch change together with a new drag state, then autosave.
fn drag_commit(
  model: Model,
  change: fn(Sketch) -> Sketch,
  drag: Option(Int),
) -> #(Model, Effect(Msg)) {
  let sk = change(model.sketch)
  #(Model(sketch: sk, drag: drag), autosave(sk))
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
    panel("fourier", case ready {
      True -> "Epicycles render here in the next build (phase 5)."
      False -> "Add at least 3 dots to summon the Fourier view."
    }),
    html.div([attr.class("panel"), attr.class("terms")], [
      html.div([attr.class("panel-label")], [html.text("terms")]),
      html.div([attr.class("placeholder")], [
        html.text(case ready {
          True -> "The term table lands in phase 6."
          False -> "No terms yet."
        }),
      ]),
    ]),
  ])
}

fn panel(label: String, note: String) -> Element(Msg) {
  html.div([attr.class("panel")], [
    html.div([attr.class("panel-label")], [html.text(label)]),
    html.div([attr.class("placeholder")], [html.text(note)]),
  ])
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
    html.button([event.on_click(LoadStar)], [html.text("â\u{2605} star")]),
    html.button([event.on_click(LoadHeart)], [html.text("â\u{2665} heart")]),
    html.button([event.on_click(LoadWobble)], [html.text("â\u{25CB} wobble")]),
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
