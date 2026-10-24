//// fourier toy v2 — dial experiments against fixture shapes, rendered as
//// always-on epicycle + comet illustrations on canvas, with the score and
//// dial rows driven by the tested pure core (shapes + puzzle modules).
////
//// Architecture (the sibling's proven split): Lustre owns puzzle state,
//// dial state, score, and the row UI; the canvas lives on the FFI side and
//// runs its own RAF loop — Gleam pushes shape/terms/theme in on change
//// (cache-deduped there), exactly like fourier_sketch's panel-2.

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
  HashChange(String)
  SlotStep(Int, Int)
  Reset
  ToggleTheme
}

type Page {
  Home
  Board(setup: Setup, state: List(TermState), match_pct: Float)
}

type Model {
  Model(page: Page, dark: Bool)
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_: Nil) -> #(Model, Effect(Msg)) {
  let model = Model(route(ffi.hash_now()), False)
  #(model, effect.batch([watch_hash(), hold_driver(), sync_effect(model.page)]))
}

/// Bind the hold-to-repeat input driver once — its document-level listeners
/// cover stepper rows re-rendered by any later route change.
fn hold_driver() -> Effect(Msg) {
  effect.from(fn(_dispatch) { ffi.hold_init() })
}

fn route(hash: String) -> Page {
  case puzzle.find(hash) {
    Ok(setup) -> {
      let shape = puzzle.shape_of(setup.shape)
      let state = puzzle.initial(shape, setup.patches)
      Board(setup, state, shapes.match_pct(shape, state))
    }
    Error(Nil) -> Home
  }
}

fn watch_hash() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    ffi.hash_watch(fn(hash) { dispatch(HashChange(hash)) })
  })
}

/// Push the canvas everything it needs for the page we're on.
fn sync_effect(page: Page) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    case page {
      Home -> Nil
      Board(setup, state, _) -> {
        let shape = puzzle.shape_of(setup.shape)
        ffi.canvas_shape(shape)
        ffi.canvas_terms(state)
        Nil
      }
    }
  })
}

