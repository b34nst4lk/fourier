//// base64url contract (RFC 4648 §5, RFC 7515 §2), phase 4a.
////
//// NO HAND-WRITTEN ENCODER: gleam_stdlib 1.x already ships
//// `bit_array.base64_encode` / `base64_url_encode` (and their decoders) on
//// both targets, so the brief's "implement it pure in Gleam IF the stdlib
//// lacks it" condition is not met — there is nothing to implement and no new
//// dependency to add. What remains worth doing is PINNING the behaviour this
//// project relies on, so a future stdlib bump cannot quietly change it:
////
////   - the RFC 4648 §10 vectors (padding, empty input, non-multiple-of-3);
////   - the URL-safe alphabet swap (+/ <-> -_) with padding on and off;
////   - unpadded decode, which is what a JWT segment is (RFC 7515: base64url
////     WITHOUT padding) — the Access token's payload segment has no "=".
////
//// If a bump ever breaks one of these, the RED lands here, next to the
//// explanation, instead of inside a puzzling 401 in production.

import gleam/bit_array
import gleam/string
import gleeunit/should

fn bytes(text: String) -> BitArray {
  bit_array.from_string(text)
}

// ---------- RFC 4648 §10 vectors (standard alphabet, padded) ----------

pub fn rfc_4648_encode_vectors_test() {
  should.equal("", bit_array.base64_encode(bytes(""), True))
  should.equal("Zg==", bit_array.base64_encode(bytes("f"), True))
  should.equal("Zm8=", bit_array.base64_encode(bytes("fo"), True))
  should.equal("Zm9v", bit_array.base64_encode(bytes("foo"), True))
  should.equal("Zm9vYg==", bit_array.base64_encode(bytes("foob"), True))
  should.equal("Zm9vYmE=", bit_array.base64_encode(bytes("fooba"), True))
  should.equal("Zm9vYmFy", bit_array.base64_encode(bytes("foobar"), True))
}

pub fn rfc_4648_encode_without_padding_test() {
  should.equal("", bit_array.base64_encode(bytes(""), False))
  should.equal("Zg", bit_array.base64_encode(bytes("f"), False))
  should.equal("Zm8", bit_array.base64_encode(bytes("fo"), False))
  should.equal("Zm9vYg", bit_array.base64_encode(bytes("foob"), False))
  should.equal("Zm9vYmE", bit_array.base64_encode(bytes("fooba"), False))
}

pub fn rfc_4648_decode_vectors_test() {
  should.equal(Ok(bytes("f")), bit_array.base64_decode("Zg=="))
  should.equal(Ok(bytes("fo")), bit_array.base64_decode("Zm8="))
  should.equal(Ok(bytes("foo")), bit_array.base64_decode("Zm9v"))
  should.equal(Ok(bytes("foob")), bit_array.base64_decode("Zm9vYg=="))
  should.equal(Ok(bytes("fooba")), bit_array.base64_decode("Zm9vYmE="))
  should.equal(Ok(bytes("foobar")), bit_array.base64_decode("Zm9vYmFy"))
  // Padding-less input is accepted too — the JWT case.
  should.equal(Ok(bytes("foob")), bit_array.base64_decode("Zm9vYg"))
}

// ---------- the URL-safe alphabet ----------

pub fn url_safe_alphabet_swaps_the_two_symbols_test() {
  // 0xFB 0xFF exercises the two characters that differ: standard "+/" vs
  // URL-safe "-_". (A JWT payload can contain either byte sequence in a
  // utf-8 name or, more likely, in a signature we ignore.)
  let raw = <<0xFB, 0xFF>>
  should.equal("+/8=", bit_array.base64_encode(raw, True))
  should.equal("-_8=", bit_array.base64_url_encode(raw, True))
  should.equal("-_8", bit_array.base64_url_encode(raw, False))
}

pub fn url_safe_decode_accepts_unpadded_segments_test() {
  // RFC 7515 §2: JWT segments are base64url WITHOUT padding.
  let raw = <<0xFB, 0xFF>>
  should.equal(Ok(raw), bit_array.base64_url_decode("-_8="))
  should.equal(Ok(raw), bit_array.base64_url_decode("-_8"))
  // The decoders accept the standard alphabet as well (the alphabets differ
  // only in characters whose meaning is unambiguous), which is why our JWT
  // reader can hand a segment straight to `base64_url_decode`.
  should.equal(Ok(raw), bit_array.base64_url_decode("+/8"))
}

pub fn a_jwt_shaped_payload_round_trips_test() {
  let claims = "{\"aud\":[\"toy-admin\"],\"exp\":1700000000}"
  let segment = bit_array.base64_url_encode(bytes(claims), False)
  should.be_true(string_has_no_padding(segment))
  should.equal(Ok(bytes(claims)), bit_array.base64_url_decode(segment))
}

pub fn invalid_base64_is_refused_test() {
  should.equal(Error(Nil), bit_array.base64_url_decode("not base64!"))
  should.equal(Error(Nil), bit_array.base64_decode("not base64!"))
}

fn string_has_no_padding(segment: String) -> Bool {
  !string.contains(segment, "=")
}
