//// The admin access fence.
////
//// Cloudflare Access is the wall; this fence is the door-latch the backend can
//// check for itself. Every /api/admin/* request passes through `access.check`
//// BEFORE any method routing or body read.
////
//// What is verified (and what is not) is the module header's story; the tests
//// here pin the matrix the admin routes depend on:
////
////   no token                                -> 401 Unauthorized
////   token present but not a JWT             -> 403 Forbidden
////   aud missing / not containing ours       -> 403 Forbidden
////   exp missing / in the past               -> 403 Forbidden
////   aud + exp good                          -> pass
////   ADMIN_ACCESS_AUD unset                  -> presence-only (any non-empty
////                                              token passes, nothing passes
////                                              without one)
////
//// The last row is the safety property: a typo in the environment must fail
//// toward "still needs a Cloudflare token", never toward "wide open".

import gleam/bit_array
import gleam/erlang/process
import gleam/http/request
import gleam/int
import gleam/option
import gleam/string
import gleeunit/should
import toy_admin/access

const now = 1_700_000_000

const aud = "toy-admin"

// ---------- the token header ----------

fn request_with(token: String) -> request.Request(String) {
  request.new() |> request.set_header(access.token_header, token)
}

fn request_without_token() -> request.Request(String) {
  request.new()
}

/// A JWT of the right shape: three dot-separated segments, the claims
/// base64url-encoded without padding (RFC 7515). The signature is nonsense on
/// purpose — this phase does not verify it (module header).
fn jwt(claims: String) -> String {
  "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9."
  <> bit_array.base64_url_encode(bit_array.from_string(claims), False)
  <> ".bm90LWEtc2lnbmF0dXJl"
}

fn claims(aud_field: String, exp_field: String) -> String {
  "{" <> aud_field <> "," <> exp_field <> "}"
}

fn good_claims() -> String {
  claims("\"aud\":[\"" <> aud <> "\"]", "\"exp\":" <> int_string(now + 60))
}

// ---------- the missing-token case ----------

pub fn a_missing_token_is_401_unauthorized_test() {
  let result = access.check(request_without_token(), now, option.Some(aud))
  should.equal(Error(access.MissingToken), result)
  should.equal(401, access.status_of(access.MissingToken))
  should.equal("Unauthorized", access.error_name(access.MissingToken))
}

pub fn a_blank_token_counts_as_missing_test() {
  should.equal(
    Error(access.MissingToken),
    access.check(request_with("   "), now, option.Some(aud)),
  )
}

pub fn missing_stays_401_even_without_a_configured_audience_test() {
  // Presence-only mode still requires presence. This is the whole point.
  should.equal(
    Error(access.MissingToken),
    access.check(request_without_token(), now, option.None),
  )
}

// ---------- the happy paths ----------

pub fn an_audience_array_containing_ours_passes_test() {
  should.equal(
    Ok(Nil),
    access.check(request_with(jwt(good_claims())), now, option.Some(aud)),
  )
}

pub fn a_bare_string_aud_claim_passes_test() {
  // RFC 7519 allows `aud` to be a single string; Access sends an array, but a
  // reader that only handled one spelling would break on the other.
  let token =
    jwt(claims("\"aud\":\"" <> aud <> "\"", "\"exp\":" <> int_string(now + 1)))
  should.equal(
    Ok(Nil),
    access.check(request_with(token), now, option.Some(aud)),
  )
}

pub fn exp_exactly_now_is_still_valid_test() {
  // The rule is `exp >= now`; a certificate that expires at this second is
  // still valid for this second.
  let token =
    jwt(claims("\"aud\":[\"" <> aud <> "\"]", "\"exp\":" <> int_string(now)))
  should.equal(
    Ok(Nil),
    access.check(request_with(token), now, option.Some(aud)),
  )
}

pub fn a_fractional_exp_is_read_as_seconds_test() {
  let token =
    jwt(claims(
      "\"aud\":[\"" <> aud <> "\"]",
      "\"exp\":" <> int_string(now + 10) <> ".0",
    ))
  should.equal(
    Ok(Nil),
    access.check(request_with(token), now, option.Some(aud)),
  )
}

// ---------- audience refusals ----------

pub fn another_audience_is_403_forbidden_test() {
  let token =
    jwt(claims(
      "\"aud\":[\"some-other-app\"]",
      "\"exp\":" <> int_string(now + 60),
    ))
  should.equal(
    Error(access.BadAudience),
    access.check(request_with(token), now, option.Some(aud)),
  )
  should.equal(403, access.status_of(access.BadAudience))
  should.equal("Forbidden", access.error_name(access.BadAudience))
}

pub fn an_audience_list_without_ours_is_refused_test() {
  let token =
    jwt(claims("\"aud\":[\"a\",\"b\"]", "\"exp\":" <> int_string(now + 60)))
  should.equal(
    Error(access.BadAudience),
    access.check(request_with(token), now, option.Some(aud)),
  )
}

