//// The Lustre app: 2x2 grid — sketch (top-left), output (top-right), the
//// term table (bottom row, full width). Parchment-cartography themes
//// (light + lamplit dark); the theme toggle lives in the static shell
//// (index.html owns body[data-theme] — see the FFI palette()).
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
import sketch_share

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
  SetCircles(Int)
  SetSpeed(Int)
  ToggleAnimate
  SelectTerm(Int)
  ExportCsv
  ShareOpen
  ShareClose
  CopyShare
  CopyDone(Bool)
  PasteSet(String)
  PasteLoad
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
    speed: Int,
    share_open: Bool,
    share_copied: Bool,
    paste: String,
    paste_bad: Bool,
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
const max_terms = 256

// -- lifecycle ---------------------------------------------------------------

pub fn init(_: Nil) -> #(Model, Effect(Msg)) {
  // an incoming share link beats the local autosave (replace + autosave —
  // low stakes by ruling); the shared query is consumed so refreshes serve
  // the recipient's own saved sketch afterwards
  let dots = case sketch_share.from_query(render.read_shared_query()) {
    Ok(shared) -> {
      render.consume_shared_query()
      shared
    }
    Error(_) ->
      case store.store_load() {
        Ok(dots) -> dots
        Error(_) -> []
      }
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
      speed: 100,
      share_open: False,
      share_copied: False,
      paste: "",
      paste_bad: False,
    )
  #(model, effect.batch([autosave(sk), canvas_sync(model), keys_effect()]))
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
    Ignored -> #(model, effect.none())
    SetSpeed(n) -> {
      let m = Model(..model, speed: render.clamp_speed(n))
      #(m, canvas_sync(m))
    }
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
    ShareOpen -> #(
      Model(..model, share_open: True, share_copied: False),
      effect.none(),
    )
    ShareClose -> #(
      Model(..model, share_open: False, paste: "", paste_bad: False),
      effect.none(),
    )
    CopyShare -> #(model, copy_share_effect(model))
    CopyDone(ok) -> #(Model(..model, share_copied: ok), effect.none())
    PasteSet(v) -> #(Model(..model, paste: v, paste_bad: False), effect.none())
    PasteLoad ->
      case sketch_share.from_query(model.paste) {
        Ok(dots) -> {
          let #(m, eff) = commit(model, fn(sk) { sketch.load_dots(sk, dots) })
          #(Model(..m, share_open: False, paste: "", paste_bad: False), eff)
        }
        Error(_) -> #(Model(..model, paste_bad: True), effect.none())
      }
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
  // record-update spread: adding a Model field can never break drags
  let m = Model(..model, sketch: sk, drag: drag, terms: pipeline(sk))
  #(m, effect.batch([autosave(sk), canvas_sync(m)]))
}

/// Push the current render state (top-N targets + mode flags) into the
/// FFI animation loop.
fn canvas_sync(model: Model) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    render.sync(
      render.build_targets(model.terms, model.circles),
      model.animate,
      model.selected,
      render.speed_factor(model.speed),
    )
  })
}

fn share_query(model: Model) -> String {
  sketch_share.to_query(sketch.dots(model.sketch))
}

fn copy_share_effect(model: Model) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    render.copy_text(render.share_url(share_query(model)), fn(ok) {
      dispatch(CopyDone(ok))
    })
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

fn touch_down_decoder() -> decode.Decoder(Msg) {
  touch_point_decoder(fn(x, y) { SketchDown(0, x, y) })
}

fn touch_move_decoder() -> decode.Decoder(Msg) {
  touch_point_decoder(fn(x, y) { SketchMove(x, y) })
}

