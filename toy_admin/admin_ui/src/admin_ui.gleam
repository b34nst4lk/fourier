//// The admin browser UI (PLAN-daily-puzzles.md §3 Q18, phase 4b).
////
//// Three views over one API, one page:
////
////   MENU       the calendar: every puzzle with its Q23 numbers, and the three
////              verbs that act on a row (test / edit / delete)
////   AUTHORING  draw dots, name the puzzle, pick a show date, save it — and see
////              a LIVE panel of the toy's board while drawing; anything can be
////              test-played full-size, unsaved (POST /api/admin/preview)
////   TEST-PLAY  the toy's own board: the four dials, the comet, the match
////
//// Design notes that outlive this file:
////
////   - The browser does NO derivation. The fixture (centroid, dial truth,
////     extras, target) always arrives from the server, so what the editor
////     previews is literally what the toy will serve. The only maths here is the
////     match metric (score.gleam), which the toy also computes client-side.
////   - Test play is fed by PREVIEW, never by a save: an admin can try a drawing
////     before committing a date to it.
////   - Errors are shown, not swallowed: `wire.failure_text` turns the envelope's
////     error names into words, and a name it does not know is printed verbatim.
////   - Delete is armed, not confirmed twice-from-nowhere: the button becomes
////     `sure?` for two seconds and a second click inside that window deletes. A
////     stray click costs nothing; a deliberate second click is still one.
////   - The fence is the SERVER's (Cloudflare Access); this UI is served behind
////     it, and an expired session shows up as the 401 banner.

import admin_ui/dial
import admin_ui/draw
import admin_ui/score
import admin_ui/wire
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// ---------- the browser boundary ----------

@external(javascript, "./fetch.mjs", "fetch_request")
fn fetch_request(
  method: String,
  path: String,
  body: String,
  on_done: fn(Int, String) -> Nil,
) -> Nil

@external(javascript, "./fetch.mjs", "after")
fn after(ms: Int, callback: fn() -> Nil) -> Nil

// The preview debounce's timer. fetch.mjs keeps ONE slot and cancels the
// previous timer on every call, so a burst of taps leaves exactly one live
// timer (the generation guard in `update` is the second line of defence, for a
// timer that fires after the drawing moved on).
@external(javascript, "./fetch.mjs", "preview_after")
fn preview_after(ms: Int, callback: fn() -> Nil) -> Nil

@external(javascript, "./canvas.mjs", "event_point")
fn event_point(event: dynamic.Dynamic) -> #(Float, Float, Bool)

@external(javascript, "./canvas.mjs", "draw_render")
fn draw_render(path: String, dots: List(#(Float, Float))) -> Nil

// One play driver, two boards: `board_id` says which canvas this view mounts
// (`play-board` for test play, `preview-board` for the authoring panel). The
// driver looks up exactly that id, so a view swap can never attach to the
// canvas that is about to leave the DOM.
@external(javascript, "./canvas.mjs", "play_shape")
fn play_shape(
  board_id: String,
  centroid: #(Float, Float),
  target: List(#(Float, Float)),
  extras: List(#(Int, Float, Float)),
) -> Nil

@external(javascript, "./canvas.mjs", "play_terms")
fn play_terms(
  board_id: String,
  dial: List(#(Int, Float, Float)),
  kinds: List(Int),
) -> Nil

@external(javascript, "./canvas.mjs", "play_stop")
fn play_stop() -> Nil

const api_puzzles = "/api/admin/puzzles"

const preview_path = "/api/admin/preview"

/// How long a delete button stays armed, in milliseconds.
const arm_ms = 2000

/// How long a drawing change waits before the panel asks for a preview: a
/// burst of taps is one request, not one per dot.
const preview_debounce_ms = 300

/// The full board's canvas (test play) and the authoring panel's; one play
/// driver serves whichever is mounted.
const play_board_id = "play-board"

const preview_board_id = "preview-board"

// ---------- state ----------

pub type View {
  Menu
  Authoring
  TestPlay
}

/// A test-play session: the fixture the server derived, the player's dials, and
/// the score computed from them (never from the server: the toy scores in the
/// browser, so the editor does too).
pub type Play {
  Play(
    fixture: wire.Fixture,
    kinds: List(dial.Kind),
    terms: List(score.Term),
    target: List(score.Point),
    normalizer: Float,
    match: Float,
    moves: Int,
    solved_once: Bool,
  )
}

/// The panel's debounce record. The timer itself is the FFI's one slot
/// (fetch.mjs `preview_after`), which this record cannot see; what it carries
/// is what makes a fire or an answer discardable on this side:
///
///   - `generation` is monotone and bumps on every draw change — it is the
///     request id, stamped on the fire and on the POST that follows it;
///   - `scheduled` is the generation whose timer is armed (None once it fired
///     or was superseded), so a superseded fire is a no-op;
///   - `inflight` is the generation of the POST awaiting an answer, so an
///     answer that lands after a newer request was SENT is discarded.
///
/// The panel keeps the last good fixture while this record churns.
pub type PreviewClock {
  PreviewClock(generation: Int, scheduled: Option(Int), inflight: Option(Int))
}

pub type Model {
  Model(
    view: View,
    rows: List(wire.Row),
    busy: Bool,
    flash: Option(String),
    failure: Option(wire.Failure),
    editing: Option(Int),
    name: String,
    show_date: String,
    drawing: draw.Drawing,
    play: Option(Play),
    armed: Option(Int),
    preview: Option(wire.Fixture),
    preview_pending: Bool,
    preview_stale: Bool,
    preview_start: Bool,
    preview_scheduled: PreviewClock,
  )
}

pub type Msg {
  Refresh
  RowsLoaded(Result(List(wire.Row), wire.Failure))
  StartNew
  StartEdit(Int)
  StartTest(Int)
  TestLoaded(Result(wire.Fixture, wire.Failure))
  DotsLoaded(Result(List(score.Point), wire.Failure))
  DotsTapped(#(Float, Float))
  Undo
  Clear
  NameChanged(String)
  ShowDateChanged(String)
  Save
  Saved(Result(Nil, wire.Failure))
  Preview
  Previewed(Result(wire.Fixture, wire.Failure))
  PreviewFire(Int)
  PanelPreviewed(Int, Result(wire.Fixture, wire.Failure))
  StartView
  TruthView
  DialStep(Int, Int)
  BackToMenu
  BackToAuthoring
  ArmDelete(Int)
  DisarmDelete(Int)
  Delete(Int)
  Deleted(Result(Nil, wire.Failure))
}

// ---------- boot ----------

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_: Nil) -> #(Model, Effect(Msg)) {
  #(
    Model(
      view: Menu,
      rows: [],
      busy: True,
      flash: None,
      failure: None,
      editing: None,
      name: "",
      show_date: "",
      drawing: draw.empty(),
      play: None,
      armed: None,
      preview: None,
      preview_pending: False,
      preview_stale: False,
      preview_start: False,
      preview_scheduled: PreviewClock(0, None, None),
    ),
    load_rows(),
  )
}

// ---------- effects ----------

fn load_rows() -> Effect(Msg) {
  request("GET", api_puzzles, "", fn(status, text) {
    RowsLoaded(wire.decode_rows(status, text))
  })
}

fn request(
  method: String,
  path: String,
  body: String,
  to_msg: fn(Int, String) -> Msg,
) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    fetch_request(method, path, body, fn(status, text) {
      dispatch(to_msg(status, text))
    })
  })
}

