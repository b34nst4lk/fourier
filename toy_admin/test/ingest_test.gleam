//// Ingest validation (PLAN-daily-puzzles.md §2 Q22): uuid v4 format, the 500
//// move cap, and per-move slot/direction ranges. Every problem is reported,
//// not just the first — the client gets one complete answer.

import gleam/list
import gleeunit/should
import toy_admin/ingest.{
  type Move, BadDirection, BadPuzzleDate, BadSlot, BadUuid, Move, TooManyMoves,
}

const uuid = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"

const date = "2026-10-25"

fn moves(count: Int) -> List(Move) {
  list.repeat(Move(0, 1), count)
}

pub fn valid_solve_with_no_moves_test() {
  should.equal(Ok(Nil), ingest.validate_solve(uuid, date, []))
}

pub fn valid_solve_at_the_cap_test() {
  should.equal(Ok(Nil), ingest.validate_solve(uuid, date, moves(500)))
}

pub fn solve_past_the_cap_is_rejected_test() {
  should.equal(
    Error([TooManyMoves(501)]),
    ingest.validate_solve(uuid, date, moves(501)),
  )
}

pub fn over_the_cap_reports_only_the_cap_test() {
  // A huge list is not walked move-by-move: the cap alone is the answer.
  should.equal(
    Error([TooManyMoves(1000)]),
    ingest.validate_solve(uuid, date, list.repeat(Move(9, 9), 1000)),
  )
}

pub fn slot_out_of_range_is_rejected_test() {
  should.equal(
    Error([BadSlot(1, 4)]),
    ingest.validate_solve(uuid, date, [Move(0, 1), Move(4, 1)]),
  )
  should.equal(
    Error([BadSlot(0, -1)]),
    ingest.validate_solve(uuid, date, [Move(-1, 1)]),
  )
}

pub fn direction_must_be_minus_one_or_one_test() {
  should.equal(
    Error([BadDirection(0, 0)]),
    ingest.validate_solve(uuid, date, [Move(0, 0)]),
  )
  should.equal(
    Error([BadDirection(1, 2)]),
    ingest.validate_solve(uuid, date, [Move(0, 1), Move(3, 2)]),
  )
}

pub fn every_move_is_checked_test() {
  should.equal(
    Error([BadSlot(1, 5), BadDirection(2, -2), BadSlot(3, 99)]),
    ingest.validate_solve(uuid, date, [
      Move(0, 1),
      Move(5, 1),
      Move(2, -2),
      Move(99, 1),
    ]),
  )
}

pub fn uuid_version_must_be_four_test() {
  // v1-shaped uuid: same shape, version nibble 1
  should.equal(
    Error([BadUuid]),
    ingest.validate_solve("3f2504e0-4f89-11d3-9a0c-0305e82c3301", date, []),
  )
  should.be_true(ingest.is_uuid_v4(uuid))
  should.be_false(ingest.is_uuid_v4("3f2504e0-4f89-11d3-9a0c-0305e82c3301"))
}

pub fn uuid_variant_must_be_rfc4122_test() {
  // Variant nibble must be 8, 9, a or b; c is not a v4 variant.
  should.equal(
    Error([BadUuid]),
    ingest.validate_solve("3f2504e0-4f89-41d3-ca0c-0305e82c3301", date, []),
  )
}

pub fn uuid_is_canonical_lowercase_test() {
  // crypto.randomUUID() emits lowercase; anything else is rejected so one
  // player cannot mint two identities by re-casing.
  should.equal(
    Error([BadUuid]),
    ingest.validate_solve("3F2504E0-4F89-41D3-9A0C-0305E82C3301", date, []),
  )
}

pub fn malformed_uuids_are_rejected_test() {
  should.be_false(ingest.is_uuid_v4(""))
  should.be_false(ingest.is_uuid_v4("not-a-uuid"))
  should.be_false(ingest.is_uuid_v4("3f2504e04f8941d39a0c0305e82c3301"))
  should.be_false(ingest.is_uuid_v4("3f2504e0-4f89-41d3-9a0c-0305e82c330"))
  should.be_false(ingest.is_uuid_v4("3f2504e0-4f89-41d3-9a0c-0305e82c33011"))
  should.be_false(ingest.is_uuid_v4("3f2504e0_4f89_41d3_9a0c_0305e82c3301"))
  should.be_false(ingest.is_uuid_v4("3f2504e0-4f89-41d3-9a0c-0305e82c330g"))
}

pub fn puzzle_date_must_be_a_real_date_test() {
  should.equal(
    Error([BadPuzzleDate]),
    ingest.validate_solve(uuid, "2026-02-30", []),
  )
  should.equal(Error([BadPuzzleDate]), ingest.validate_solve(uuid, "", []))
}

pub fn all_problems_are_reported_together_test() {
  should.equal(
    Error([BadUuid, BadPuzzleDate, BadSlot(0, 7)]),
    ingest.validate_solve("nope", "2026-13-01", [Move(7, 1)]),
  )
}
