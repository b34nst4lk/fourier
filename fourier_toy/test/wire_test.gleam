//// The served puzzle's decoder (PLAN-daily-puzzles.md §1 Q1): the JSON
//// `/api/puzzle/today` answers with becomes the toy's `Setup` + `Shape`.
////
//// Why a decoder and not a second fixture pipeline: the backend derives the
//// dial truth and the 512-point target at save time (fixture_json.gleam). The
//// toy's job is to READ that, resolve the starting patches against the shape it
//// just read, and play — no DFT, no guessing which number is which.
////
//// What the decoder derives client-side is exactly what cannot ride the wire
//// without repeating the shape: `dial_max_r` (the biggest dialable radius, the
//// radius dial's unit and 200% ceiling) and `rms_polar` (the metric's
//// normalizer, computed from the target trace about the centroid).
////
//// Every document here is a fixture the backend really serves (the api test
//// pins the encoder; these pin the reader). Statuses other than "ok" — "none"
//// for an empty calendar, "error" for a refused request — are `Error(Nil)`:
//// the caller falls back to the built-in quaver.
////
//// The 3-lock and normalization (PLAN-dial-columns.md §4.1d): the board dials
//// exactly three terms, so a served document is normalized before it is
//// accepted — every "fixed" slot's truth term becomes an EXTRA (a
//// fixed-correct term IS an extra) and its patch is dropped, wherever the
//// slot sits. After normalization there must be exactly three dialable slots
//// with kinds in {phase, radius, k}; anything else is `Error(Nil)` (fallback).

import fourier_toy/puzzle
import fourier_toy/shapes
import fourier_toy/wire
import gleam/list
import gleeunit/should

fn approx(a: Float, b: Float, eps: Float) -> Nil {
  let delta = case a -. b >. 0.0 {
    True -> a -. b
    False -> b -. a
  }
  let assert True = delta <. eps
  Nil
}

/// The star, derived by the backend (dial truth amplitude-ordered, phases
/// snapped to 5°, the standard arrangement, the derived start).
const star_json =
  "{\"status\":\"ok\",\"puzzle\":{\"name\":\"the star\",\"showDate\":\"2026-10-26\",\"dots\":[[10.0,50.0],[90.0,50.0]],\"centroid\":[50.0,49.999824523925774],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":1,\"radius\":27.574653306648354,\"phase\":270.0},{\"k\":-4,\"radius\":6.0,\"phase\":270.0},{\"k\":6,\"radius\":3.0,\"phase\":270.0},{\"k\":-14,\"radius\":0.5,\"phase\":270.0}],\"extras\":[{\"k\":2,\"radius\":0.25,\"phase\":90.0}],\"patches\":[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"radius\",\"pct\":73.0},{\"kind\":\"k\",\"k\":4},{\"kind\":\"keep\"}],\"target\":[[50.0,10.0],[60.0,40.0]]}}"

/// A new-format document: three dials, three truth terms, three starts, no
/// fixed slot at all.
const three_slot_json =
  "{\"status\":\"ok\",\"puzzle\":{\"name\":\"the star\",\"showDate\":\"2026-10-26\",\"centroid\":[50.0,50.0],\"dials\":[\"phase\",\"radius\",\"k\"],\"dial\":[{\"k\":1,\"radius\":27.5,\"phase\":270.0},{\"k\":-4,\"radius\":6.0,\"phase\":270.0},{\"k\":6,\"radius\":3.0,\"phase\":270.0}],\"extras\":[{\"k\":2,\"radius\":0.25,\"phase\":90.0}],\"patches\":[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"radius\",\"pct\":73.0},{\"kind\":\"k\",\"k\":4}],\"target\":[[50.0,10.0],[60.0,40.0]]}}"

/// The fixed slot is NOT slot 4: arrangement [phase, fixed, k, radius].
const fixed_mid_json =
  "{\"status\":\"ok\",\"puzzle\":{\"name\":\"rearranged\",\"showDate\":\"2026-10-26\",\"centroid\":[50.0,50.0],\"dials\":[\"phase\",\"fixed\",\"k\",\"radius\"],\"dial\":[{\"k\":1,\"radius\":27.5,\"phase\":270.0},{\"k\":-4,\"radius\":6.0,\"phase\":270.0},{\"k\":6,\"radius\":3.0,\"phase\":270.0},{\"k\":-14,\"radius\":0.5,\"phase\":270.0}],\"extras\":[{\"k\":2,\"radius\":0.25,\"phase\":90.0}],\"patches\":[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"keep\"},{\"kind\":\"k\",\"k\":4},{\"kind\":\"radius\",\"pct\":73.0}],\"target\":[[50.0,10.0],[60.0,40.0]]}}"