fn render_drawing(drawing: draw.Drawing) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    draw_render(draw.closed_path(drawing), draw.dots(drawing))
    Nil
  })
}

fn sync_board(play: Play) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    play_shape(
      play_board_id,
      play.fixture.centroid,
      play.target,
      term_triples(play.fixture.extras),
    )
    play_terms(play_board_id, term_triples(play.terms), kind_codes(play.kinds))
    Nil
  })
}

/// Paint the authoring panel from a fixture: shape first (the target trace, the
/// fixed extras), then the terms the toggle picked. No request — the fixture is
/// already here.
fn sync_panel(fixture: wire.Fixture, start: Bool) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    play_shape(
      preview_board_id,
      fixture.centroid,
      fixture.target,
      term_triples(fixture.extras),
    )
    play_terms(
      preview_board_id,
      term_triples(panel_terms(fixture, start)),
      kind_codes(fixture.dials),
    )
    Nil
  })
}

/// Come back to the authoring view with a panel to show: the play driver is a
/// singleton, so stop whatever board was running and boot the panel's in one
/// effect (a batch would run in reverse order — stop would land last).
fn restart_panel(fixture: Option(wire.Fixture), start: Bool) -> Effect(Msg) {
  case fixture {
    None -> stop_board()
    Some(fixture) ->
      effect.from(fn(_dispatch) {
        play_stop()
        play_shape(
          preview_board_id,
          fixture.centroid,
          fixture.target,
          term_triples(fixture.extras),
        )
        play_terms(
          preview_board_id,
          term_triples(panel_terms(fixture, start)),
          kind_codes(fixture.dials),
        )
        Nil
      })
  }
}

/// Arm the debounce for a drawing change: cancel the previous timer and, one
/// window later, dispatch the fire that owns this generation. In a test the
/// fire is dispatched by hand — same message, same guard.
fn arm_preview(generation: Int) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    preview_after(preview_debounce_ms, fn() {
      dispatch(PreviewFire(generation))
    })
    Nil
  })
}

/// A draw change: bump the generation, arm the debounce, and paint the dot the
/// tap added. The panel keeps its last fixture until the answer lands.
fn schedule_preview(model: Model, paint: Effect(Msg)) -> #(Model, Effect(Msg)) {
  let generation = model.preview_scheduled.generation + 1
  let clock =
    PreviewClock(generation, Some(generation), model.preview_scheduled.inflight)
  #(
    Model(..model, preview_scheduled: clock),
    effect.batch([arm_preview(generation), paint]),
  )
}

