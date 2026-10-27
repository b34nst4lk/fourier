//// The stored attempt's codec and transitions: one player's progress on one
//// puzzle date, kept client-side so a reopened tab resumes where it left off.
////
//// What is pinned here: the exact JSON document (field names, the move pairs,
//// the freeze boundary and the 500-entry cap) and the two POST bodies the
//// backend decodes (`/api/solve` with the move list, `/api/attempts/abandon`
//// with only the count) — the toy cannot import toy_admin, so these literals
//// are the contract with the routes' decoders.
////
//// Schema v2: `state` is a 3-term array, one entry per dialed term. A stored
//// document of any other shape is STALE — the sanctioned version-bump
//// retirement: it decodes to Error(Nil) and the board starts fresh.

import fourier_toy/attempt
import fourier_toy/shapes
import gleam/list
import gleeunit/should

const date = "2026-10-26"

const uuid = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"

fn terms() -> List(shapes.TermState) {
  [
    shapes.TermState(-1, 17.97, 355.0),
    shapes.TermState(1, 11.3, 305.0),
    shapes.TermState(-3, 4.68, 260.0),
  ]
}

fn fresh() -> attempt.Attempt {
  attempt.fresh(date, terms())
}

// ---------- the document ----------

pub fn a_fresh_attempt_encodes_the_documented_document_test() {
  // Field names and the move-pair spelling are the contract with the next
  // reader of this storage key (the same tab after a reload, and nothing else).
  should.equal(
    // NB: whole degrees ride as bare ints (355 not 355.0) — that is what
    // JSON.stringify emits and what the decoder accepts back.
    "{\"v\":2,\"date\":\"2026-10-26\",\"state\":[{\"k\":-1,\"r\":17.97,\"phase\":355},{\"k\":1,\"r\":11.3,\"phase\":305},{\"k\":-3,\"r\":4.68,\"phase\":260}],\"moves\":[],\"count\":0,\"solved\":false,\"reported\":false}",
    attempt.encode(fresh()),
  )
}

pub fn an_attempt_round_trips_test() {
  let played =
    fresh()
    |> attempt.add_move(0, 1)
    |> attempt.add_move(1, -1)
    |> attempt.record(terms(), 2, False)
  let assert Ok(read_back) = attempt.decode(attempt.encode(played))
  should.equal(played.moves, read_back.moves)
  should.equal(2, read_back.count)
  should.equal(date, read_back.date)
  should.equal(False, read_back.solved)
  should.equal(terms(), read_back.state)
}

pub fn a_v1_document_is_stale_test() {
  // Exactly what schema v1 wrote: four dial terms. A version bump is the
  // sanctioned way to retire a stored format — the board starts fresh, never
  // with a half-restored 4-term board and never with a crash.
  should.equal(
    Error(Nil),
    attempt.decode(
      "{\"v\":1,\"date\":\"2026-10-26\",\"state\":[{\"k\":-1,\"r\":17.97,\"phase\":355},{\"k\":1,\"r\":11.3,\"phase\":305},{\"k\":-3,\"r\":4.68,\"phase\":260},{\"k\":3,\"r\":2.83,\"phase\":195}],\"moves\":[],\"count\":0,\"solved\":false,\"reported\":false}",
    ),
  )
}

pub fn the_state_must_be_three_terms_test() {
  // A v2 document carries exactly the board's three terms; anything else is
  // not this toy's attempt (and a future `v` is not this reader's document).
  let doc = fn(state: String) {
    "{\"v\":2,\"date\":\"2026-10-26\",\"state\":["
    <> state
    <> "],\"moves\":[],\"count\":0,\"solved\":false,\"reported\":false}"
  }
  let term = fn(k: String, r: String, phase: String) {
    "{\"k\":" <> k <> ",\"r\":" <> r <> ",\"phase\":" <> phase <> "}"
  }
  // four terms: a 4-slot board's document
  should.equal(
    Error(Nil),
    attempt.decode(doc(
      term("-1", "17.97", "355.0")
      <> ","
      <> term("1", "11.3", "305.0")
      <> ","
      <> term("-3", "4.68", "260.0")
      <> ","
      <> term("3", "2.83", "195.0"),
    )),
  )
  // two terms: not a board either
  should.equal(
    Error(Nil),
    attempt.decode(doc(
      term("-1", "17.97", "355.0") <> "," <> term("1", "11.3", "305.0"),
    )),
  )
  should.equal(Error(Nil), attempt.decode("{\"v\":3,\"date\":\"2026-10-26\"}"))
  should.equal(Error(Nil), attempt.decode("{}"))
  should.equal(Error(Nil), attempt.decode(""))
}

