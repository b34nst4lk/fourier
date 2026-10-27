//// fourier toy — the daily puzzle board: tune the three dialed Fourier terms
//// (phase, radius, k) until the solid comet closes onto the dashed target.
////
//// One screen, no routing. Three states feed it (PLAN-fetch-first-boot.md §1):
////
////   * `Loading` — a cold start's first moment: `GET /api/puzzle/today` is
////     already out, nothing is cached, so the board shows a minimal loading
////     state (bar + empty canvas + disabled columns, no title, no score). It
////     lasts only for the fetch's duration.
////   * `Daily(date)` — a published puzzle, either from the fetch or from the
////     last-loaded cache (`j-last`), which paints OPTIMISTICALLY at boot so a
////     returning player never sees a wrong-puzzle flash. Decoded by `wire`,
////     entered by ONE code path; its attempt is stored and its solve reported.
////   * `Quaver` — the built-in quaver, reached only by a cold start that finds
////     nothing and cannot fetch. It tells no telemetry and stores nothing: it
////     has no date and no identity to report against.
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
  /// The fetch is out and nothing is cached: a minimal loading state — no
  /// title, no score, all glyphs disabled (nothing on screen claims a puzzle).
  Loading
  /// The built-in quaver — the cold-start fallback.
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
    /// today's name. (A cached boot consumes it immediately: the cache already
    /// says which day is on the board.)
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
  // the board's placeholder until the fetch (or the cache) says what today is
  let base =
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
    )
  // The last document that loaded, through the same live `wire.decode` the
  // fetch answer takes: if it still decodes, its day is on the board at once
  // (no wrong-puzzle flash) and the fetch can only confirm it, swap it, or
  // fail and leave it standing. No version field — the decoder IS the gate, so
  // a document that no longer decodes is simply a cold boot.
  let cached =
    ffi.ls_get(last_doc_key)
    |> result.try(wire.decode)
    |> option.from_result
  let #(model, entered) = case cached {
    Some(daily) -> enter_daily(base, daily, None)
    None -> #(Model(..base, source: Loading), effect.none())
  }
  #(
    model,
    batch([
      // the fetch goes FIRST: nothing syncs a canvas before it (§1.1)
      fetch_effect(),
      hold_driver(),
      theme_apply(dark),
      entered,
    ]),
  )
}

/// Run effects in the order given; an empty list is no effect at all.
///
/// `effect.batch` folds its list with a prepend, so handing it a list reverses
/// the running order — which silently breaks ordering contracts (the fetch must
/// go out before any canvas sync, the theme before the first draw). Reversing
/// here keeps "the order you read is the order they run".
fn batch(effects: List(Effect(Msg))) -> Effect(Msg) {
  case effects {
    [] -> effect.none()
    _ -> effect.batch(list.reverse(effects))
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

/// The raw document of the last successful load, kept for the next boot
/// (PLAN-fetch-first-boot.md §1.2). Best-effort, like every storage write, and
/// versionless on purpose: `wire.decode` IS the gate.
const last_doc_key = "j-last"

fn cache_effect(raw: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    let _ = ffi.ls_set(last_doc_key, raw)
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
    // the loading state has no board: its glyphs are disabled, and a step that
    // arrived anyway could only sync a canvas of placeholder nothing (or book
    // an attempt against a puzzle that does not exist yet)
    SlotStep(slot, dir) ->
      case model.source {
        Loading -> #(model, effect.none())
        _ -> slot_step(model, slot, dir)
      }
    Reset ->
      case model.source {
        Loading -> #(model, effect.none())
        _ -> reset(model)
      }
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
        // the built-in fallback has no attempt to end (and the loading state
        // cannot be reset: its chip is disabled and `update` guards the message)
        _ -> #(
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
  case result {
    Error(Nil) -> fetch_failed(model)
    Ok(text) ->
      case wire.decode(text) {
        // a 2xx this decoder cannot use (a tunnel's HTML page, a newer format)
        Error(Nil) -> fetch_failed(model)
        // the body is worth keeping for the next boot BEFORE it is taken
        Ok(daily) -> enter_daily(model, daily, Some(text))
      }
  }
}

/// The fetch settled without a puzzle: "none", a failed request, or a document
/// this decoder cannot use. Whatever is on screen stays — a cached daily is
/// fully playable for its own date — and only a cold start (the loading state,
/// which has painted nothing) falls through to the built-in quaver.
fn fetch_failed(model: Model) -> #(Model, Effect(Msg)) {
  case model.source {
    Loading -> {
      let model = Model(..model, source: Quaver)
      #(model, sync_effect(model.shape, model.state, model.setup.dials))
    }
    _ -> #(model, effect.none())
  }
}

/// Take a decoded document as the board's puzzle — the ONE path the cached boot
/// and the fetch answer share, so an offline board is a real daily by
/// construction (its own date, its own attempt, its own telemetry).
///
/// `cache_raw` is the raw body when the document came from the network (worth
/// keeping for the next boot). The boot's own read passes `None`: it IS the
/// cache, so rewriting it would be churn.
fn enter_daily(
  model: Model,
  daily: wire.DailyPuzzle,
  cache_raw: Option(String),
) -> #(Model, Effect(Msg)) {
  case model.source {
    // the answer confirms the day already on the board: the boot's resume (or
    // the swap that opened it) has already run, so this is a no-op — nothing
    // to repaint, nothing to store, nothing to re-post
    Daily(show_date) if show_date == daily.show_date -> #(model, effect.none())
    _ -> {
      let #(model, entered) = switch_daily(model, daily)
      let keep = case cache_raw {
        Some(raw) -> [cache_effect(raw)]
        None -> []
      }
      #(model, batch(list.flatten([keep, [entered]])))
    }
  }
}

