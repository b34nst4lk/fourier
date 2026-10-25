//// The admin API (PLAN-daily-puzzles.md §2 Q12/Q17/Q23, phase 4a) — the
//// editor's backend: fence, CRUD, per-puzzle stats.
////
////   GET    /api/admin                 the admin UI itself (phase 4b, Q18)
////   GET    /api/admin/                the same page (a browser's trailing slash)
////   POST   /api/admin/preview         derive a fixture, save nothing (4b, Q4)
////   GET    /api/admin/puzzles        list, newest show_date first, with stats
////   POST   /api/admin/puzzles        create {name, showDate, dots}
////   GET    /api/admin/puzzles/<id>   one puzzle, full row (dots + fixture)
////   PUT    /api/admin/puzzles/<id>   partial update {name?, showDate?, dots?}
////   DELETE /api/admin/puzzles/<id>   204; telemetry rows survive
////
//// Order of operations on EVERY route here, without exception:
////
////   1. the access fence (access.check) — no method sniffing, no body read, no
////      store access before it passes. An unfenced caller learns nothing, not
////      even which methods a path takes;
////   2. the path id, if any (`/api/admin/puzzles/<id>`) — a non-numeric id is
////      404 UnknownPuzzle whatever the method;
////   3. the method (405 with an accurate `allow` header);
////   4. body read + decode (400 BadRequest for a body that is not JSON);
////   5. field validation, collecting ALL problems into one envelope (a body
////      with a blank name AND a bad date reports both, so the editor can
////      underline both fields in one round trip);
////   6. derivation (create, and dots-changing updates);
////   7. the store.
////
//// Derivation is the route layer's job, not the store's (store.update_puzzle's
//// header): a puzzle's fixture is ALWAYS the derivation of its dots, name and
//// show_date. So a dots change re-derives (Q2/Q3), and a name/show_date change
//// rewrites the fixture's embedded copy — without re-running the DFT, since the
//// numbers do not depend on the labels.
////
//// Stats policy (Q23), in stats.gleam's words: attempts = every attempt row
//// (solves + abandons), solves = solved rows, solvePct = one decimal or null,
//// medianMoves = the median of ALL attempts' move_count (an abandon counts with
//// its own reported count) or null.
////
//// The list route reads stats per puzzle (one COUNT query + one move_count query
//// each). That is N+1 by design: the calendar is hundreds of rows at most, the
//// store stays a set of small composable primitives, and the arithmetic lives in
//// a pure module with its own tests. If the calendar ever grows to thousands,
//// this is the one place to fold into a single GROUP BY.
////
//// DELETE deliberately keeps the puzzle's attempt rows: there is no foreign key
//// and no cascade (store.gleam). Deleting a puzzle from the calendar must not
//// rewrite history — "we had 40 attempts on that puzzle" stays true.

import gleam/dynamic
import gleam/dynamic/decode
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import sketch.{type Dot}
import toy_admin/access
import toy_admin/admin_ui
import toy_admin/clock
import toy_admin/dates
import toy_admin/derivation
import toy_admin/envelope
import toy_admin/fixture_json
import toy_admin/stats
import toy_admin/store
import wisp

// ---------- the two routed shapes ----------

/// `/api/admin/puzzles` — the collection.
pub fn puzzles(request: wisp.Request) -> wisp.Response {
  fenced(request, fn() {
    case request.method {
      http.Get -> list_puzzles()
      http.Post -> create_puzzle(request)
      _ -> wisp.method_not_allowed([http.Get, http.Post])
    }
  })
}

/// `/api/admin/puzzles/<id>` — one row.
pub fn puzzle(request: wisp.Request, id_text: String) -> wisp.Response {
  fenced(request, fn() {
    case parse_id(id_text) {
      Error(_) -> envelope.error_response(404, ["UnknownPuzzle"])
      Ok(id) ->
        case request.method {
          http.Get -> read_puzzle(id)
          http.Put -> update_puzzle(request, id)
          http.Delete -> delete_puzzle(id)
          _ -> wisp.method_not_allowed([http.Get, http.Put, http.Delete])
        }
    }
  })
}

