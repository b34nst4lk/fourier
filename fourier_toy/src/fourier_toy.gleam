//// fourier toy — the quaver puzzle: tune four Fourier terms (phase, radius,
//// k) until the solid comet closes onto the dashed eighth-note target.
//// Final v2 shape: ONE puzzle, no routing — the app boots straight into
//// the board. The tested pure core (shapes + puzzle) owns the math; the
//// canvas/RAF/theme/hold drivers live in the FFI (sibling patterns).

import fourier_toy/ffi
import fourier_toy/puzzle.{type Setup}
import fourier_toy/shapes.{type TermState}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
import lustre/event

type Msg {
  SlotStep(Int, Int)
  Reset
  ToggleTheme
}

type Model {
  Model(state: List(TermState), dark: Bool, moves: Int, solved_once: Bool)
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn setup() -> Setup {
  puzzle.quaver_setup()
}

fn shape() {
  puzzle.shape_of(setup().shape)
}

fn init(_: Nil) -> #(Model, Effect(Msg)) {
  // stored choice (or system preference) decides the boot theme
  let dark = case ffi.theme_load() {
    "dark" -> True
    _ -> False
  }
  let state = puzzle.initial(shape(), setup().patches)
  #(
    Model(state, dark, 0, False),
    effect.batch([hold_driver(), sync_effect(state), theme_apply(dark)]),
  )
}

/// Mirror the boot theme onto the page and the canvas palette.
fn theme_apply(dark: Bool) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    ffi.canvas_theme(dark)
    ffi.set_dark(dark)
    Nil
  })
}

/// Bind the hold-to-repeat input driver once — its document-level listeners
/// cover the stepper rows through every later re-render.
fn hold_driver() -> Effect(Msg) {
  effect.from(fn(_dispatch) { ffi.hold_init() })
}

/// Push the canvas everything it needs: the (constant) quaver shape plus
/// the current dial terms.
fn sync_effect(state: List(TermState)) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    ffi.canvas_shape(shape())
    ffi.canvas_terms(state)
  })
}

fn push_terms(state: List(TermState)) -> Effect(Msg) {
  effect.from(fn(_dispatch) { ffi.canvas_terms(state) })
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SlotStep(slot, dir) -> {
      let kind = kind_at(setup().dials, slot)
      let stepped =
        list.index_map(model.state, fn(s, i) {
          case i == slot {
            True -> puzzle.step(kind, s, dir, shape().dial_max_r)
            False -> s
          }
        })
      // the counter freezes at the FIRST solve: steps after that don't
      // count — the number you solved in is the number you keep
      let #(moves, solved_once) = case model.solved_once {
        True -> #(model.moves, True)
        False -> #(model.moves + 1, shapes.solved(shape(), stepped))
      }
      #(Model(stepped, model.dark, moves, solved_once), push_terms(stepped))
    }
    Reset -> {
      let state = puzzle.initial(shape(), setup().patches)
      #(Model(state, model.dark, 0, False), push_terms(state))
    }
    ToggleTheme -> {
      let dark = case model.dark {
        True -> False
        False -> True
      }
      #(
        Model(model.state, dark, model.moves, model.solved_once),
        effect.from(fn(_dispatch) {
          ffi.canvas_theme(dark)
          ffi.set_dark(dark)
          ffi.theme_save(dark)
          Nil
        }),
      )
    }
  }
}

fn kind_at(dials: List(puzzle.DialKind), slot: Int) -> puzzle.DialKind {
  case list.drop(dials, slot) {
    [kind, ..] -> kind
    [] -> puzzle.DialFixed
  }
}

// ---------- view ----------

fn view(model: Model) -> Element(Msg) {
  let m = shapes.match_pct(shape(), model.state)
  board_view(model.state, m, model.moves, model.dark)
}