fn switch_daily(
  model: Model,
  daily: wire.DailyPuzzle,
) -> #(Model, Effect(Msg)) {
  let start = puzzle.initial(daily.shape, daily.setup.patches)
  // the attempt this board is responsible for: the one read from storage at
  // boot (the cold path), or the live one (a cached board a newer day retires)
  let held = case model.stored {
    Some(a) -> Some(a)
    None -> model.attempt
  }
  let model =
    Model(
      ..model,
      setup: daily.setup,
      shape: daily.shape,
      source: Daily(daily.show_date),
      stored: None,
    )
  case held {
    // this day's attempt: resume exactly where it was left
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
    // unreachable: a slot at/after the dial count matches no term, so the
    // fallback never steers a step. Any dialable kind keeps the code total.
    [] -> puzzle.DialP
  }
}

// ---------- view ----------

fn view(model: Model) -> Element(Msg) {
  board_view(model)
}

fn board_view(model: Model) -> Element(Msg) {
  case model.source {
    // a cold start's fetch is still out: the bar and an empty board, the three
    // columns present with every glyph disabled — and no title and no score,
    // because nothing on this screen has a puzzle to name yet
    Loading -> {
      html.div([], [
        wordmark(),
        loading_bar(model.dark),
        // The title's slot stays OCCUPIED (an empty div, no text and no height)
        // so that the board canvas and the columns below keep their DOM
        // identity across the loading → puzzle transition: the FFI binds a
        // canvas by element, and a re-created one would stay blank until the
        // next sync.
        html.div([], []),
        html.canvas([attribute.class("board"), attribute.id("toy-board")]),
        html.div(
          [attribute.class("cols")],
          list.index_map(model.setup.dials, fn(kind, i) {
            dial_col_disabled(kind, i)
          }),
        ),
      ])
    }
    _ -> {
      html.div([], [
        wordmark(),
        bar(model.match, model.moves, model.dark),
        html.h2([attribute.class("pt")], [
          html.text(model.setup.title),
          when_tag(model.source),
        ]),
        html.canvas([attribute.class("board"), attribute.id("toy-board")]),
        html.div(
          [attribute.class("cols")],
          list.index_map(model.setup.dials, fn(kind, i) {
            let assert [s, ..] = list.drop(model.state, i)
            dial_col(kind, i, s, model.shape.dial_max_r)
          }),
        ),
      ])
    }
  }
}