/// A generation nothing may answer any more: supersede the armed timer and the
/// in-flight request (both become stale by construction: `scheduled` and
/// `inflight` are None, so every later fire/answer is discarded).
fn invalidate_preview(clock: PreviewClock) -> PreviewClock {
  PreviewClock(clock.generation + 1, None, None)
}

fn stop_board() -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    play_stop()
    Nil
  })
}

fn term_triples(terms: List(score.Term)) -> List(#(Int, Float, Float)) {
  list.map(terms, fn(term) { #(term.k, term.radius, term.phase_deg) })
}

// The arrangement's ink codes (dial.kind_code), parallel to `term_triples`:
// the canvas inks a row by its KIND, so the kinds cross the boundary with the
// terms.
fn kind_codes(kinds: List(dial.Kind)) -> List(Int) {
  list.map(kinds, dial.kind_code)
}

// ---------- update ----------

/// The whole state machine. Public so the tests can drive it exactly as the
/// runtime does (effects are values; nothing runs until the runtime does).
pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Refresh -> #(Model(..model, busy: True, failure: None), load_rows())

    RowsLoaded(Ok(rows)) -> #(
      Model(..model, rows: rows, busy: False, failure: None),
      effect.none(),
    )

    RowsLoaded(Error(failure)) -> #(
      Model(..model, busy: False, failure: Some(failure)),
      effect.none(),
    )

    StartNew -> {
      let fresh =
        Model(
          ..model,
          view: Authoring,
          editing: None,
          name: "",
          show_date: "",
          drawing: draw.empty(),
          flash: None,
          failure: None,
          play: None,
          armed: None,
          preview: None,
          preview_pending: False,
          preview_stale: False,
          preview_start: False,
          preview_scheduled: invalidate_preview(model.preview_scheduled),
        )
      #(fresh, render_drawing(fresh.drawing))
    }

    StartEdit(id) -> {
      let row = row_of(model.rows, id)
      let editing =
        Model(
          ..model,
          view: Authoring,
          editing: Some(id),
          name: case row {
            Some(row) -> row.name
            None -> ""
          },
          show_date: case row {
            Some(row) -> row.show_date
            None -> ""
          },
          drawing: draw.empty(),
          flash: None,
          failure: None,
          play: None,
          armed: None,
          preview: None,
          preview_pending: False,
          preview_stale: False,
          preview_start: False,
          preview_scheduled: invalidate_preview(model.preview_scheduled),
        )
      #(
        editing,
        effect.batch([
          request(
            "GET",
            api_puzzles <> "/" <> int.to_string(id),
            "",
            fn(status, text) { DotsLoaded(wire.decode_dots(status, text)) },
          ),
          render_drawing(editing.drawing),
        ]),
      )
    }

    StartTest(id) -> #(
      Model(..model, busy: True, failure: None, armed: None),
      request(
        "GET",
        api_puzzles <> "/" <> int.to_string(id),
        "",
        fn(status, text) { TestLoaded(wire.decode_fixture(status, text)) },
      ),
    )

    TestLoaded(Error(failure)) -> #(
      Model(..model, busy: False, failure: Some(failure)),
      effect.none(),
    )

    TestLoaded(Ok(fixture)) -> {
      let play = play_from(fixture)
      #(
        Model(
          ..model,
          view: TestPlay,
          busy: False,
          play: Some(play),
          failure: None,
        ),
        sync_board(play),
      )
    }

    DotsLoaded(Ok(dots)) -> {
      let drawing =
        list.fold(dots, draw.empty(), fn(acc, point) { draw.add(acc, point) })
      let next = Model(..model, drawing: drawing)
      schedule_preview(next, render_drawing(drawing))
    }

    DotsLoaded(Error(failure)) -> #(
      Model(..model, failure: Some(failure)),
      effect.none(),
    )

    DotsTapped(point) -> {
      let drawing = draw.add(model.drawing, point)
      let next = Model(..model, drawing: drawing)
      schedule_preview(next, render_drawing(drawing))
    }

    Undo -> {
      let drawing = draw.undo(model.drawing)
      let next = Model(..model, drawing: drawing)
      schedule_preview(next, render_drawing(drawing))
    }

    Clear -> {
      let drawing = draw.clear(model.drawing)
      let next = Model(..model, drawing: drawing)
      schedule_preview(next, render_drawing(drawing))
    }

    NameChanged(name) -> #(Model(..model, name: name), effect.none())

    ShowDateChanged(date) -> #(Model(..model, show_date: date), effect.none())

    Save -> {
      let body =
        wire.puzzle_body(model.name, model.show_date, draw.dots(model.drawing))
      let path = case model.editing {
        Some(id) -> api_puzzles <> "/" <> int.to_string(id)
        None -> api_puzzles
      }
      let method = case model.editing {
        Some(_) -> "PUT"
        None -> "POST"
      }
      #(
        Model(..model, busy: True, failure: None, flash: None),
        request(method, path, body, fn(status, text) {
          Saved(wire.decode_nothing(status, text))
        }),
      )
    }

    Saved(Ok(_)) -> {
      // a save lands back on the menu with the calendar refreshed — the new
      // puzzle's stats row is the proof it stuck
      let done =
        Model(
          ..model,
          view: Menu,
          busy: True,
          editing: None,
          name: "",
          show_date: "",
          drawing: draw.empty(),
          play: None,
          flash: Some("saved"),
          failure: None,
          preview: None,
          preview_pending: False,
          preview_stale: False,
          preview_start: False,
          preview_scheduled: invalidate_preview(model.preview_scheduled),
        )
      #(done, load_rows())
    }

    Saved(Error(failure)) -> #(
      Model(..model, busy: False, failure: Some(failure), flash: None),
      effect.none(),
    )

    Preview -> {
      let body =
        wire.preview_body(model.name, model.show_date, draw.dots(model.drawing))
      #(
        Model(
          ..model,
          busy: True,
          failure: None,
          flash: None,
          // the full board's preview is its own flow: the panel's armed
          // timer and any in-flight panel request must not follow it
          preview_pending: False,
          preview_scheduled: invalidate_preview(model.preview_scheduled),
        ),
        request("POST", preview_path, body, fn(status, text) {
          Previewed(wire.decode_fixture(status, text))
        }),
      )
    }

    Previewed(Ok(fixture)) -> {
      let play = play_from(fixture)
      #(
        Model(
          ..model,
          view: TestPlay,
          busy: False,
          play: Some(play),
          failure: None,
        ),
        sync_board(play),
      )
    }

    Previewed(Error(failure)) -> #(
      Model(..model, busy: False, failure: Some(failure)),
      effect.none(),
    )

    PreviewFire(generation) -> {
      case model.view, model.preview_scheduled.scheduled {
        Authoring, Some(scheduled) if scheduled == generation -> {
          let body =
            wire.preview_body(
              model.name,
              model.show_date,
              draw.dots(model.drawing),
            )
          let clock = PreviewClock(generation, None, Some(generation))
          #(
            Model(
              ..model,
              preview_pending: True,
              preview_scheduled: clock,
              failure: None,
            ),
            request("POST", preview_path, body, fn(status, text) {
              PanelPreviewed(generation, wire.decode_fixture(status, text))
            }),
          )
        }
        _, _ -> #(model, effect.none())
      }
    }

    PanelPreviewed(generation, Ok(fixture)) -> {
      case model.view, model.preview_scheduled.inflight {
        Authoring, Some(inflight) if inflight == generation -> {
          // The answer owns only the inflight slot: the ARMED timer (a newer
          // tap since the fire went out) must survive, or that fire dies and
          // the panel stops updating.
          let clock =
            PreviewClock(
              model.preview_scheduled.generation,
              model.preview_scheduled.scheduled,
              None,
            )
          #(
            Model(
              ..model,
              preview: Some(fixture),
              preview_pending: False,
              preview_stale: False,
              preview_scheduled: clock,
            ),
            sync_panel(fixture, model.preview_start),
          )
        }
        _, _ -> #(model, effect.none())
      }
    }

    PanelPreviewed(generation, Error(_)) -> {
      case model.view, model.preview_scheduled.inflight {
        Authoring, Some(inflight) if inflight == generation -> {
          // same rule as the Ok branch: only the inflight slot is the
          // answer's to clear
          let clock =
            PreviewClock(
              model.preview_scheduled.generation,
              model.preview_scheduled.scheduled,
              None,
            )
          #(
            Model(
              ..model,
              preview_pending: False,
              preview_stale: True,
              preview_scheduled: clock,
            ),
            // the panel keeps the last fixture it drew; only the hint moves
            effect.none(),
          )
        }
        _, _ -> #(model, effect.none())
      }
    }

    StartView -> set_panel_view(model, True)

    TruthView -> set_panel_view(model, False)

    DialStep(slot, dir) -> {
      case model.play {
        None -> #(model, effect.none())
        Some(play) -> {
          let kind = kind_at(play.kinds, slot)
          let max_r = dial.max_radius(play.fixture.dial)
          let terms =
            list.index_map(play.terms, fn(term, index) {
              case index == slot {
                True -> dial.step(kind, term, dir, max_r)
                False -> term
              }
            })
          let match =
            score.synthesis_match(
              play.fixture.centroid,
              terms,
              play.fixture.extras,
              play.target,
              play.normalizer,
            )
          let #(moves, solved_once) = case play.solved_once {
            True -> #(play.moves, True)
            False -> #(play.moves + 1, score.solved(match))
          }
          let stepped =
            Play(
              ..play,
              terms: terms,
              match: match,
              moves: moves,
              solved_once: solved_once,
            )
          #(
            Model(..model, play: Some(stepped)),
            effect.from(fn(_dispatch) {
              play_terms(
                play_board_id,
                term_triples(terms),
                kind_codes(play.kinds),
              )
              Nil
            }),
          )
        }
      }
    }

    BackToMenu -> {
      let menu =
        Model(
          ..model,
          view: Menu,
          play: None,
          busy: True,
          flash: None,
          failure: None,
          armed: None,
          preview_pending: False,
          preview_scheduled: invalidate_preview(model.preview_scheduled),
        )
      #(menu, effect.batch([stop_board(), load_rows()]))
    }

    BackToAuthoring -> {
      let back = Model(..model, view: Authoring, play: None, armed: None)
      #(
        back,
        effect.batch([
          restart_panel(back.preview, back.preview_start),
          render_drawing(back.drawing),
        ]),
      )
    }

    ArmDelete(id) -> {
      let armed = Model(..model, armed: Some(id))
      let timed =
        effect.from(fn(dispatch) {
          after(arm_ms, fn() { dispatch(DisarmDelete(id)) })
          Nil
        })
      #(armed, timed)
    }

    DisarmDelete(id) ->
      case model.armed {
        Some(armed_id) if armed_id == id -> #(
          Model(..model, armed: None),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }

    Delete(id) -> #(
      Model(..model, armed: None, busy: True, failure: None),
      request(
        "DELETE",
        api_puzzles <> "/" <> int.to_string(id),
        "",
        fn(status, text) { Deleted(wire.decode_nothing(status, text)) },
      ),
    )

    Deleted(Ok(_)) -> #(Model(..model, flash: Some("deleted")), load_rows())

    Deleted(Error(failure)) -> #(
      Model(..model, busy: False, failure: Some(failure)),
      effect.none(),
    )
  }
}

