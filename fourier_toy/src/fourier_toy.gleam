//// fourier toy — the daily puzzle board: tune four Fourier terms (phase,
//// radius, k) until the solid comet closes onto the dashed target.
////
//// One screen, no routing. Two sources feed it (PLAN-daily-puzzles.md §1):
////
////   * `Daily(date)` — today's published puzzle, fetched from
////     `/api/puzzle/today` and decoded by `wire`; its attempt is stored and its
////     solve is reported.
////   * `Quaver` — the built-in quaver, which is what the board paints FIRST
////     (deterministically, before any network answer) and what it falls back to
////     when there is no puzzle today, the fetch fails, or the document is
////     unusable. The fallback tells no telemetry and stores nothing: it has no
////     date and no identity to report against.
////
//// The tested pure core owns the math (shapes + puzzle), the stored attempt's
//// codec and transitions (attempt), and the served document's decoder (wire).
//// This module owns the wiring between them and the FFI: canvas sync, storage,
//// fetch, and the two POSTs. Its behaviour is pinned by
//// scripts/artifact_smoke.mjs (S8), the house contract for the view/FFI layer.

import fourier_toy/attempt
import fourier_toy/ffi
import fourier_toy/puzzle.{type Setup}
import fourier_toy/shapes.{type TermState}
import fourier_toy/wire
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
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
  /// The daily fetch settled: the body text of a 2xx, or a failure.
  PuzzleFetched(Result(String, Nil))
  /// A solve POST came back 2xx: the attempt has nothing left to report.
  SolveReported
}

type Source {
  /// The built-in quaver (the first paint, and the fallback).
  Quaver
  /// Today's published puzzle, by show date.
  Daily(show_date: String)
}

type Model {
  // the immutable fixture data is memoized once per puzzle (a 512-point
  // synth_trace + the term table); the live match is computed once per step
  // and read by the view — never rebuilt per render
  Model(
    setup: Setup,
    shape: shapes.Shape,
    source: Source,
    state: List(TermState),
    dark: Bool,
    moves: Int,
    solved_once: Bool,
    match: Float,
    /// The site-wide anonymous identity (Q16) — empty only if the platform
    /// gave us nothing, in which case nothing is reported.
    uuid: String,
    /// The live attempt for `source`. None while the board is the built-in
    /// quaver: the fallback is not an attempt (no date, no storage, no POST).
    attempt: Option(attempt.Attempt),
    /// An attempt read from storage at boot, HELD until the fetch says which
    /// puzzle today is. Applying it early would paint yesterday's dials under
    /// today's name — and the board must paint the quaver first anyway.
    stored: Option(attempt.Attempt),
  )
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_: Nil) -> #(Model, Effect(Msg)) {
  // stored choice (or system preference) decides the boot theme
  let dark = case ffi.theme_load() {
    "dark" -> True
    _ -> False
  }
  let setup = puzzle.quaver_setup()
  let shape = puzzle.shape_of(setup.shape)
  let state = puzzle.initial(shape, setup.patches)
  #(
    Model(
      setup: setup,
      shape: shape,
      source: Quaver,
      state: state,
      dark: dark,
      moves: 0,
      solved_once: False,
      match: shapes.match_pct(shape, state),
      uuid: ffi.uuid_ensure(),
      attempt: None,
      stored: ffi.ls_get(attempt.storage_key)
        |> result.try(attempt.decode)
        |> option.from_result,
    ),
    batch([
      hold_driver(),
      sync_effect(shape, state, setup.dials),
      theme_apply(dark),
      fetch_effect(),
    ]),
  )
}

/// Run effects in order; an empty list is no effect at all.
fn batch(effects: List(Effect(Msg))) -> Effect(Msg) {
  case effects {
    [] -> effect.none()
    _ -> effect.batch(effects)
  }
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

/// Push the canvas everything it needs: this puzzle's shape plus the current
/// dial terms.
fn sync_effect(
  shape: shapes.Shape,
  state: List(TermState),
  kinds: List(puzzle.DialKind),
) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    ffi.canvas_shape(shape)
    ffi.canvas_terms(state, kinds)
  })
}

