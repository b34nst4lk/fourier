//// The admin access fence (PLAN-daily-puzzles.md §2 Q12/§3, phase 4a).
////
//// ============================================================================
//// THIS MODULE DOES NOT VERIFY THE JWT SIGNATURE. READ THIS BEFORE CHANGING IT.
//// ============================================================================
////
//// Cloudflare Access puts `Cf-Access-Jwt-Assertion` on every request that got
//// through the Access application. The token is an RS256 JWT signed by
//// Cloudflare with a key set published at
//// `https://<team>.cloudflareaccess.com/cdn-cgi/access/certs`. Verifying that
//// signature means fetching and rotating a JWKS, pinning the issuer, and
//// carrying a crypto dependency — and the plan parks it on the shelf (Q12,
//// §7: "Access JWT full signature verification — if the ingress surface ever
//// grows beyond the tunnel").
////
//// The reasoning is the ingress, not this code: the container publishes no host
//// ports (Q13), the tunnel's rule routes /api here, and the Access policy sits
//// in front of /api/admin*. Cloudflare strips or ignores a client-supplied
//// `Cf-Access-Jwt-Assertion` that did not come from Access, so "there is a
//// token" means "Access minted a token for a request it admitted". This fence
//// therefore checks SANITY, not authenticity:
////
////   - a token must be PRESENT (missing -> 401 Unauthorized);
////   - its payload must parse as a JSON object (else 403 Forbidden);
////   - `aud` must contain our audience (else 403);
////   - `exp` must be present and >= now (else 403) — a stale certificate the
////     browser is still echoing must not open the door.
////
//// If this surface ever grows beyond the tunnel, the shelf item is the whole
//// answer: verify the signature, pin `iss`, check `nbf`/`iat`. Until then this
//// module says plainly what it does and does not do.
////
//// ADMIN_ACCESS_AUD (the Access application's audience tag) is read from the
//// environment per request, like the rest of the config (env.gleam explains
//// why). UNSET OR BLANK means PRESENCE-ONLY: the token must still exist, but
//// its claims are not checked. That is a deliberate fail-toward-safe default —
//// a compose typo loses the audience/expiry check, it does NOT open the admin
//// routes to someone who never passed Access. The boot warning announces it
//// once (access.announce_at_boot is called from main).
////
//// Order of checks: presence -> shape/JSON -> exp -> aud. Expiry before
//// audience because a stale token is stale regardless of who it names.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/float
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import toy_admin/env

/// The header Cloudflare Access adds to admitted requests. Lowercase because
/// HTTP header names are case-insensitive and every layer below stores them
/// that way (mist included).
pub const token_header = "cf-access-jwt-assertion"

/// The Access application's audience (AUD) tag. See the header for what an
/// unset/blank value means.
pub const audience_env = "ADMIN_ACCESS_AUD"

pub type Failure {
  /// No (or blank) Cf-Access-Jwt-Assertion header: the caller did not come
  /// through Access at all. 401.
  MissingToken
  /// A token is present but is not a three-segment JWT whose payload is a JSON
  /// object with usable claims. 403.
  MalformedToken
  /// The token's audience does not contain ours (or names no audience). 403.
  BadAudience
  /// `exp` is in the past — or absent, which cannot prove currency. 403.
  Expired
}

/// The fence. `audience = None` is presence-only mode (ADMIN_ACCESS_AUD unset
/// or blank).
pub fn check(
  request: request.Request(a),
  now_seconds: Int,
  audience: Option(String),
) -> Result(Nil, Failure) {
  let token = case request.get_header(request, token_header) {
    Ok(value) -> string.trim(value)
    Error(_) -> ""
  }
  case token {
    "" -> Error(MissingToken)
    _ ->
      case audience {
        // Presence-only (see the header): the token exists, and existence is
        // all this mode can honestly check.
        None -> Ok(Nil)
        Some(expected) -> verify(token, now_seconds, expected)
      }
  }
}

/// 401 for "you never came through Access", 403 for "your certificate is not
/// good enough".
pub fn status_of(failure: Failure) -> Int {
  case failure {
    MissingToken -> 401
    _ -> 403
  }
}

/// The stable error name in the JSON envelope (plan §8). Two names, not four:
/// the admin UI's reaction to any refused certificate is "log in again".
pub fn error_name(failure: Failure) -> String {
  case failure {
    MissingToken -> "Unauthorized"
    _ -> "Forbidden"
  }
}