/// Start a test play from a fixture: the fixture's OWN starting perturbation
/// (derived with it, §1), applied to whatever arrangement it declares. A fixture
/// stored before the patches field has none — it falls back to the editor's old
/// standard row, so an old row still test-plays.
pub fn play_from(fixture: wire.Fixture) -> Play {
  let kinds = fixture.dials
  let terms = fixture_start(fixture)
  let normalizer =
    score.rms_polar(fixture.target, fixture.centroid.0, fixture.centroid.1)
  Play(
    fixture: fixture,
    kinds: kinds,
    terms: terms,
    target: fixture.target,
    normalizer: normalizer,
    match: score.synthesis_match(
      fixture.centroid,
      terms,
      fixture.extras,
      fixture.target,
      normalizer,
    ),
    moves: 0,
    solved_once: False,
  )
}

fn row_of(rows: List(wire.Row), id: Int) -> Option(wire.Row) {
  list.find(rows, fn(row) { row.id == id })
  |> option_from_result
}

/// The panel's two readings of the same fixture: the dial truth (what the
/// puzzle is) or the player's start (the fixture's patches applied). Both come
/// from data already in hand — switching views never asks the server again.
pub fn panel_terms(fixture: wire.Fixture, start: Bool) -> List(score.Term) {
  case start {
    False -> fixture.dial
    True -> fixture_start(fixture)
  }
}