fn push_terms(
  state: List(TermState),
  kinds: List(puzzle.DialKind),
) -> Effect(Msg) {
  effect.from(fn(_dispatch) { ffi.canvas_terms(state, kinds) })
}

/// Ask for today's puzzle. `tz` is minutes to ADD to UTC (the API's spelling),
/// so the backend resolves the visitor's own date.
fn fetch_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    ffi.fetch_puzzle(
      ffi.tz_offset_minutes(),
      fn(text) { dispatch(PuzzleFetched(Ok(text))) },
      fn() { dispatch(PuzzleFetched(Error(Nil))) },
    )
  })
}

/// Keep the attempt: after every step, and at the two boundaries (a fresh
/// attempt, a reported solve). Best-effort — private mode just means the tab
/// cannot resume.
fn persist_effect(a: attempt.Attempt) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    let _ = ffi.ls_set(attempt.storage_key, attempt.encode(a))
    Nil
  })
}

fn saved(attempt_state: Option(attempt.Attempt)) -> List(Effect(Msg)) {
  case attempt_state {
    Some(a) -> [persist_effect(a)]
    None -> []
  }
}

/// POST the solve. Fire-and-forget: the answer only retires the pending report,
/// and a solve that never lands is re-sent by the next boot (`reported: false`).
fn solve_effect(uuid: String, a: attempt.Attempt) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    ffi.post_telemetry("/api/solve", attempt.solve_body(uuid, a), fn() {
      dispatch(SolveReported)
    })
  })
}

/// POST the abandonment of an unsolved attempt (Q21).
fn abandon_effect(uuid: String, a: attempt.Attempt) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    ffi.post_telemetry(
      "/api/attempts/abandon",
      attempt.abandon_body(uuid, a),
      fn() { Nil },
    )
  })
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SlotStep(slot, dir) -> slot_step(model, slot, dir)
    Reset -> reset(model)
    ToggleTheme -> {
      let dark = case model.dark {
        True -> False
        False -> True
      }
      #(
        Model(..model, dark: dark),
        effect.from(fn(_dispatch) {
          ffi.canvas_theme(dark)
          ffi.set_dark(dark)
          ffi.theme_save(dark)
          Nil
        }),
      )
    }
    PuzzleFetched(result) -> puzzle_fetched(model, result)
    SolveReported -> solve_reported(model)
  }
}

fn slot_step(model: Model, slot: Int, dir: Int) -> #(Model, Effect(Msg)) {
  let kind = kind_at(model.setup.dials, slot)
  let stepped =
    list.index_map(model.state, fn(s, i) {
      case i == slot {
        True -> puzzle.step(kind, s, dir, model.shape.dial_max_r)
        False -> s
      }
    })
  // the metric is computed ONCE per step: the solved gate, the view's score
  // and the attempt's `solved` flag all read this result
  let match = shapes.match_pct(model.shape, stepped)
  let solved_before = model.solved_once
  // the counter freezes at the FIRST solve: steps after that don't count —
  // the number you solved in is the number you keep
  let moves = case solved_before {
    True -> model.moves
    False -> model.moves + 1
  }
  let solved_now = case solved_before {
    True -> True
    False -> match >=. shapes.solved_at
  }
  let next_attempt = case model.attempt {
    None -> None
    Some(a) -> {
      // the move list stops at the first solve, like the counter
      let a = case solved_before {
        True -> a
        False -> attempt.add_move(a, slot, dir)
      }
      Some(attempt.record(a, stepped, moves, solved_now))
    }
  }
  let model =
    Model(
      ..model,
      state: stepped,
      match: match,
      moves: moves,
      solved_once: solved_now,
      attempt: next_attempt,
    )
  // the solve moment is the one moment that posts — and it marks the attempt
  // reported only when the server says it landed
  let effects = case solved_before, next_attempt {
    False, Some(a) if solved_now -> [solve_effect(model.uuid, a)]
    _, _ -> []
  }
  #(
    model,
    batch(
      list.flatten([
        [push_terms(stepped, model.setup.dials)],
        effects,
        saved(next_attempt),
      ]),
    ),
  )
}