fn push_terms(state: List(TermState)) -> Effect(Msg) {
  effect.from(fn(_dispatch) { ffi.canvas_terms(state) })
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    HashChange(hash) -> {
      let page = route(hash)
      #(Model(page, model.dark), sync_effect(page))
    }
    SlotStep(slot, dir) ->
      case model.page {
        Board(setup, state, _) -> {
          let shape = puzzle.shape_of(setup.shape)
          let kind = kind_at(setup.dials, slot)
          let stepped =
            list.index_map(state, fn(s, i) {
              case i == slot {
                True -> puzzle.step(kind, s, dir, shape.dial_max_r)
                False -> s
              }
            })
          let page = Board(setup, stepped, shapes.match_pct(shape, stepped))
          #(Model(page, model.dark), push_terms(stepped))
        }
        Home -> #(model, effect.none())
      }
    Reset ->
      case model.page {
        Board(setup, _, _) -> {
          let shape = puzzle.shape_of(setup.shape)
          let state = puzzle.initial(shape, setup.patches)
          let page = Board(setup, state, shapes.match_pct(shape, state))
          #(Model(page, model.dark), push_terms(state))
        }
        Home -> #(model, effect.none())
      }
    ToggleTheme -> {
      let dark = case model.dark {
        True -> False
        False -> True
      }
      #(
        Model(model.page, dark),
        effect.from(fn(_dispatch) {
          ffi.canvas_theme(dark)
          ffi.set_dark(dark)
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
  case model.page {
    Home -> home_view()
    Board(setup, state, m) -> board_view(setup, state, m, model.dark)
  }
}

fn home_view() -> Element(Msg) {
  html.div([], [
    html.p([attribute.class("intro")], [
      html.text(
        "Dial experiments against four targets: the sketch's star, a 6-petal flower, a fish drawn from its terms, and a quaver (♪). The puzzle terms are each shape's real fourier coefficients (the k=0 centroid is fixed and never shown as a dial). Match the dashed target by closing the solid comet.",
      ),
    ]),
    html.div(
      [attribute.class("cards")],
      list.map(puzzle.setups(), fn(setup) {
        html.a([attribute.class("card"), attribute.href("#" <> setup.id)], [
          html.span([attribute.class("card-t")], [html.text(setup.title)]),
          html.span([attribute.class("card-d")], [html.text(setup.desc)]),
        ])
      }),
    ),
    html.p([attribute.class("note")], [
      html.text(
        "solved at ≥ 95% · the star's board tops out at ≈ 97.7% (the traced star is not exactly a 4-term curve); the others are exact targets (tops at 100%) · the fish and quaver carry fixed higher-harmonic extras baked into both traces · a wrong k on a dominant term shows 0 — no partial credit — while the same wrong k on a small term is graded gently · animation always on, at half the sketch's max speed",
      ),
    ]),
  ])
}

fn bar(dark: Bool, m: Float) -> Element(Msg) {
  html.div([attribute.class("bar")], [
    html.a([attribute.class("back"), attribute.href("#")], [
      html.text("← experiments"),
    ]),
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
        html.span([attribute.class("ok")], [html.text("solved ✓")]),
      ],
    ),
    // corner-chip toggle, icon-only: moon when light, sun when dark
    // (ink-colored inline SVG — no glyph that a platform can emoji-ize);
    // aria-label keeps the button's meaning for screen readers
    html.button(
      [
        attribute.class("theme"),
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
  ])
}

fn board_view(
  setup: Setup,
  state: List(TermState),
  m: Float,
  dark: Bool,
) -> Element(Msg) {
  html.div([], [
    bar(dark, m),
    html.h2([attribute.class("pt")], [
      html.text(setup.title),
    ]),
    html.canvas([attribute.class("board"), attribute.id("toy-board")]),
    html.div(
      [attribute.class("rows")],
      list.index_map(setup.dials, fn(kind, i) { #(i, kind) })
        |> list.filter(fn(pair) { pair.1 != puzzle.DialFixed })
        |> list.map(fn(pair) {
          let #(i, kind) = pair
          let assert [s, ..] = list.drop(state, i)
          dial_row(setup, kind, i, s)
        }),
    ),
    html.button(
      [attribute.class("reset"), event.on("click", decode.success(Reset))],
      [html.text("reset to start")],
    ),
  ])
}

fn dial_row(
  setup: Setup,
  kind: puzzle.DialKind,
  i: Int,
  s: TermState,
) -> Element(Msg) {
  let shape = puzzle.shape_of(setup.shape)
  let head = [
    html.div([attribute.class("id")], [
      html.span([attribute.class("term")], [
        html.text("term " <> int.to_string(i + 1)),
      ]),
      html.span([attribute.class("sub")], [
        html.text(puzzle.locked_note(kind, s, shape.dial_max_r)),
      ]),
    ]),
  ]
  let body = case kind {
    puzzle.DialFixed -> [
      html.div([attribute.class("val")], [html.text("not a dial")]),
    ]
    _ -> [
      edge_button(i, -1, at_min(kind, s, shape.dial_max_r)),
      html.div([attribute.class("val")], [
        html.text(puzzle.slot_value(kind, s, shape.dial_max_r)),
      ]),
      edge_button(i, 1, at_max(kind, s, shape.dial_max_r)),
    ]
  }
  html.div([attribute.class("row")], list.append(head, body))
  |> keep
}

fn at_min(kind: puzzle.DialKind, s: TermState, _max_r: Float) -> Bool {
  case kind {
    puzzle.DialK -> s.k <= -16
    puzzle.DialR -> s.r <=. 0.0
    _ -> False
  }
}

fn at_max(kind: puzzle.DialKind, s: TermState, max_r: Float) -> Bool {
  case kind {
    puzzle.DialK -> s.k >= 16
    puzzle.DialR -> s.r >=. 2.0 *. max_r
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

// ---- theme icons (stroke geometry, 24×24 viewBox, inked via CSS) ----

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
