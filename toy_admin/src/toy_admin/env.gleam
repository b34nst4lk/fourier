//// The process environment, as Gleam Strings.
////
//// Erlang's `os:getenv/1` and `os:putenv/2` speak charlists ("strings" in Erlang
//// terms), which are NOT Gleam Strings (binaries). Calling them with a Gleam
//// String raises `badarg` — a trap worth isolating in one file rather than
//// rediscovering at every call site.
////
//// Configuration is read per request, not cached at boot: an `os:getenv` is a
//// hash lookup in the environment list and the values (`DB_PATH`, the throttle
//// windows) are read a handful of times per second at most. Not caching keeps
//// tests able to aim a single running server at a scratch database.

import gleam/option.{type Option}

/// The value of `key`, or `None` if it is unset.
@external(erlang, "env_ffi", "get")
pub fn get(key: String) -> Option(String)

/// Set `key` for this process and its future children. Tests and the container's
/// entrypoint use it; the server itself only reads.
@external(erlang, "env_ffi", "set")
pub fn set(key: String, value: String) -> Nil