pub fn whole_number_terms_read_back_as_floats_test() {
  // A state written by JSON.stringify carries 355, not 355.0 — both spellings
  // are the same number, and the dial arithmetic needs a Float either way.
  let assert Ok(read_back) =
    attempt.decode(
      "{\"v\":2,\"date\":\"2026-10-26\",\"state\":[{\"k\":-1,\"r\":18,\"phase\":355},{\"k\":1,\"r\":11.3,\"phase\":305.0},{\"k\":-3,\"r\":4.68,\"phase\":260.0}],\"moves\":[],\"count\":0,\"solved\":false,\"reported\":false}",
    )
  should.equal(
    Ok(shapes.TermState(-1, 18.0, 355.0)),
    list.first(read_back.state),
  )
}

// ---------- transitions ----------

pub fn moves_are_recorded_in_play_order_test() {
  let played =
    fresh()
    |> attempt.add_move(2, 1)
    |> attempt.add_move(0, -1)
  should.equal([#(2, 1), #(0, -1)], played.moves)
}

pub fn the_move_list_caps_at_five_hundred_test() {
  // the list is capped at 500 (the backend refuses more). Dropping the
  // overflow keeps the record reproducible from the start state; the count
  // still tells the truth about how many steps were taken.
  let long =
    list.fold(list.repeat(1, 520), fresh(), fn(a, _) {
      attempt.add_move(a, 0, 1)
    })
  should.equal(500, list.length(long.moves))
  let recorded = attempt.record(long, terms(), 520, False)
  should.equal(520, recorded.count)
  should.equal(500, list.length(recorded.moves))
}

pub fn every_step_records_state_count_and_solve_test() {
  let played = attempt.record(fresh(), terms(), 3, True)
  should.equal(3, played.count)
  should.equal(True, played.solved)
  should.equal(False, played.reported)
}

pub fn reporting_marks_the_attempt_test() {
  let solved = attempt.record(fresh(), terms(), 3, True)
  let reported = attempt.mark_reported(solved)
  should.equal(True, reported.reported)
  // the record itself is untouched
  should.equal(3, reported.count)
  should.equal(solved.moves, reported.moves)
}

// ---------- the two POST bodies ----------

pub fn the_solve_body_is_the_documented_payload_test() {
  // POST /api/solve: {uuid, puzzleDate, moves: [{slot, dir}, ...]} — the
  // reproducible record (start state + moves ⇒ final state).
  let played =
    fresh()
    |> attempt.add_move(0, 1)
    |> attempt.add_move(2, -1)
    |> attempt.record(terms(), 2, True)
  should.equal(
    "{\"uuid\":\"3f2504e0-4f89-41d3-9a0c-0305e82c3301\",\"puzzleDate\":\"2026-10-26\",\"moves\":[{\"slot\":0,\"dir\":1},{\"slot\":2,\"dir\":-1}]}",
    attempt.solve_body(uuid, played),
  )
}

pub fn the_abandon_body_carries_only_the_count_test() {
  // POST /api/attempts/abandon: {uuid, puzzleDate, moves: N} — an abandoned
  // attempt has no list worth keeping, only how far it got.
  let played = attempt.record(fresh(), terms(), 7, False)
  should.equal(
    "{\"uuid\":\"3f2504e0-4f89-41d3-9a0c-0305e82c3301\",\"puzzleDate\":\"2026-10-26\",\"moves\":7}",
    attempt.abandon_body(uuid, played),
  )
}