/// The fence, in one place so no route can forget it (access.gleam).
fn fenced(request: wisp.Request, next: fn() -> wisp.Response) -> wisp.Response {
  case
    access.check(request, clock.now_seconds(), access.configured_audience())
  {
    Ok(Nil) -> next()
    Error(failure) ->
      envelope.error_response(access.status_of(failure), [
        access.error_name(failure),
      ])
  }
}

fn parse_id(text: String) -> Result(Int, Nil) {
  case int.parse(text) {
    Ok(id) if id > 0 -> Ok(id)
    _ -> Error(Nil)
  }
}

// ---------- GET /api/admin — the embedded UI ----------

/// The admin page (Q18). Behind the same fence as the API it drives, and
/// method-gated the same way: the fence first, so an unfenced caller learns
/// nothing, then the method, then the bytes the boot read cached.
pub fn ui(request: wisp.Request, bundle: Option(String)) -> wisp.Response {
  fenced(request, fn() {
    case request.method {
      http.Get -> admin_ui.page(bundle)
      _ -> wisp.method_not_allowed([http.Get])
    }
  })
}

// ---------- POST /api/admin/preview ----------

/// Derive a fixture from an UNSAVED drawing (Q4: "test the current drawing
/// before saving"). The editor's whole point is that the fixture arrives in one
/// round trip: the client does no maths, so what the admin previews and what the
/// toy later serves are the same numbers from the same derivation.
///
/// This route WRITES NOTHING, and that is the contract, not an accident: no
/// store call, no duplicate-date check, no id. It is therefore also the only
/// admin write-shaped route that cannot fail with 409 — a preview over a taken
/// date answers 200 with the fixture. What it derives is exactly what a create
/// with the same body would store (asserted in admin_api_test).
pub fn preview(request: wisp.Request) -> wisp.Response {
  fenced(request, fn() {
    case request.method {
      http.Post -> derive_preview(request)
      _ -> wisp.method_not_allowed([http.Post])
    }
  })
}

fn derive_preview(request: wisp.Request) -> wisp.Response {
  wisp.require_string_body(request, fn(body) {
    case parse_draft(body) {
      Error(_) -> envelope.error_response(400, ["BadRequest"])
      Ok(draft) ->
        case validated_preview(draft) {
          Error(problems) -> envelope.error_response(400, problems)
          Ok(#(name, show_date, dots)) -> {
            let fixture = derivation.derive_fixture(dots, name, show_date)
            case derivation.is_degenerate(fixture) {
              True -> envelope.error_response(400, ["BadDrawing"])
              False ->
                envelope.ok_with([
                  #("fixture", fixture_json.fixture_to_json(fixture)),
                ])
            }
          }
        }
    }
  })
}