pub fn the_served_puzzle_decodes_to_a_setup_and_a_shape_test() {
  let assert Ok(daily) = wire.decode(star_json)
  let setup = daily.setup
  let shape = daily.shape

  // identity: the fixture name is the toy's title, the row's date labels it
  should.equal("the star", setup.title)
  should.equal("the star", setup.id)
  should.equal("2026-10-26", daily.show_date)

  // the served "fixed" slot normalizes away: three dials, three starts
  should.equal([puzzle.DialP, puzzle.DialR, puzzle.DialK], setup.dials)
  should.equal(
    [puzzle.PhaseDeg(0.0), puzzle.RPct(73.0), puzzle.KSet(4)],
    setup.patches,
  )

  // the dial truth is the first three served terms
  should.equal(
    [
      shapes.TermState(1, 27.574653306648354, 270.0),
      shapes.TermState(-4, 6.0, 270.0),
      shapes.TermState(6, 3.0, 270.0),
    ],
    shape.dial,
  )
  // the served fixed term IS an extra — it comes FIRST, before the served
  // extras (the board's term order is preserved)
  should.equal(
    [shapes.TermState(-14, 0.5, 270.0), shapes.TermState(2, 0.25, 90.0)],
    shape.extras,
  )
  should.equal([#(50.0, 10.0), #(60.0, 40.0)], shape.target)
  should.equal(#(50.0, 49.999824523925774), shape.centroid)
  should.equal(27.574653306648354, shape.dial_max_r)
}

pub fn the_decoder_derives_what_the_wire_cannot_carry_test() {
  // dial_max_r is the biggest DIAL radius (27.57…, not the 0.25 extra) and
  // rms_polar is the target's polar RMS about the centroid — the same numbers
  // the built-in shapes compute for themselves (shapes.from_parts).
  let assert Ok(daily) = wire.decode(star_json)
  should.equal(27.574653306648354, daily.shape.dial_max_r)
  let expected =
    shapes.from_parts(
      name: "the star",
      centroid: #(50.0, 49.999824523925774),
      dial: daily.shape.dial,
      extras: daily.shape.extras,
      target: daily.shape.target,
    ).rms_polar
  should.equal(expected, daily.shape.rms_polar)
}

pub fn the_start_resolves_against_the_served_shape_test() {
  // What the board opens with: phase 0° (the patch), radius 73% of 27.57…,
  // k 4 (the patch) — and NO fourth slot (the pattern is exact).
  let assert Ok(daily) = wire.decode(star_json)
  let state = puzzle.initial(daily.shape, daily.setup.patches)
  let assert [phase_slot, radius_slot, k_slot] = state
  should.equal(shapes.TermState(1, 27.574653306648354, 0.0), phase_slot)
  should.equal(-4, radius_slot.k)
  approx(radius_slot.r, 0.73 *. 27.574653306648354, 1.0e-9)
  should.equal(shapes.TermState(4, 3.0, 270.0), k_slot)
}

pub fn a_new_format_document_decodes_directly_test() {
  // Three dials, three terms, three patches, no fixed slot: nothing to
  // normalize — the document is already a board.
  let assert Ok(daily) = wire.decode(three_slot_json)
  should.equal([puzzle.DialP, puzzle.DialR, puzzle.DialK], daily.setup.dials)
  should.equal(
    [puzzle.PhaseDeg(0.0), puzzle.RPct(73.0), puzzle.KSet(4)],
    daily.setup.patches,
  )
  should.equal(
    [
      shapes.TermState(1, 27.5, 270.0),
      shapes.TermState(-4, 6.0, 270.0),
      shapes.TermState(6, 3.0, 270.0),
    ],
    daily.shape.dial,
  )
  should.equal([shapes.TermState(2, 0.25, 90.0)], daily.shape.extras)
  should.equal(27.5, daily.shape.dial_max_r)
}

pub fn a_fixed_slot_anywhere_normalizes_test() {
  // The fixed slot is data, not a position: [phase, fixed, k, radius]
  // normalizes to dials [phase, k, radius] with the fixed truth term first
  // among the extras and the fixed slot's patch dropped.
  let assert Ok(daily) = wire.decode(fixed_mid_json)
  should.equal([puzzle.DialP, puzzle.DialK, puzzle.DialR], daily.setup.dials)
  should.equal(
    [
      shapes.TermState(1, 27.5, 270.0),
      shapes.TermState(6, 3.0, 270.0),
      shapes.TermState(-14, 0.5, 270.0),
    ],
    daily.shape.dial,
  )
  should.equal(
    [
      shapes.TermState(-4, 6.0, 270.0),
      shapes.TermState(2, 0.25, 90.0),
    ],
    daily.shape.extras,
  )
  should.equal(
    [puzzle.PhaseDeg(0.0), puzzle.KSet(4), puzzle.RPct(73.0)],
    daily.setup.patches,
  )
  // and the normalized board still opens
  let state = puzzle.initial(daily.shape, daily.setup.patches)
  should.equal(3, list.length(state))
}

pub fn a_real_board_starts_unsolved_test() {
  // The start is a puzzle, not the answer: a served puzzle must not arrive
  // solved (the derivation's start is a quarter turn and a radius cut away).
  let assert Ok(daily) = wire.decode(star_json)
  let state = puzzle.initial(daily.shape, daily.setup.patches)
  should.equal(False, shapes.match_pct(daily.shape, state) >=. shapes.solved_at)
}

// ---------- refusals: everything the client falls back on ----------

pub fn no_published_puzzle_is_not_a_puzzle_test() {
  should.equal(
    Error(Nil),
    wire.decode("{\"status\":\"none\",\"fallback\":true}"),
  )
  should.equal(
    Error(Nil),
    wire.decode("{\"status\":\"error\",\"errors\":[\"BadTimezone\"]}"),
  )
  should.equal(Error(Nil), wire.decode(""))
  should.equal(Error(Nil), wire.decode("<html>tunnel down</html>"))
}

pub fn a_four_dialable_document_is_refused_test() {
  // P10's arrangement (four dialable slots) violates the 3-lock: the board
  // has three columns, so a four-dial document is a fallback, not a board.
  should.equal(
    Error(Nil),
    wire.decode(
      "{\"status\":\"ok\",\"puzzle\":{\"name\":\"n\",\"showDate\":\"2026-10-26\",\"centroid\":[50.0,50.0],\"dials\":[\"phase\",\"radius\",\"k\",\"radius\"],\"dial\":[{\"k\":1,\"radius\":27.0,\"phase\":270.0},{\"k\":-4,\"radius\":6.0,\"phase\":270.0},{\"k\":6,\"radius\":3.0,\"phase\":270.0},{\"k\":-14,\"radius\":0.5,\"phase\":270.0}],\"extras\":[],\"patches\":[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"radius\",\"pct\":73.0},{\"kind\":\"k\",\"k\":4},{\"kind\":\"radius\",\"pct\":16.0}],\"target\":[[50.0,10.0]]}}",
    ),
  )
}

pub fn a_two_dialable_document_is_refused_test() {
  should.equal(
    Error(Nil),
    wire.decode(
      "{\"status\":\"ok\",\"puzzle\":{\"name\":\"n\",\"showDate\":\"2026-10-26\",\"centroid\":[50.0,50.0],\"dials\":[\"phase\",\"radius\"],\"dial\":[{\"k\":1,\"radius\":27.0,\"phase\":270.0},{\"k\":-4,\"radius\":6.0,\"phase\":270.0}],\"extras\":[],\"patches\":[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"radius\",\"pct\":73.0}],\"target\":[[50.0,10.0]]}}",
    ),
  )
}

pub fn a_six_dialable_document_is_refused_test() {
  // the recorded ≤6-term ceiling exists, but the board renders three columns:
  // an N>3 document is a fallback (N>3 rendering is parked)
  should.equal(
    Error(Nil),
    wire.decode(
      "{\"status\":\"ok\",\"puzzle\":{\"name\":\"n\",\"showDate\":\"2026-10-26\",\"centroid\":[50.0,50.0],\"dials\":[\"phase\",\"radius\",\"k\",\"radius\",\"k\",\"phase\"],\"dial\":[{\"k\":1,\"radius\":27.0,\"phase\":270.0},{\"k\":-4,\"radius\":6.0,\"phase\":270.0},{\"k\":6,\"radius\":3.0,\"phase\":270.0},{\"k\":-14,\"radius\":0.5,\"phase\":270.0},{\"k\":5,\"radius\":0.4,\"phase\":90.0},{\"k\":-3,\"radius\":0.3,\"phase\":180.0}],\"extras\":[],\"patches\":[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"radius\",\"pct\":73.0},{\"kind\":\"k\",\"k\":4},{\"kind\":\"radius\",\"pct\":16.0},{\"kind\":\"k\",\"k\":2},{\"kind\":\"phase\",\"deg\":90.0}],\"target\":[[50.0,10.0]]}}",
    ),
  )
}

pub fn a_puzzle_without_its_start_is_refused_test() {
  // puzzle.initial needs exactly three patches; a document that cannot open a
  // board is a fallback, not a half-built screen.
  should.equal(
    Error(Nil),
    wire.decode(
      "{\"status\":\"ok\",\"puzzle\":{\"name\":\"n\",\"showDate\":\"2026-10-26\",\"centroid\":[50.0,50.0],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":1,\"radius\":27.0,\"phase\":270.0},{\"k\":-4,\"radius\":6.0,\"phase\":270.0},{\"k\":6,\"radius\":3.0,\"phase\":270.0},{\"k\":-14,\"radius\":0.5,\"phase\":270.0}],\"extras\":[],\"patches\":[],\"target\":[[50.0,10.0]]}}",
    ),
  )
}

pub fn a_puzzle_without_three_dials_is_refused_test() {
  // four kinds but one truth term: the document contradicts itself
  should.equal(
    Error(Nil),
    wire.decode(
      "{\"status\":\"ok\",\"puzzle\":{\"name\":\"n\",\"showDate\":\"2026-10-26\",\"centroid\":[50.0,50.0],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":1,\"radius\":27.0,\"phase\":270.0}],\"extras\":[],\"patches\":[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"radius\",\"pct\":73.0},{\"kind\":\"k\",\"k\":4},{\"kind\":\"keep\"}],\"target\":[[50.0,10.0]]}}",
    ),
  )
}

pub fn an_empty_target_is_refused_test() {
  // `target` is the 512-point trace the score is measured against: an empty
  // list is a well-formed JSON array but NOT a usable metric. `shapes.from_parts`
  // derives rms_polar from it (asserting a non-zero count), so the boundary
  // must refuse it before any shape is built — a fallback, not a panic.
  should.equal(
    Error(Nil),
    wire.decode(
      "{\"status\":\"ok\",\"puzzle\":{\"name\":\"n\",\"showDate\":\"2026-10-26\",\"centroid\":[50.0,50.0],\"dials\":[\"phase\",\"radius\",\"k\"],\"dial\":[{\"k\":1,\"radius\":27.0,\"phase\":270.0},{\"k\":-4,\"radius\":6.0,\"phase\":270.0},{\"k\":6,\"radius\":3.0,\"phase\":270.0}],\"extras\":[],\"patches\":[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"radius\",\"pct\":73.0},{\"kind\":\"k\",\"k\":4}],\"target\":[]}}",
    ),
  )
}

pub fn an_unknown_patch_kind_is_refused_test() {
  should.equal(
    Error(Nil),
    wire.decode(
      "{\"status\":\"ok\",\"puzzle\":{\"name\":\"n\",\"showDate\":\"2026-10-26\",\"centroid\":[50.0,50.0],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":1,\"radius\":27.0,\"phase\":270.0},{\"k\":-4,\"radius\":6.0,\"phase\":270.0},{\"k\":6,\"radius\":3.0,\"phase\":270.0},{\"k\":-14,\"radius\":0.5,\"phase\":270.0}],\"extras\":[],\"patches\":[{\"kind\":\"wobble\"},{\"kind\":\"radius\",\"pct\":73.0},{\"kind\":\"k\",\"k\":4},{\"kind\":\"keep\"}],\"target\":[[50.0,10.0]]}}",
    ),
  )
}

pub fn whole_number_coordinates_read_as_floats_test() {
  // JSON.stringify emits 10, not 10.0 — the centroid and target must accept
  // both spellings (the backend's own decoder does).
  let assert Ok(daily) =
    wire.decode(
      "{\"status\":\"ok\",\"puzzle\":{\"name\":\"n\",\"showDate\":\"2026-10-26\",\"centroid\":[50,50],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":1,\"radius\":27,\"phase\":270},{\"k\":-4,\"radius\":6,\"phase\":270},{\"k\":6,\"radius\":3,\"phase\":270},{\"k\":-14,\"radius\":0.5,\"phase\":270}],\"extras\":[],\"patches\":[{\"kind\":\"phase\",\"deg\":0},{\"kind\":\"radius\",\"pct\":73},{\"kind\":\"k\",\"k\":4},{\"kind\":\"keep\"}],\"target\":[[50,10],[60,40]]}}",
    )
  should.equal(#(50.0, 50.0), daily.shape.centroid)
  should.equal(27.0, daily.shape.dial_max_r)
  should.equal([#(50.0, 10.0), #(60.0, 40.0)], daily.shape.target)
}