fn reset(model: Model) -> #(Model, Effect(Msg)) {
  // the dials go back to start — and before any solve the counter zeroes and
  // the attempt ends; after a solve the record survives (the number you solved
  // in is the number you keep, reset or not)
  let state = puzzle.initial(model.shape, model.setup.patches)
  let match = shapes.match_pct(model.shape, state)
  case model.solved_once {
    True -> {
      let next_attempt = case model.attempt {
        Some(a) -> Some(attempt.record(a, state, model.moves, True))
        None -> None
      }
      let model =
        Model(..model, state: state, match: match, attempt: next_attempt)
      #(
        model,
        batch(
          list.flatten([
            [push_terms(state, model.setup.dials)],
            saved(next_attempt),
          ]),
        ),
      )
    }
    False -> {
      // an unsolved attempt that was actually played is ABANDONED before it is
      // replaced (Q21): the backend keeps the day's record, so difficulty data
      // is not biased toward the attempts that ended in a solve
      let retire = case model.attempt {
        Some(a) if a.count > 0 -> [abandon_effect(model.uuid, a)]
        _ -> []
      }
      let model = Model(..model, state: state, match: match, moves: 0)
      case model.source {
        Daily(date) -> {
          let fresh = attempt.fresh(date, state)
          let model = Model(..model, attempt: Some(fresh))
          #(
            model,
            batch(
              list.flatten([
                [push_terms(state, model.setup.dials)],
                retire,
                [persist_effect(fresh)],
              ]),
            ),
          )
        }
        // the built-in fallback has no attempt to end
        Quaver -> #(
          Model(..model, attempt: None),
          batch(list.flatten([[push_terms(state, model.setup.dials)], retire])),
        )
      }
    }
  }
}

fn puzzle_fetched(
  model: Model,
  result: Result(String, Nil),
) -> #(Model, Effect(Msg)) {
  // A failure or a "none" envelope leaves the board exactly as it is — the
  // player may already be playing the quaver, and there is nothing to report.
  let decoded =
    result
    |> result.try(wire.decode)
  case decoded {
    Error(Nil) -> #(model, effect.none())
    Ok(daily) -> enter_daily(model, daily)
  }
}

fn enter_daily(model: Model, daily: wire.DailyPuzzle) -> #(Model, Effect(Msg)) {
  let start = puzzle.initial(daily.shape, daily.setup.patches)
  let held = model.stored
  let model =
    Model(
      ..model,
      setup: daily.setup,
      shape: daily.shape,
      source: Daily(daily.show_date),
      stored: None,
    )
  case held {
    // today's attempt: resume exactly where it was left
    Some(stored) if stored.date == daily.show_date -> resume(model, stored)
    // an earlier day's attempt: retire it, then open today clean
    Some(old_attempt) -> retire_then_open(model, old_attempt, daily, start)
    None -> open_fresh(model, daily.show_date, start, [])
  }
}

fn resume(model: Model, stored: attempt.Attempt) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      ..model,
      state: stored.state,
      match: shapes.match_pct(model.shape, stored.state),
      moves: stored.count,
      solved_once: stored.solved,
      attempt: Some(stored),
    )
  // a solve that never reached the server (offline, closed tab) is re-sent now:
  // the backend's solve REPLACES the row, so a duplicate costs nothing
  let replay = case stored.solved, stored.reported {
    True, False -> [solve_effect(model.uuid, stored)]
    _, _ -> []
  }
  #(
    model,
    batch(
      list.flatten([
        [sync_effect(model.shape, stored.state, model.setup.dials)],
        replay,
      ]),
    ),
  )
}

fn retire_then_open(
  model: Model,
  old_attempt: attempt.Attempt,
  daily: wire.DailyPuzzle,
  start: List(TermState),
) -> #(Model, Effect(Msg)) {
  let retire = case old_attempt.solved, old_attempt.reported {
    // a solve from that day that never landed: report it before the day is
    // forgotten (it is worth more than the abandon)
    True, False -> [solve_effect(model.uuid, old_attempt)]
    // started and dropped: the abandon record (Q21)
    False, _ -> [abandon_effect(model.uuid, old_attempt)]
    True, True -> []
  }
  open_fresh(model, daily.show_date, start, retire)
}