/// The preview body's rules: the create body's, minus the requirement that the
/// name and the date be there. A preview happens while the admin is still
/// drawing, so neither may be mandatory; the fixture's labels are best-effort.
///
///   - a blank (or absent) name borrows the date it is previewed for, and falls
///     back to `"preview"` when no date is set yet — the name is what the toy
///     shows in its menu, and "preview" is the honest word for "not saved";
///   - an absent date previews as the empty string ("not picked yet"), but a
///     date that IS there and is impossible is a typo and fails like create
///     (BadPuzzleDate) — silently previewing under a date the save would reject
///     would be a lie about the round trip;
///   - the drawing must still derive to a non-degenerate fixture (BadDrawing),
///     because there is nothing to test-play otherwise.
///
/// All problems are collected into one envelope, in field order, exactly as on
/// create.
fn validated_preview(
  draft: Draft,
) -> Result(#(String, String, List(Dot)), List(String)) {
  let show_date = case draft.show_date {
    None -> Ok("")
    Some(value) -> validated_date(value)
  }
  let dots = validated_dots(draft.dots)
  case show_date, dots {
    Ok(show_date), Ok(dots) -> {
      let trimmed = case draft.name {
        None -> ""
        Some(value) -> string.trim(value)
      }
      let name = case trimmed, show_date {
        "", "" -> "preview"
        "", show_date -> show_date
        name, _ -> name
      }
      Ok(#(name, show_date, dots))
    }
    _, _ -> Error(list.append(problem_list(show_date), problem_list(dots)))
  }
}

// ---------- GET /api/admin/puzzles ----------

fn list_puzzles() -> wisp.Response {
  let path = store.path_from_env()
  case store.list_puzzles(path) {
    Error(_) -> envelope.error_response(500, ["StoreError"])
    Ok(puzzles) ->
      case
        puzzles
        |> list.map(fn(puzzle) { summarize(path, puzzle) })
        |> result.all
      {
        Error(_) -> envelope.error_response(500, ["StoreError"])
        Ok(rows) ->
          envelope.ok_with([
            #("puzzles", json.array(rows, of: fn(document) { document })),
          ])
      }
  }
}

/// One menu row: identity, schedule, and the Q23 numbers.
fn summarize(path: String, puzzle: store.Puzzle) -> Result(json.Json, Nil) {
  use #(attempts, solves) <- result.try(
    store.stats(path, puzzle.id)
    |> result.map_error(fn(_) { Nil }),
  )
  use counts <- result.try(
    store.move_counts(path, puzzle.id)
    |> result.map_error(fn(_) { Nil }),
  )
  let summary =
    stats.summarize(attempts: attempts, solves: solves, counts: counts)

  Ok(
    json.object([
      #("id", json.int(puzzle.id)),
      #("name", json.string(puzzle.name)),
      #("showDate", json.string(puzzle.show_date)),
      #("attempts", json.int(summary.attempts)),
      #("solves", json.int(summary.solves)),
      #("solvePct", optional_string(summary.solve_pct)),
      #("medianMoves", optional_float(summary.median_moves)),
    ]),
  )
}

fn optional_string(value: Option(String)) -> json.Json {
  case value {
    Some(text) -> json.string(text)
    None -> json.null()
  }
}

fn optional_float(value: Option(Float)) -> json.Json {
  case value {
    Some(number) -> json.float(number)
    None -> json.null()
  }
}

// ---------- POST /api/admin/puzzles ----------

fn create_puzzle(request: wisp.Request) -> wisp.Response {
  wisp.require_string_body(request, fn(body) {
    case parse_draft(body) {
      Error(_) -> envelope.error_response(400, ["BadRequest"])
      Ok(draft) ->
        case validated_new(draft) {
          Error(problems) -> envelope.error_response(400, problems)
          Ok(new_puzzle) -> save_new_puzzle(new_puzzle)
        }
    }
  })
}

/// Derive, then insert. Named apart from `store.insert_puzzle` on purpose: the
/// derivation is this layer's step, and the two must not be confused.
fn save_new_puzzle(new_puzzle: NewPuzzle) -> wisp.Response {
  let NewPuzzle(name, show_date, dots) = new_puzzle
  let fixture = derivation.derive_fixture(dots, name, show_date)
  case derivation.is_degenerate(fixture) {
    True ->
      // Fewer than three dots: nothing renderable can come out. The fixture is
      // the observable, so the check is on it rather than a second dot count.
      envelope.error_response(400, ["BadDrawing"])
    False ->
      case
        store.insert_puzzle(
          store.path_from_env(),
          name,
          show_date,
          fixture_json.dots_to_string(dots),
          fixture_json.to_string(fixture),
        )
      {
        Ok(row) -> respond_row(201, row)
        Error(store.DuplicateShowDate(_)) ->
          envelope.error_response(409, ["DuplicateShowDate"])
        // Unreachable: the date was validated above. Say the client-side thing
        // anyway rather than inventing a 500 for a bad input.
        Error(store.InvalidShowDate(_)) ->
          envelope.error_response(400, ["BadPuzzleDate"])
        Error(_) -> envelope.error_response(500, ["StoreError"])
      }
  }
}