/// The fixture's OWN starting perturbation, applied to its dial truth — the
/// same list `play_from` boots the full board with.
fn fixture_start(fixture: wire.Fixture) -> List(score.Term) {
  let patches = case fixture.patches {
    [] -> dial.standard_patches()
    own -> own
  }
  dial.initial(fixture.dial, fixture.dials, patches)
}

/// The panel's toggle: flip which reading the board and the rows show. A
/// repaint, never a request.
fn set_panel_view(model: Model, start: Bool) -> #(Model, Effect(Msg)) {
  let next = Model(..model, preview_start: start)
  case model.preview {
    None -> #(next, effect.none())
    Some(fixture) -> #(next, sync_panel(fixture, start))
  }
}

fn option_from_result(result: Result(a, Nil)) -> Option(a) {
  case result {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn kind_at(kinds: List(dial.Kind), slot: Int) -> dial.Kind {
  case list.drop(kinds, slot) {
    [kind, ..] -> kind
    [] -> dial.KindFixed
  }
}

// ---------- view ----------

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("app")], [
    header(model),
    case model.view {
      Menu -> menu_view(model)
      Authoring -> authoring_view(model)
      TestPlay -> test_play_view(model)
    },
  ])
}

fn header(model: Model) -> Element(Msg) {
  html.header([attribute.class("head")], [
    html.h1([], [html.text("toy admin")]),
    html.span([attribute.class("sub")], [
      html.text(case model.view {
        Menu -> "the calendar"
        Authoring ->
          case model.editing {
            Some(_) -> "editing a puzzle"
            None -> "a new puzzle"
          }
        TestPlay -> "test play"
      }),
    ]),
  ])
}

fn flash_line(model: Model) -> Element(Msg) {
  case model.flash {
    Some(text) -> html.p([attribute.class("flash")], [html.text(text)])
    None -> html.p([attribute.class("flash hidden")], [])
  }
}

fn failure_line(model: Model) -> Element(Msg) {
  case model.failure {
    Some(failure) ->
      html.p([attribute.class("error")], [html.text(wire.failure_text(failure))])
    None -> html.p([attribute.class("error hidden")], [])
  }
}

// ---- menu ----