/// The audience this process is configured to require, or `None` for
/// presence-only mode.
pub fn configured_audience() -> Option(String) {
  audience_from(env.get)
}

/// The audience rule with the environment lookup injected, so the rule is
/// testable without mutating the process environment (store.path_from's shape).
pub fn audience_from(get: fn(String) -> Option(String)) -> Option(String) {
  case get(audience_env) {
    None -> None
    Some(value) ->
      case string.trim(value) {
        "" -> None
        trimmed -> Some(trimmed)
      }
  }
}

/// The boot line, when there is one. `None` when the audience is configured —
/// the dangerous state is the one worth a line; the safe state is visible in
/// the environment itself.
pub fn boot_warning(audience: Option(String)) -> Option(String) {
  case audience {
    Some(_) -> None
    None ->
      Some(
        "toy_admin: "
        <> audience_env
        <> " is unset — the Cloudflare Access audience check is OFF. Admin"
        <> " routes are in presence-only mode: a Cf-Access-Jwt-Assertion token"
        <> " must still be present, but its audience and expiry are not"
        <> " checked. Set "
        <> audience_env
        <> " to the Access application's AUD tag to enforce them.",
      )
  }
}

/// Emit the boot warning exactly once, through the caller's logger. Main calls
/// this once before the listener starts; a test injects a mailbox to pin the
/// "once" and the content.
pub fn announce_at_boot(
  audience: Option(String),
  log: fn(String) -> Nil,
) -> Nil {
  case boot_warning(audience) {
    Some(line) -> log(line)
    None -> Nil
  }
}

// ---------- the token ----------

type Claims {
  Claims(aud: List(String), exp: Option(Int))
}

fn verify(
  token: String,
  now_seconds: Int,
  expected_audience: String,
) -> Result(Nil, Failure) {
  use claims <- result.try(claims_of(token))
  case claims.exp {
    // No exp claim: a certificate that cannot prove it is current is treated
    // as stale. The door stays shut.
    None -> Error(Expired)
    Some(exp) ->
      case exp >= now_seconds {
        False -> Error(Expired)
        True ->
          case list.contains(claims.aud, expected_audience) {
            True -> Ok(Nil)
            False -> Error(BadAudience)
          }
      }
  }
}

/// The payload segment's claims. Every failure maps to `MalformedToken`: the
/// reason a token is unusable is a server-side diagnostic, not something the
/// admin UI can act on differently.
fn claims_of(token: String) -> Result(Claims, Failure) {
  use segment <- result.try(
    payload_segment(token)
    |> result.map_error(fn(_) { MalformedToken }),
  )
  use bytes <- result.try(
    bit_array.base64_url_decode(segment)
    |> result.map_error(fn(_) { MalformedToken }),
  )
  use text <- result.try(
    bit_array.to_string(bytes)
    |> result.map_error(fn(_) { MalformedToken }),
  )
  case json.parse(text, using: claims_decoder()) {
    Ok(claims) -> Ok(claims)
    Error(_) -> Error(MalformedToken)
  }
}

fn payload_segment(token: String) -> Result(String, Nil) {
  // JWT compact serialisation: header.payload.signature. Anything else is not
  // a JWT. The header is NOT inspected (alg/typ are the signer's business, and
  // this module does not verify signatures — see the header).
  case string.split(token, ".") {
    [_header, payload, _signature] -> Ok(payload)
    _ -> Error(Nil)
  }
}

fn claims_decoder() -> decode.Decoder(Claims) {
  // Both claims are read leniently so a MISSING claim keeps its own meaning:
  // no `aud` -> BadAudience (no audience matches), no `exp` -> Expired (cannot
  // prove currency). A present-but-wrongly-typed claim is a malformed token.
  use aud <- decode.optional_field("aud", [], audience_decoder())
  use exp <- decode.optional_field(
    "exp",
    None,
    decode.optional(numeric_decoder()),
  )
  decode.success(Claims(aud: aud, exp: exp))
}

/// RFC 7519: `aud` is either a string or an array of strings. Access sends an
/// array; a reader that only handled one spelling would break on the other.
fn audience_decoder() -> decode.Decoder(List(String)) {
  decode.one_of(decode.list(decode.string), or: [
    decode.map(decode.string, fn(single) { [single] }),
  ])
}

/// `exp` is NumericDate seconds. Integers are the norm; a JSON parser that
/// hands floats is still reading a number, so both spellings decode.
fn numeric_decoder() -> decode.Decoder(Int) {
  decode.one_of(decode.int, or: [decode.map(decode.float, float.truncate)])
}