// ---------- GET /api/admin/puzzles/<id> ----------

fn read_puzzle(id: Int) -> wisp.Response {
  case store.puzzle_by_id(store.path_from_env(), id) {
    Error(_) -> envelope.error_response(500, ["StoreError"])
    Ok(None) -> envelope.error_response(404, ["UnknownPuzzle"])
    Ok(Some(row)) -> respond_row(200, row)
  }
}

// ---------- PUT /api/admin/puzzles/<id> ----------

fn update_puzzle(request: wisp.Request, id: Int) -> wisp.Response {
  wisp.require_string_body(request, fn(body) {
    case parse_draft(body) {
      Error(_) -> envelope.error_response(400, ["BadRequest"])
      Ok(draft) ->
        case validated_patch(draft) {
          Error(problems) -> envelope.error_response(400, problems)
          Ok(patch) -> apply_patch(id, patch)
        }
    }
  })
}

fn apply_patch(id: Int, patch: Patch) -> wisp.Response {
  let path = store.path_from_env()
  case store.puzzle_by_id(path, id) {
    Error(_) -> envelope.error_response(500, ["StoreError"])
    Ok(None) -> envelope.error_response(404, ["UnknownPuzzle"])
    Ok(Some(existing)) ->
      case fixture_for_update(existing, patch) {
        Error(BadDrawing) -> envelope.error_response(400, ["BadDrawing"])
        Error(StoreFault) -> envelope.error_response(500, ["StoreError"])
        Ok(#(fixture, dots_json)) -> {
          let name = option.unwrap(patch.name, existing.name)
          let show_date = option.unwrap(patch.show_date, existing.show_date)
          // A field that was mentioned but says what the row already says is
          // not an edit: an editor PUTs the whole form it just loaded, and
          // "saved" must not claim a change that did not happen.
          let changes =
            store.PuzzleUpdate(
              name: changed(name, existing.name),
              show_date: changed(show_date, existing.show_date),
              dots_json: dots_json,
              fixture_json: case fixture {
                // Nothing that the fixture embeds changed: leave the column
                // alone and let the store keep `updated_at` still.
                None -> None
                Some(fixture) -> Some(fixture_json.to_string(fixture))
              },
            )
          case store.update_puzzle(path, id, changes) {
            Ok(row) -> respond_row(200, row)
            Error(store.UnknownPuzzleId(_)) ->
              envelope.error_response(404, ["UnknownPuzzle"])
            Error(store.DuplicateShowDate(_)) ->
              envelope.error_response(409, ["DuplicateShowDate"])
            Error(store.InvalidShowDate(_)) ->
              envelope.error_response(400, ["BadPuzzleDate"])
            Error(_) -> envelope.error_response(500, ["StoreError"])
          }
        }
      }
  }
}

/// The store's own "nothing to say" value for a field whose new value equals
/// the old one.
fn changed(new: a, old: a) -> Option(a) {
  case new == old {
    True -> None
    False -> Some(new)
  }
}

/// The fixture (if it must be rewritten) and the dots JSON (if they changed).
///
/// Three cases, each with a reason:
///   - the drawing changed  -> re-derive from it (Q2/Q3: the fixture is the
///     derivation of the drawing);
///   - only name/show_date changed -> keep the numbers, rewrite the labels in
///     the fixture's embedded copy (the served document takes identity from the
///     row, so this is coherence, not correctness — but a stored fixture that
///     disagrees with its row is a trap for the next reader);
///   - nothing changed -> `None`, so the store writes nothing (and does not bump
///     `updated_at` for a no-op).
type PatchFailure {
  /// The new drawing cannot be derived (<3 dots): 400 BadDrawing.
  BadDrawing
  /// A stored row that no longer decodes: 500 StoreError.
  StoreFault
}