fn menu_view(model: Model) -> Element(Msg) {
  html.section([attribute.class("menu")], [
    flash_line(model),
    failure_line(model),
    html.div([attribute.class("tools")], [
      html.button([attribute.class("btn primary"), event.on_click(StartNew)], [
        html.text("new puzzle"),
      ]),
      html.button(
        [
          attribute.class("btn"),
          attribute.disabled(model.busy),
          event.on_click(Refresh),
        ],
        [
          html.text(case model.busy {
            True -> "loading…"
            False -> "refresh"
          }),
        ],
      ),
    ]),
    case model.rows {
      [] ->
        case model.busy {
          True ->
            html.p([attribute.class("empty")], [
              html.text("loading the calendar…"),
            ])
          False ->
            html.p([attribute.class("empty")], [
              html.text("no puzzles yet — draw one"),
            ])
        }
      rows -> row_table(rows, model.armed)
    },
  ])
}

fn row_table(rows: List(wire.Row), armed: Option(Int)) -> Element(Msg) {
  html.table([attribute.class("rows")], [
    html.thead([], [
      html.tr([], [
        head_cell("name"),
        head_cell("show date"),
        head_cell("attempts"),
        head_cell("solves"),
        head_cell("solve %"),
        head_cell("median moves"),
        head_cell(""),
      ]),
    ]),
    html.tbody([], list.map(rows, fn(row) { row_line(row, armed) })),
  ])
}

fn head_cell(text: String) -> Element(Msg) {
  html.th([], [html.text(text)])
}

fn row_line(row: wire.Row, armed: Option(Int)) -> Element(Msg) {
  let is_armed = case armed {
    Some(id) -> id == row.id
    None -> False
  }
  html.tr([], [
    html.td([attribute.class("name")], [html.text(row.name)]),
    html.td([], [html.text(row.show_date)]),
    html.td([attribute.class("num")], [html.text(int.to_string(row.attempts))]),
    html.td([attribute.class("num")], [html.text(int.to_string(row.solves))]),
    html.td([attribute.class("num")], [
      html.text(optional_text(row.solve_pct, "—")),
    ]),
    html.td([attribute.class("num")], [
      html.text(optional_number(row.median_moves)),
    ]),
    html.td([attribute.class("acts")], [
      html.button(
        [attribute.class("btn small"), event.on_click(StartTest(row.id))],
        [html.text("test")],
      ),
      html.button(
        [attribute.class("btn small"), event.on_click(StartEdit(row.id))],
        [html.text("edit")],
      ),
      html.button(
        [
          attribute.classes([
            #("btn", True),
            #("small", True),
            #("danger", True),
          ]),
          event.on_click(case is_armed {
            True -> Delete(row.id)
            False -> ArmDelete(row.id)
          }),
        ],
        [
          html.text(case is_armed {
            True -> "sure?"
            False -> "delete"
          }),
        ],
      ),
    ]),
  ])
}

fn optional_text(value: Option(String), fallback: String) -> String {
  case value {
    Some(text) -> text
    None -> fallback
  }
}

fn optional_number(value: Option(Float)) -> String {
  case value {
    Some(number) -> dial.fmt1(number)
    None -> "—"
  }
}

// ---- authoring ----

fn authoring_view(model: Model) -> Element(Msg) {
  html.section([attribute.class("authoring")], [
    flash_line(model),
    failure_line(model),
    html.div([attribute.class("studio")], [
      draw_panel(model),
      preview_panel(model),
    ]),
    html.div([attribute.class("panel form")], [
      field_label("name", name_problem(model.failure)),
      html.input([
        attribute.class("input"),
        attribute.type_("text"),
        attribute.value(model.name),
        attribute.placeholder("the star"),
        event.on_input(NameChanged),
      ]),
      field_label("show date", date_problem(model.failure)),
      html.input([
        attribute.class("input"),
        attribute.type_("date"),
        attribute.value(model.show_date),
        event.on_input(ShowDateChanged),
      ]),
      html.div([attribute.class("tools")], [
        html.button(
          [
            attribute.class("btn primary"),
            attribute.disabled(!draw.can_submit(model.drawing) || model.busy),
            event.on_click(Save),
          ],
          [
            html.text(case model.editing {
              Some(_) -> "save changes"
              None -> "save puzzle"
            }),
          ],
        ),
        html.button([attribute.class("btn"), event.on_click(BackToMenu)], [
          html.text("back"),
        ]),
      ]),
      html.p([attribute.class("hint")], [
        html.text(
          "the panel and the full board both show the drawing as it is — "
          <> "nothing is saved until you save it",
        ),
      ]),
    ]),
  ])
}