fn touch_point_decoder(build: fn(Float, Float) -> Msg) -> decode.Decoder(Msg) {
  decode.new_primitive_decoder("touch", fn(data) {
    let point = event_point(data, svg_id, #(point_sentinel_x, point_sentinel_x))
    case point.0 == point_sentinel_x {
      True -> Error(Ignored)
      False -> Ok(build(point.0, point.1))
    }
  })
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
    sketch_panel(model),
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
      html.div([attr.class("toolbar terms-toolbar")], [
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
  html.div([attr.class("toolbar fourier-toolbar")], [
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
      attr.attribute("min", int.to_string(render.min_circles)),
      attr.attribute("max", int.to_string(render.max_circles)),
      attr.attribute("step", "1"),
      attr.attribute("value", int.to_string(model.circles)),
      attr.class("circles-slider"),
      event.on("input", circles_decoder()),
    ]),
    html.span([attr.class("count-label")], [
      html.text(int.to_string(model.circles)),
    ]),
    html.span([attr.class("slider-label")], [html.text("speed")]),
    html.input([
      attr.type_("range"),
      attr.attribute("min", int.to_string(render.min_speed_percent)),
      attr.attribute("max", int.to_string(render.max_speed_percent)),
      attr.attribute("value", int.to_string(model.speed)),
      attr.class("speed-slider"),
      event.on("input", speed_decoder()),
    ]),
    html.span([attr.class("count-label")], [
      html.text(int.to_string(model.speed) <> "%"),
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

fn sketch_panel(model: Model) -> Element(Msg) {
  let sk = model.sketch
  html.div([attr.class("panel")], [
    html.div([attr.class("panel-label")], [html.text("sketch")]),
    toolbar(sk),
    case model.share_open {
      True -> share_dialog(model)
      False -> html.div([], [])
    },
    svg.svg(
      [
        attr.attribute("id", svg_id),
        attr.attribute("viewBox", "0 0 100 100"),
        attr.class("sketch-svg"),
        event.on("mousedown", down_decoder()),
        event.on("mousemove", move_decoder()),
        event.on("mouseup", up_decoder()),
        event.on("mouseleave", up_decoder()),
        event.on("touchstart", touch_down_decoder()),
        event.prevent_default(event.on("touchmove", touch_move_decoder())),
        event.on("touchend", up_decoder()),
        event.on("touchcancel", up_decoder()),
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
    html.button([event.on_click(ShareOpen)], [html.text("share")]),
  ])
}

fn share_dialog(model: Model) -> Element(Msg) {
  let link = render.share_url(share_query(model))
  let code = share_query(model)
  html.div([attr.class("share-dialog")], [
    html.div([attr.class("share-sheet")], [
      html.div([attr.class("share-top")], [
        html.span([attr.class("about-heading")], [
          html.text("share / load a sketch"),
        ]),
        html.button([attr.class("corner-chip"), event.on_click(ShareClose)], [
          html.text("x"),
        ]),
      ]),
      html.div([attr.class("share-label")], [
        html.text("link — anyone opening it sees your drawing"),
      ]),
      html.div([attr.class("share-row")], [
        html.textarea([attr.readonly(True), attr.class("share-box")], link),
        html.button([attr.class("corner-chip"), event.on_click(CopyShare)], [
          html.text(case model.share_copied {
            True -> "copied"
            False -> "copy"
          }),
        ]),
      ]),
      html.div([attr.class("share-label")], [html.text("code")]),
      html.textarea([attr.readonly(True), attr.class("share-box")], code),
      html.div([attr.class("share-label")], [
        html.text("load from a link or code"),
      ]),
      html.div([attr.class("share-row")], [
        html.textarea(
          [
            attr.class("share-box"),
            attr.placeholder("paste a share link or the code here"),
            event.on("input", paste_decoder()),
          ],
          model.paste,
        ),
        html.button([attr.class("corner-chip"), event.on_click(PasteLoad)], [
          html.text("load"),
        ]),
      ]),
      case model.paste_bad {
        True ->
          html.div([attr.class("paste-note")], [
            html.text("couldn't read that — paste a share link or the code"),
          ])
        False -> html.div([], [])
      },
    ]),
  ])
}

fn paste_decoder() -> decode.Decoder(Msg) {
  decode.new_primitive_decoder("paste-box", fn(data) {
    Ok(PasteSet(render.event_text(data, "")))
  })
}

fn dots_elems(dots: List(Dot)) -> List(Element(Msg)) {
  let n = list.length(dots)
  dots
  |> list.index_map(fn(d, i) {
    svg.circle([
      attr.classes([
        #("dot", True),
        #("dot-last", n - 1 == i),
      ]),
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

fn range_decoder(name: String, build: fn(Int) -> Msg) -> decode.Decoder(Msg) {
  decode.new_primitive_decoder(name, fn(data) {
    let v = event_value(data, -1.0)
    case v >=. 0.0 {
      True -> Ok(build(float.round(v)))
      False -> Error(Ignored)
    }
  })
}

fn circles_decoder() -> decode.Decoder(Msg) {
  range_decoder("circles-slider", fn(n) { SetCircles(n) })
}

fn speed_decoder() -> decode.Decoder(Msg) {
  range_decoder("speed-slider", fn(n) { SetSpeed(n) })
}