fn fixture_for_update(
  existing: store.Puzzle,
  patch: Patch,
) -> Result(#(Option(derivation.Fixture), Option(String)), PatchFailure) {
  let name = option.unwrap(patch.name, existing.name)
  let show_date = option.unwrap(patch.show_date, existing.show_date)
  case patch.dots {
    Some(dots) -> {
      let fixture = derivation.derive_fixture(dots, name, show_date)
      case derivation.is_degenerate(fixture) {
        True -> Error(BadDrawing)
        False -> Ok(#(Some(fixture), Some(fixture_json.dots_to_string(dots))))
      }
    }
    None ->
      case name == existing.name && show_date == existing.show_date {
        True -> Ok(#(None, None))
        False ->
          case fixture_json.decode(existing.fixture_json) {
            Ok(fixture) ->
              Ok(#(
                Some(
                  derivation.Fixture(
                    ..fixture,
                    name: name,
                    show_date: show_date,
                  ),
                ),
                None,
              ))
            // A row whose fixture no longer decodes: repair it from its own
            // drawing rather than refusing the edit forever.
            Error(_) ->
              case fixture_json.dots_from_json(existing.dots_json) {
                Ok(dots) ->
                  Ok(#(
                    Some(derivation.derive_fixture(dots, name, show_date)),
                    None,
                  ))
                Error(_) -> Error(StoreFault)
              }
          }
      }
  }
}

// ---------- DELETE /api/admin/puzzles/<id> ----------

fn delete_puzzle(id: Int) -> wisp.Response {
  case store.delete_puzzle(store.path_from_env(), id) {
    Ok(True) -> wisp.no_content()
    Ok(False) -> envelope.error_response(404, ["UnknownPuzzle"])
    Error(_) -> envelope.error_response(500, ["StoreError"])
  }
}

// ---------- the full row document ----------