/// The loading state's bar: the same chrome, an EMPTY score slot (no number, no
/// change count) and a disabled reset — there is nothing on the board to reset.
/// The theme chip stays live: the page's scheme never waits on the network.
fn loading_bar(dark: Bool) -> Element(Msg) {
  html.div([attribute.class("bar")], [
    html.span([attribute.class("score")], []),
    tools(dark, True),
  ])
}

/// The daily puzzle wears its date faintly beside its name, so a player can
/// tell one day's board from the next (neither the fallback nor the loading
/// state has a date).
fn when_tag(source: Source) -> Element(Msg) {
  html.span([attribute.class("when")], [
    html.text(case source {
      Daily(show_date) -> " · " <> show_date
      _ -> ""
    }),
  ])
}

/// The game's name — Doodle with the custom `e`: the bowl's arc is the
/// whole circle except a 55° aperture that opens UP-RIGHT of the tilt; the
/// bar docks INTO the bowl at the aperture's upper rim (the arc's own end
/// point — a direct connection, no chin) and runs inward to the centre; the
/// whole mark tilted 45° up. Raster-verified before insertion.
fn wordmark() -> Element(Msg) {
  html.div([attribute.class("brand")], [
    html.span([attribute.class("wm")], [
      html.text("Doodl"),
      svg.svg(
        [
          attribute.class("e"),
          attribute.attribute("viewBox", "11.5 16.5 77 77"),
        ],
        [
          svg.path([
            attribute.attribute("d", "M 81.5 60.6 A 32 32 0 1 1 72.6 32.4"),
          ]),
          svg.path([
            attribute.attribute("d", "M 72.6 32.4 L 50 55"),
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
    tools(dark, False),
  ])
}

/// The two icon chips. `reset_disabled` is the loading state's version: the
/// board has no start to skip back to.
fn tools(dark: Bool, reset_disabled: Bool) -> Element(Msg) {
  html.div([attribute.class("tools")], [
    // reset chip: skip-back-to-start, icon-only (the aria-label keeps its
    // meaning for screen readers)
    html.button(
      [
        attribute.classes([#("chip", True), #("reset", True)]),
        attribute.aria_label("reset to start"),
        attribute.disabled(reset_disabled),
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
  ])
}

/// One dial column: [glyph ↑][canvas col-N][glyph ↓], no text nodes at all.
/// Up steps +1; down steps −1. The glyphs wear motion-matching feathers, and
/// the column's ink is its ORDINAL (CSS `nth-child`), not its kind.
fn dial_col(
  kind: puzzle.DialKind,
  slot: Int,
  s: TermState,
  max_r: Float,
) -> Element(Msg) {
  col(kind, slot, at_max(kind, s, max_r), at_min(kind, s))
}

/// The loading state's column: both glyphs disabled, because there is no puzzle
/// to step yet.
fn dial_col_disabled(kind: puzzle.DialKind, slot: Int) -> Element(Msg) {
  col(kind, slot, True, True)
}

fn col(
  kind: puzzle.DialKind,
  slot: Int,
  top_edge: Bool,
  bottom_edge: Bool,
) -> Element(Msg) {
  html.div([attribute.class("col")], [
    glyph_button(kind, slot, 1, top_edge),
    html.canvas([
      attribute.class("dial"),
      attribute.id("col-" <> int.to_string(slot)),
    ]),
    glyph_button(kind, slot, -1, bottom_edge),
  ])
}

/// `button.btn` is the hold-to-repeat driver's hook (the FFI listens on the
/// document for it); the glyph is the icon-only face of the same stepper.
fn glyph_button(
  kind: puzzle.DialKind,
  slot: Int,
  dir: Int,
  at_edge: Bool,
) -> Element(Msg) {
  let label = case dir > 0 {
    True -> "increase " <> kind_name(kind)
    False -> "decrease " <> kind_name(kind)
  }
  html.button(
    [
      attribute.classes([#("btn", True), #("glyph", True)]),
      attribute.aria_label(label),
      attribute.disabled(at_edge),
      event.on("click", decode.success(SlotStep(slot, dir))),
    ],
    [glyph_icon(kind, dir)],
  )
}

/// The word the aria-label names the dial with (the glyph says the action).
fn kind_name(kind: puzzle.DialKind) -> String {
  case kind {
    puzzle.DialP -> "phase"
    puzzle.DialR -> "radius"
    puzzle.DialK -> "k"
  }
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

/// Motion-matching glyphs (feather's 24×24 stroke geometry): the arrow shows
/// what the button does, the column's ink shows which wheel it turns.
fn glyph_icon(kind: puzzle.DialKind, dir: Int) -> Element(Msg) {
  case kind, dir > 0 {
    puzzle.DialP, True ->
      glyph_svg([
        svg.polyline([attribute.attribute("points", "23 4 23 10 17 10")]),
        svg.path([
          attribute.attribute("d", "M20.49 15a9 9 0 1 1-2.12-9.36L23 10"),
        ]),
      ])
    puzzle.DialP, False ->
      glyph_svg([
        svg.polyline([attribute.attribute("points", "1 4 1 10 7 10")]),
        svg.path([
          attribute.attribute("d", "M3.51 15a9 9 0 1 0 2.13-9.36L1 10"),
        ]),
      ])
    puzzle.DialR, True ->
      glyph_svg([
        svg.polyline([attribute.attribute("points", "15 3 21 3 21 9")]),
        svg.polyline([attribute.attribute("points", "9 21 3 21 3 15")]),
        svg.line([
          attribute.attribute("x1", "21"),
          attribute.attribute("y1", "3"),
          attribute.attribute("x2", "14"),
          attribute.attribute("y2", "10"),
        ]),
        svg.line([
          attribute.attribute("x1", "3"),
          attribute.attribute("y1", "21"),
          attribute.attribute("x2", "10"),
          attribute.attribute("y2", "14"),
        ]),
      ])
    puzzle.DialR, False ->
      glyph_svg([
        svg.polyline([attribute.attribute("points", "4 14 10 14 10 20")]),
        svg.polyline([attribute.attribute("points", "20 10 14 10 14 4")]),
        svg.line([
          attribute.attribute("x1", "14"),
          attribute.attribute("y1", "10"),
          attribute.attribute("x2", "21"),
          attribute.attribute("y2", "3"),
        ]),
        svg.line([
          attribute.attribute("x1", "3"),
          attribute.attribute("y1", "21"),
          attribute.attribute("x2", "10"),
          attribute.attribute("y2", "14"),
        ]),
      ])
    puzzle.DialK, True ->
      glyph_svg([
        svg.polygon([attribute.attribute("points", "13 19 22 12 13 5 13 19")]),
        svg.polygon([attribute.attribute("points", "2 19 11 12 2 5 2 19")]),
      ])
    puzzle.DialK, False ->
      glyph_svg([
        svg.polygon([attribute.attribute("points", "11 19 2 12 11 5 11 19")]),
        svg.polygon([attribute.attribute("points", "22 19 13 12 22 5 22 19")]),
      ])
  }
}

/// One change per stepper step; the singular reads better at one.
fn changes_text(n: Int) -> String {
  case n {
    1 -> "1 change"
    _ -> int.to_string(n) <> " changes"
  }
}

// ---- icon chips (stroke geometry, 24×24 viewBox, inked via CSS) ----

/// The shared svg shell: a 24×24 viewBox, `.icon` sizing, currentColor ink.
fn glyph_svg(children: List(Element(Msg))) -> Element(Msg) {
  svg.svg(
    [attribute.class("icon"), attribute.attribute("viewBox", "0 0 24 24")],
    children,
  )
}

/// Skip-back-to-start: a bar and a left-pointing triangle (feather's
/// skip-back). Reset returns the dials to the start, not the clock.
fn reset_icon() -> Element(Msg) {
  glyph_svg([
    svg.polygon([attribute.attribute("points", "19 20 9 12 19 4 19 20")]),
    svg.line([
      attribute.attribute("x1", "5"),
      attribute.attribute("y1", "19"),
      attribute.attribute("x2", "5"),
      attribute.attribute("y2", "5"),
    ]),
  ])
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