fn draw_panel(model: Model) -> Element(Msg) {
  html.div([attribute.class("panel draw")], [
    html.canvas([
      attribute.class("board"),
      attribute.id("draw-canvas"),
      event.on("pointerdown", tap_decoder()),
    ]),
    html.p([attribute.class("hint")], [
      html.text(
        int.to_string(draw.count(model.drawing))
        <> " dots — tap to add, three at least, the outline closes itself",
      ),
    ]),
    html.div([attribute.class("tools")], [
      html.button(
        [
          attribute.class("btn"),
          attribute.disabled(!draw.can_undo(model.drawing)),
          event.on_click(Undo),
        ],
        [html.text("undo")],
      ),
      html.button(
        [
          attribute.class("btn"),
          attribute.disabled(draw.count(model.drawing) == 0),
          event.on_click(Clear),
        ],
        [html.text("clear")],
      ),
    ]),
  ])
}

/// The live panel: the toy's own board for the LAST previewed fixture, the
/// dials read-only (no steppers — this is a look, not a play), and the toggle
/// between the puzzle's truth and the player's start. It never blanks: a
/// refused preview keeps the last fixture drawn and says so underneath.
fn preview_panel(model: Model) -> Element(Msg) {
  html.div([attribute.class("panel preview")], [
    html.canvas([
      attribute.class("board"),
      attribute.id(preview_board_id),
    ]),
    html.div([attribute.class("toggle")], [
      toggle_button("solved view", !model.preview_start, TruthView),
      toggle_button("player start", model.preview_start, StartView),
    ]),
    case model.preview {
      None ->
        html.p([attribute.class("hint")], [
          html.text("the toy's board, previewed — draw to begin"),
        ])
      Some(fixture) -> preview_dial_rows(fixture, model.preview_start)
    },
    html.p(
      [
        attribute.classes([
          #("preview-stale", True),
          #("hidden", !model.preview_stale),
        ]),
      ],
      [html.text("preview stale")],
    ),
    html.div([attribute.class("tools")], [
      html.button(
        [
          attribute.class("btn small link"),
          attribute.disabled(!draw.can_submit(model.drawing) || model.busy),
          event.on_click(Preview),
        ],
        [html.text("open full board")],
      ),
    ]),
  ])
}