pub fn a_missing_aud_claim_is_refused_test() {
  let token = jwt("{\"exp\":" <> int_string(now + 60) <> "}")
  should.equal(
    Error(access.BadAudience),
    access.check(request_with(token), now, option.Some(aud)),
  )
}

pub fn a_non_string_aud_claim_is_malformed_test() {
  let token = jwt(claims("\"aud\":42", "\"exp\":" <> int_string(now + 60)))
  should.equal(
    Error(access.MalformedToken),
    access.check(request_with(token), now, option.Some(aud)),
  )
}

// ---------- expiry refusals ----------

pub fn a_stale_certificate_is_403_test() {
  // A certificate the browser is still echoing must not open the door.
  let token =
    jwt(claims("\"aud\":[\"" <> aud <> "\"]", "\"exp\":" <> int_string(now - 1)))
  should.equal(
    Error(access.Expired),
    access.check(request_with(token), now, option.Some(aud)),
  )
  should.equal(403, access.status_of(access.Expired))
  should.equal("Forbidden", access.error_name(access.Expired))
}

pub fn a_missing_exp_claim_is_refused_test() {
  let token = jwt("{\"aud\":[\"" <> aud <> "\"]}")
  should.equal(
    Error(access.Expired),
    access.check(request_with(token), now, option.Some(aud)),
  )
}

pub fn a_non_numeric_exp_is_malformed_test() {
  let token = jwt(claims("\"aud\":[\"" <> aud <> "\"]", "\"exp\":\"tomorrow\""))
  should.equal(
    Error(access.MalformedToken),
    access.check(request_with(token), now, option.Some(aud)),
  )
}

// ---------- malformed tokens ----------

pub fn a_token_without_three_segments_is_refused_test() {
  should.equal(
    Error(access.MalformedToken),
    access.check(request_with("only.two"), now, option.Some(aud)),
  )
  should.equal(
    Error(access.MalformedToken),
    access.check(request_with("one"), now, option.Some(aud)),
  )
  should.equal(
    Error(access.MalformedToken),
    access.check(request_with("a.b.c.d"), now, option.Some(aud)),
  )
}

pub fn a_payload_that_is_not_base64_is_refused_test() {
  should.equal(
    Error(access.MalformedToken),
    access.check(request_with("h.!!!.s"), now, option.Some(aud)),
  )
}

pub fn a_payload_that_is_not_json_is_refused_test() {
  let token =
    "h."
    <> bit_array.base64_url_encode(bit_array.from_string("not json"), False)
    <> ".s"
  should.equal(
    Error(access.MalformedToken),
    access.check(request_with(token), now, option.Some(aud)),
  )
}

pub fn a_payload_that_is_not_a_json_object_is_refused_test() {
  let token =
    "h."
    <> bit_array.base64_url_encode(bit_array.from_string("[1,2]"), False)
    <> ".s"
  should.equal(
    Error(access.MalformedToken),
    access.check(request_with(token), now, option.Some(aud)),
  )
}

// ---------- presence-only mode (ADMIN_ACCESS_AUD unset) ----------

pub fn without_an_audience_any_present_token_passes_test() {
  // Documented trade: the tunnel is the only ingress; a token that Access put
  // there is assumed genuine. Presence-only still refuses an unauthenticated
  // caller that never came through Access.
  should.equal(
    Ok(Nil),
    access.check(request_with("not-even-a-jwt"), now, option.None),
  )
}

pub fn the_audience_configuration_reads_the_environment_test() {
  // The rule, with the environment injected: unset -> None, blank -> None,
  // padded -> trimmed. A blank value must behave like unset, not like "the
  // empty audience matches everything".
  should.equal(option.None, access.audience_from(fn(_key) { option.None }))
  should.equal(
    option.None,
    access.audience_from(fn(_key) { option.Some("   ") }),
  )
  should.equal(
    option.Some(aud),
    access.audience_from(fn(_key) { option.Some("  " <> aud <> " ") }),
  )
}

// ---------- the boot warning ----------

pub fn an_unset_audience_warns_once_at_boot_test() {
  // The observable: `announce_at_boot` hands the logger ONE line, and that line
  // says which variable to set and that the audience check is off. Main calls
  // this exactly once before the listener starts. A process mailbox is the
  // capture: it is mutable where the test body is not, and "exactly one
  // message" is exactly the "LOG ONCE" claim.
  let logger = process.new_subject()
  access.announce_at_boot(option.None, fn(line) { process.send(logger, line) })

  let assert Ok(line) = process.receive(logger, 0)
  should.be_true(string.contains(line, access.audience_env))
  should.be_true(string.contains(line, "audience check is OFF"))
  should.be_true(string.contains(line, "presence-only"))
  // ...and nothing else followed it.
  should.equal(Error(Nil), process.receive(logger, 0))
}

pub fn a_configured_audience_is_silent_at_boot_test() {
  let logger = process.new_subject()
  access.announce_at_boot(option.Some(aud), fn(line) {
    process.send(logger, line)
  })
  should.equal(Error(Nil), process.receive(logger, 0))
}

// ---------- helpers ----------

fn int_string(value: Int) -> String {
  int.to_string(value)
}