fn board_view(
  state: List(TermState),
  m: Float,
  moves: Int,
  dark: Bool,
) -> Element(Msg) {
  html.div([], [
    bar(m, moves, dark),
    html.h2([attribute.class("pt")], [html.text(setup().title)]),
    html.canvas([attribute.class("board"), attribute.id("toy-board")]),
    html.div(
      [attribute.class("rows")],
      list.index_map(setup().dials, fn(kind, i) { #(i, kind) })
        |> list.filter(fn(pair) { pair.1 != puzzle.DialFixed })
        |> list.map(fn(pair) {
          let #(i, kind) = pair
          let assert [s, ..] = list.drop(state, i)
          dial_row(kind, i, s)
        }),
    ),
  ])
}

fn bar(m: Float, moves: Int, dark: Bool) -> Element(Msg) {
  html.div([attribute.class("bar")], [
    html.span(
      [
        attribute.classes([
          #("score", True),
          #("solved", m >=. 95.0),
        ]),
      ],
      [
        html.text("Match "),
        html.b([], [html.text(puzzle.fmt1(m) <> "%")]),
        html.span([attribute.class("mv")], [
          html.text(" · " <> changes_text(moves)),
        ]),
        html.span([attribute.class("ok")], [html.text("solved ✓")]),
      ],
    ),
    html.div([attribute.class("tools")], [
      // reset chip: the standard counterclockwise icon, icon-only (the
      // aria-label keeps its meaning for screen readers)
      html.button(
        [
          attribute.classes([#("chip", True), #("reset", True)]),
          attribute.aria_label("reset to start"),
          event.on("click", decode.success(Reset)),
        ],
        [reset_icon()],
      ),
      // corner-chip toggle, icon-only: moon when light, sun when dark
      // (ink-colored inline SVG — no glyph that a platform can emoji-ize);
      // aria-label keeps the button's meaning for screen readers
      html.button(
        [
          attribute.classes([#("chip", True), #("theme", True)]),
          attribute.aria_label(case dark {
            True -> "light mode"
            False -> "dark mode"
          }),
          event.on("click", decode.success(ToggleTheme)),
        ],
        [
          case dark {
            True -> sun_icon()
            False -> moon_icon()
          },
        ],
      ),
    ]),
  ])
}

fn dial_row(kind: puzzle.DialKind, i: Int, s: TermState) -> Element(Msg) {
  let head = [
    html.div([attribute.class("id")], [
      html.span([attribute.class("term")], [
        html.text("term " <> int.to_string(i + 1)),
      ]),
      html.span([attribute.class("sub")], [
        html.text(puzzle.locked_note(kind, s, shape().dial_max_r)),
      ]),
    ]),
  ]
  let body = case kind {
    puzzle.DialFixed -> [
      html.div([attribute.class("val")], [html.text("not a dial")]),
    ]
    _ -> [
      edge_button(i, -1, at_min(kind, s)),
      html.div([attribute.class("val")], [
        html.text(puzzle.slot_value(kind, s, shape().dial_max_r)),
      ]),
      edge_button(i, 1, at_max(kind, s)),
    ]
  }
  html.div([attribute.class("row")], list.append(head, body))
  |> keep
}

fn at_min(kind: puzzle.DialKind, s: TermState) -> Bool {
  case kind {
    puzzle.DialK -> s.k <= -16
    puzzle.DialR -> s.r <=. 0.0
    _ -> False
  }
}

fn at_max(kind: puzzle.DialKind, s: TermState) -> Bool {
  case kind {
    puzzle.DialK -> s.k >= 16
    puzzle.DialR -> s.r >=. 2.0 *. shape().dial_max_r
    _ -> False
  }
}

fn edge_button(i: Int, dir: Int, disabled_flag: Bool) -> Element(Msg) {
  html.button(
    [
      attribute.class("btn"),
      attribute.disabled(disabled_flag),
      event.on("click", decode.success(SlotStep(i, dir))),
    ],
    [
      html.text(case dir > 0 {
        True -> "+"
        False -> "−"
      }),
    ],
  )
}

fn keep(el: Element(Msg)) -> Element(Msg) {
  el
}

/// One change per stepper step; the singular reads better at one.
fn changes_text(n: Int) -> String {
  case n {
    1 -> "1 change"
    _ -> int.to_string(n) <> " changes"
  }
}

// ---- icon chips (stroke geometry, 24×24 viewBox, inked via CSS) ----

/// The standard counterclockwise reset arrow (feather's rotate-ccw).
fn reset_icon() -> Element(Msg) {
  svg.svg(
    [attribute.class("icon"), attribute.attribute("viewBox", "0 0 24 24")],
    [
      svg.polyline([attribute.attribute("points", "1 4 1 10 7 10")]),
      svg.path([
        attribute.attribute("d", "M3.51 15a9 9 0 1 0 2.13-9.36L1 10"),
      ]),
    ],
  )
}

fn moon_icon() -> Element(Msg) {
  svg.svg(
    [attribute.class("icon"), attribute.attribute("viewBox", "0 0 24 24")],
    [
      svg.path([
        attribute.attribute(
          "d",
          "M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z",
        ),
      ]),
    ],
  )
}

fn sun_icon() -> Element(Msg) {
  let ray = fn(x1: String, y1: String, x2: String, y2: String) {
    svg.line([
      attribute.attribute("x1", x1),
      attribute.attribute("y1", y1),
      attribute.attribute("x2", x2),
      attribute.attribute("y2", y2),
    ])
  }
  svg.svg(
    [attribute.class("icon"), attribute.attribute("viewBox", "0 0 24 24")],
    [
      svg.circle([
        attribute.attribute("cx", "12"),
        attribute.attribute("cy", "12"),
        attribute.attribute("r", "5"),
      ]),
      ray("12", "1", "12", "3"),
      ray("12", "21", "12", "23"),
      ray("4.22", "4.22", "5.64", "5.64"),
      ray("18.36", "18.36", "19.78", "19.78"),
      ray("1", "12", "3", "12"),
      ray("21", "12", "23", "12"),
      ray("4.22", "19.78", "5.64", "18.36"),
      ray("18.36", "5.64", "19.78", "4.22"),
    ],
  )
}