fn respond_row(status: Int, row: store.Puzzle) -> wisp.Response {
  case row_json(row) {
    Error(_) -> envelope.error_response(500, ["StoreError"])
    Ok(document) ->
      case status {
        201 -> envelope.created_with([#("puzzle", document)])
        _ -> envelope.ok_with([#("puzzle", document)])
      }
  }
}

/// The editor's document: the row's identity and timestamps, plus the drawing
/// and the fixture PARSED back out (the editor edits dots; the dialog shows the
/// fixture it is about to serve). Timestamps are epoch seconds — the same unit
/// the store keeps — not ISO strings: one unit end to end, no timezone in a
/// number.
fn row_json(row: store.Puzzle) -> Result(json.Json, Nil) {
  case
    fixture_json.decode(row.fixture_json),
    fixture_json.dots_from_json(row.dots_json)
  {
    Ok(fixture), Ok(dots) ->
      Ok(
        json.object([
          #("id", json.int(row.id)),
          #("name", json.string(row.name)),
          #("showDate", json.string(row.show_date)),
          #("dots", fixture_json.dots_to_json(dots)),
          #("fixture", fixture_json.fixture_to_json(fixture)),
          #("createdAt", json.int(row.created_at)),
          #("updatedAt", json.int(row.updated_at)),
        ]),
      )
    _, _ -> Error(Nil)
  }
}

// ---------- bodies ----------

/// A create or update body, decoded leniently: each field is `None` when ABSENT
/// so "missing" and "invalidly empty" can be told apart from "wrong type" (a
/// wrong type fails the whole document -> 400 BadRequest).
type Draft {
  Draft(
    name: Option(String),
    show_date: Option(String),
    dots: Option(dynamic.Dynamic),
  )
}

fn parse_draft(body: String) -> Result(Draft, Nil) {
  json.parse(body, using: draft_decoder())
  |> result.map_error(fn(_error) { Nil })
}

fn draft_decoder() -> decode.Decoder(Draft) {
  use name <- decode.optional_field(
    "name",
    None,
    decode.optional(decode.string),
  )
  use show_date <- decode.optional_field(
    "showDate",
    None,
    decode.optional(decode.string),
  )
  use dots <- decode.optional_field(
    "dots",
    None,
    decode.optional(decode.dynamic),
  )
  decode.success(Draft(name: name, show_date: show_date, dots: dots))
}

type NewPuzzle {
  NewPuzzle(name: String, show_date: String, dots: List(Dot))
}

/// The create body's rules. All problems are collected, in field order.
fn validated_new(draft: Draft) -> Result(NewPuzzle, List(String)) {
  let name = required(draft.name, validated_name, "BadName")
  let show_date = required(draft.show_date, validated_date, "BadPuzzleDate")
  let dots = validated_dots(draft.dots)
  case name, show_date, dots {
    Ok(name), Ok(show_date), Ok(dots) ->
      Ok(NewPuzzle(name: name, show_date: show_date, dots: dots))
    _, _, _ ->
      Error(list.append(
        problem_list(name),
        list.append(problem_list(show_date), problem_list(dots)),
      ))
  }
}

/// A partial update: `None` means "the body did not mention this field".
type Patch {
  Patch(
    name: Option(String),
    show_date: Option(String),
    dots: Option(List(Dot)),
  )
}

fn validated_patch(draft: Draft) -> Result(Patch, List(String)) {
  let name = optional_problem(draft.name, validated_name)
  let show_date = optional_problem(draft.show_date, validated_date)
  let dots = case draft.dots {
    None -> Ok(None)
    Some(value) -> validated_dots_required(value) |> result.map(Some)
  }
  case name, show_date, dots {
    Ok(name), Ok(show_date), Ok(dots) ->
      Ok(Patch(name: name, show_date: show_date, dots: dots))
    _, _, _ ->
      Error(list.append(
        problem_list(name),
        list.append(problem_list(show_date), problem_list(dots)),
      ))
  }
}

/// A field the body MUST carry: absent is the field's own error name (a create
/// body with no `name` is a blank name, not a broken request).
fn required(
  value: Option(a),
  validate: fn(a) -> Result(b, String),
  missing: String,
) -> Result(b, String) {
  case value {
    None -> Error(missing)
    Some(value) -> validate(value)
  }
}

fn optional_problem(
  value: Option(a),
  validate: fn(a) -> Result(b, String),
) -> Result(Option(b), String) {
  case value {
    None -> Ok(None)
    Some(value) -> validate(value) |> result.map(Some)
  }
}

fn problem_list(result: Result(a, String)) -> List(String) {
  case result {
    Ok(_) -> []
    Error(problem) -> [problem]
  }
}

/// A name is non-empty after trimming. Trimming is the rule, not a courtesy: a
/// menu row of invisible spaces is a bug the store cannot see.
fn validated_name(name: String) -> Result(String, String) {
  case string.trim(name) {
    "" -> Error("BadName")
    trimmed -> Ok(trimmed)
  }
}

fn validated_date(show_date: String) -> Result(String, String) {
  case dates.is_valid_date(show_date) {
    True -> Ok(show_date)
    False -> Error("BadPuzzleDate")
  }
}

fn validated_dots(value: Option(dynamic.Dynamic)) -> Result(List(Dot), String) {
  case value {
    None -> Error("BadDrawing")
    Some(value) -> validated_dots_required(value)
  }
}

/// Decode a `[[x, y], ...]` JSON array into the sketch's dot list. Whole
/// numbers arrive as ints from JavaScript's `JSON.stringify`; the decoder
/// accepts both spellings (fixture_json.dots_decoder).
fn validated_dots_required(
  value: dynamic.Dynamic,
) -> Result(List(Dot), String) {
  case decode.run(value, fixture_json.dots_decoder()) {
    Ok(dots) -> Ok(dots)
    Error(_) -> Error("BadDrawing")
  }
}
