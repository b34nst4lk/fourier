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

import fourier_toy/puzzle
import fourier_toy/shapes
import fourier_toy/wire
import gleam/list
import gleeunit/should

/// The star, derived by the backend (dial truth amplitude-ordered, phases
/// snapped to 5°, the standard arrangement, the derived start).
const star_json =
  "{\"status\":\"ok\",\"puzzle\":{\"name\":\"the star\",\"showDate\":\"2026-10-26\",\"dots\":[[10.0,50.0],[90.0,50.0]],\"centroid\":[50.0,49.999824523925774],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":1,\"radius\":27.574653306648354,\"phase\":270.0},{\"k\":-4,\"radius\":6.0,\"phase\":270.0},{\"k\":6,\"radius\":3.0,\"phase\":270.0},{\"k\":-14,\"radius\":0.5,\"phase\":270.0}],\"extras\":[{\"k\":2,\"radius\":0.25,\"phase\":90.0}],\"patches\":[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"radius\",\"pct\":73.0},{\"kind\":\"k\",\"k\":4},{\"kind\":\"keep\"}],\"target\":[[50.0,10.0],[60.0,40.0]]}}"

pub fn the_served_puzzle_decodes_to_a_setup_and_a_shape_test() {
  let assert Ok(daily) = wire.decode(star_json)
  let setup = daily.setup
  let shape = daily.shape

  // identity: the fixture name is the toy's title, the row's date labels it
  should.equal("the star", setup.title)
  should.equal("the star", setup.id)
  should.equal("2026-10-26", daily.show_date)

  // the arrangement rides with the puzzle (Q19) — the toy never hard-codes it
  should.equal(
    [puzzle.DialP, puzzle.DialR, puzzle.DialK, puzzle.DialFixed],
    setup.dials,
  )

  // the starting patches are the backend's (fixture_json's vocabulary)
  should.equal(
    [
      puzzle.PhaseDeg(0.0),
      puzzle.RPct(73.0),
      puzzle.KSet(4),
      puzzle.Keep,
    ],
    setup.patches,
  )

  // the dial truth, the extras and the target are the served numbers
  should.equal(4, list.length(shape.dial))
  let assert [first, ..] = shape.dial
  should.equal(shapes.TermState(1, 27.574653306648354, 270.0), first)
  should.equal([shapes.TermState(2, 0.25, 90.0)], shape.extras)
  should.equal([#(50.0, 10.0), #(60.0, 40.0)], shape.target)
  should.equal(#(50.0, 49.999824523925774), shape.centroid)
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
  // k 4 (the patch), and the fixed slot at truth.
  let assert Ok(daily) = wire.decode(star_json)
  let state = puzzle.initial(daily.shape, daily.setup.patches)
  let assert [phase_slot, radius_slot, k_slot, fixed_slot] = state
  should.equal(0.0, phase_slot.phase_deg)
  should.equal(1, phase_slot.k)
  should.equal(0.73 *. 27.574653306648354, radius_slot.r)
  should.equal(4, k_slot.k)
  should.equal(-14, fixed_slot.k)
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

pub fn a_puzzle_without_its_start_is_refused_test() {
  // puzzle.initial needs exactly four patches; a document that cannot open a
  // board is a fallback, not a half-built screen.
  should.equal(
    Error(Nil),
    wire.decode(
      "{\"status\":\"ok\",\"puzzle\":{\"name\":\"n\",\"showDate\":\"2026-10-26\",\"centroid\":[50.0,50.0],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":1,\"radius\":27.0,\"phase\":270.0},{\"k\":-4,\"radius\":6.0,\"phase\":270.0},{\"k\":6,\"radius\":3.0,\"phase\":270.0},{\"k\":-14,\"radius\":0.5,\"phase\":270.0}],\"extras\":[],\"patches\":[],\"target\":[[50.0,10.0]]}}",
    ),
  )
}

pub fn a_puzzle_without_four_dials_is_refused_test() {
  // three dial terms is not a board either (the same four-slot gate)
  should.equal(
    Error(Nil),
    wire.decode(
      "{\"status\":\"ok\",\"puzzle\":{\"name\":\"n\",\"showDate\":\"2026-10-26\",\"centroid\":[50.0,50.0],\"dials\":[\"phase\",\"radius\",\"k\",\"fixed\"],\"dial\":[{\"k\":1,\"radius\":27.0,\"phase\":270.0}],\"extras\":[],\"patches\":[{\"kind\":\"phase\",\"deg\":0.0},{\"kind\":\"radius\",\"pct\":73.0},{\"kind\":\"k\",\"k\":4},{\"kind\":\"keep\"}],\"target\":[[50.0,10.0]]}}",
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