fn toggle_button(label: String, on: Bool, msg: Msg) -> Element(Msg) {
  html.button(
    [
      attribute.classes([#("btn", True), #("on", on)]),
      event.on_click(msg),
    ],
    [html.text(label)],
  )
}

/// The panel's rows: same words and numbers as the full board's steppers, with
/// the steppers left out. Non-dial slots are skipped by KIND (the arrangement
/// is data), exactly as the derived list skips them.
pub fn preview_dial_rows(fixture: wire.Fixture, start: Bool) -> Element(Msg) {
  let terms = panel_terms(fixture, start)
  let max_r = dial.max_radius(fixture.dial)
  let rows =
    list.index_map(fixture.dials, fn(kind, slot) {
      #(kind, slot, list.drop(terms, slot))
    })
    |> list.filter_map(fn(entry) {
      let #(kind, slot, rest) = entry
      case kind, rest {
        dial.KindFixed, _ -> Error(Nil)
        _, [term, ..] -> Ok(dial_row(kind, slot, term, max_r, ReadOnly))
        _, [] -> Error(Nil)
      }
    })
  html.div([attribute.class("preview-dials")], rows)
}

/// The red underline under a field the server complained about.
fn name_problem(failure: Option(wire.Failure)) -> Bool {
  case failure {
    Some(failure) -> wire.name_problem(failure)
    None -> False
  }
}

fn date_problem(failure: Option(wire.Failure)) -> Bool {
  case failure {
    Some(failure) -> wire.date_problem(failure)
    None -> False
  }
}

fn field_label(text: String, problem: Bool) -> Element(Msg) {
  html.label([attribute.classes([#("label", True), #("bad", problem)])], [
    html.text(text),
  ])
}

/// A tap on the panel becomes a dot. The mapping (pixels -> 0..100, letterbox
/// aware) is FFI; the tap that lands outside the square is dropped.
fn tap_decoder() -> decode.Decoder(Msg) {
  decode.then(decode.dynamic, fn(event) {
    case event_point(event) {
      #(x, y, True) -> decode.success(DotsTapped(#(x, y)))
      _ -> decode.failure(DotsTapped(#(0.0, 0.0)), "a point on the panel")
    }
  })
}

// ---- test play ----

fn test_play_view(model: Model) -> Element(Msg) {
  case model.play {
    None -> html.section([], [failure_line(model)])
    Some(play) -> {
      html.section([attribute.class("play")], [
        failure_line(model),
        play_bar(play),
        html.div([attribute.class("panels")], [
          html.canvas([
            attribute.class("board"),
            attribute.id("play-board"),
          ]),
          html.div([attribute.class("panel dials")], dial_rows(play)),
        ]),
        derived_list(play.fixture),
        html.div([attribute.class("tools")], [
          html.button(
            [attribute.class("btn"), event.on_click(BackToAuthoring)],
            [html.text("back to the drawing")],
          ),
          html.button([attribute.class("btn"), event.on_click(BackToMenu)], [
            html.text("the calendar"),
          ]),
        ]),
      ])
    }
  }
}

fn play_bar(play: Play) -> Element(Msg) {
  html.div([attribute.class("bar")], [
    html.span(
      [
        attribute.classes([
          #("score", True),
          #("solved", score.solved(play.match)),
        ]),
      ],
      [
        html.text("Match "),
        html.b([], [html.text(dial.fmt1(play.match) <> "%")]),
        html.span([attribute.class("mv")], [
          html.text(" · " <> changes_text(play.moves)),
        ]),
        html.span([attribute.class("ok")], [html.text("solved ✓")]),
        html.span([attribute.class("mv")], [
          html.text(
            " · "
            <> case play.fixture.show_date {
              "" -> "no date yet"
              date -> date
            },
          ),
        ]),
      ],
    ),
  ])
}

/// The derived truths, before anything is saved (plan Q2/Q3): the numbers the
/// derivation decided, one bullet per MOVABLE slot, in the same words as the
/// steppers that can undo them (dial.slot_label / dial.truth_value).
///
/// The list is filtered by KIND, not position (Q19: the arrangement is data):
/// a slot whose kind is `fixed` is correct by construction and has no dial, so
/// listing it would be telling the player about a term they cannot touch. Slot
/// numbers stay the arrangement's, so a reordered fixture still names the right
/// term.
pub fn truth_entries(fixture: wire.Fixture) -> List(String) {
  let max_r = dial.max_radius(fixture.dial)
  list.index_map(fixture.dials, fn(kind, slot) {
    #(kind, slot, list.drop(fixture.dial, slot))
  })
  |> list.filter_map(fn(entry) {
    let #(kind, slot, truth) = entry
    case kind, truth {
      dial.KindFixed, _ -> Error(Nil)
      _, [] -> Error(Nil)
      _, [term, ..] ->
        Ok(
          "term "
          <> int.to_string(slot + 1)
          <> " · "
          <> dial.slot_label(kind)
          <> " — set "
          <> dial.truth_value(kind, term, max_r),
        )
    }
  })
}

fn derived_list(fixture: wire.Fixture) -> Element(Msg) {
  html.div([attribute.class("derived")], [
    html.span([attribute.class("label")], [html.text("derived")]),
    html.ul(
      [],
      list.map(truth_entries(fixture), fn(entry) {
        html.li([], [html.text(entry)])
      }),
    ),
  ])
}

fn dial_rows(play: Play) -> List(Element(Msg)) {
  let max_r = dial.max_radius(play.fixture.dial)
  list.index_map(play.kinds, fn(kind, slot) {
    let assert [term, ..] = list.drop(play.terms, slot)
    dial_row(kind, slot, term, max_r, Interactive)
  })
}

/// How a row is drawn: the full board's rows are the player's (steppers on
/// either side of the value), the panel's are a reading of the same numbers.
/// One renderer, so the two can never word a slot differently.
type DialRowMode {
  Interactive
  ReadOnly
}

fn dial_row(
  kind: dial.Kind,
  slot: Int,
  term: score.Term,
  max_r: Float,
  mode: DialRowMode,
) -> Element(Msg) {
  let head = [
    html.div([attribute.class("id")], [
      html.span([attribute.class("term")], [
        html.text("term " <> int.to_string(slot + 1)),
      ]),
      html.span([attribute.class("sub")], [
        html.text(dial.locked_note(kind, term, max_r)),
      ]),
    ]),
  ]
  let value =
    html.div([attribute.class("val")], [
      html.text(dial.slot_value(kind, term, max_r)),
    ])
  let body = case mode {
    ReadOnly -> [value]
    Interactive ->
      case kind {
        dial.KindFixed -> [
          html.div([attribute.class("val")], [html.text("not a dial")]),
        ]
        _ -> [
          edge_button(slot, -1, at_min(kind, term, max_r)),
          value,
          edge_button(slot, 1, at_max(kind, term, max_r)),
        ]
      }
  }
  html.div(
    [
      attribute.classes([
        #("row", True),
        #("read-only", mode == ReadOnly),
      ]),
    ],
    list.append(head, body),
  )
}

fn at_min(kind: dial.Kind, term: score.Term, _max_r: Float) -> Bool {
  case kind {
    dial.KindK -> term.k <= dial.k_min
    dial.KindRadius -> term.radius <=. 0.0
    _ -> False
  }
}

fn at_max(kind: dial.Kind, term: score.Term, max_r: Float) -> Bool {
  case kind {
    dial.KindK -> term.k >= dial.k_max
    dial.KindRadius -> term.radius >=. 2.0 *. max_r
    _ -> False
  }
}

fn edge_button(slot: Int, dir: Int, disabled_flag: Bool) -> Element(Msg) {
  html.button(
    [
      attribute.class("btn"),
      attribute.disabled(disabled_flag),
      event.on_click(DialStep(slot, dir)),
    ],
    [
      html.text(case dir > 0 {
        True -> "+"
        False -> "−"
      }),
    ],
  )
}

fn changes_text(n: Int) -> String {
  case n {
    0 -> "no changes yet"
    1 -> "1 change"
    _ -> int.to_string(n) <> " changes"
  }
}