fn open_fresh(
  model: Model,
  show_date: String,
  start: List(TermState),
  before: List(Effect(Msg)),
) -> #(Model, Effect(Msg)) {
  let fresh = attempt.fresh(show_date, start)
  let model =
    Model(
      ..model,
      source: Daily(show_date),
      state: start,
      match: shapes.match_pct(model.shape, start),
      moves: 0,
      solved_once: False,
      attempt: Some(fresh),
    )
  #(
    model,
    batch(
      list.flatten([
        before,
        [sync_effect(model.shape, start, model.setup.dials)],
        [persist_effect(fresh)],
      ]),
    ),
  )
}

fn solve_reported(model: Model) -> #(Model, Effect(Msg)) {
  case model.attempt {
    None -> #(model, effect.none())
    Some(a) -> {
      case a.reported {
        // a duplicate callback (or a stale one): nothing to store
        True -> #(model, effect.none())
        False -> {
          let a = attempt.mark_reported(a)
          let model = Model(..model, attempt: Some(a))
          #(model, batch(saved(Some(a))))
        }
      }
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
  board_view(model)
}

fn board_view(model: Model) -> Element(Msg) {
  html.div([], [
    wordmark(),
    bar(model.match, model.moves, model.dark),
    html.h2([attribute.class("pt")], [
      html.text(model.setup.title),
      when_tag(model.source),
    ]),
    html.canvas([attribute.class("board"), attribute.id("toy-board")]),
    html.div(
      [attribute.class("rows")],
      list.index_map(model.setup.dials, fn(kind, i) { #(i, kind) })
        |> list.filter(fn(pair) { pair.1 != puzzle.DialFixed })
        |> list.map(fn(pair) {
          let #(i, kind) = pair
          let assert [s, ..] = list.drop(model.state, i)
          dial_row(kind, i, s, model.shape.dial_max_r)
        }),
    ),
  ])
}

/// The daily puzzle wears its date faintly beside its name, so a player can
/// tell one day's board from the next (the built-in fallback has no date).
fn when_tag(source: Source) -> Element(Msg) {
  html.span([attribute.class("when")], [
    html.text(case source {
      Daily(show_date) -> " · " <> show_date
      Quaver -> ""
    }),
  ])
}

/// The game's name — Doodle with the custom `e`: a vertically flipped
/// capital G read as a lowercase e — the bowl incomplete on the RIGHT (the
/// cross stroke sits where the gap is), the bar a chord from the edge to the
/// centre, the chin hanging UP from the bar's outer end with a free tip; the
/// whole mark tilted 45° up. Raster-verified before insertion.
fn wordmark() -> Element(Msg) {
  html.div([attribute.class("brand")], [
    html.span([attribute.class("wm")], [
      html.text("Doodl"),
      svg.svg(
        [attribute.class("e"), attribute.attribute("viewBox", "11 7 77 87")],
        [
          svg.path([
            attribute.attribute("d", "M 81.5 60.6 A 32 32 0 1 1 44.4 23.5"),
          ]),
          svg.path([
            attribute.attribute("d", "M 54.1 13.8 L 72.6 32.4 L 50 55"),
          ]),
        ],
      ),
    ]),
  ])
}

fn bar(m: Float, moves: Int, dark: Bool) -> Element(Msg) {
  html.div([attribute.class("bar")], [
    html.span(
      [
        attribute.classes([
          #("score", True),
          #("solved", m >=. shapes.solved_at),
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

fn dial_row(
  kind: puzzle.DialKind,
  i: Int,
  s: TermState,
  max_r: Float,
) -> Element(Msg) {
  let head = [
    html.div([attribute.class("id")], [
      html.span([attribute.class("term")], [
        html.text("term " <> int.to_string(i + 1)),
      ]),
      html.span([attribute.class("sub")], [
        html.text(puzzle.locked_note(kind, s, max_r)),
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
        html.text(puzzle.slot_value(kind, s, max_r)),
      ]),
      edge_button(i, 1, at_max(kind, s, max_r)),
    ]
  }
  html.div(
    [
      attribute.classes([
        #("row", True),
        #(puzzle.kind_class(kind), True),
        // the row wears its kind's ink
      ]),
    ],
    list.append(head, body),
  )
}

fn at_min(kind: puzzle.DialKind, s: TermState) -> Bool {
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
