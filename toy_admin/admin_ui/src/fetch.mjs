// The one network call in the bundle: fetch, then hand the status and the body
// text back to Gleam, which decodes it (wire.gleam) and decides what to say.
//
// Why the FFI stops at text: decoding is a pure function with tests, and this
// file has none. Keeping JSON parsing on the Gleam side means the envelope, the
// error names and the "unreadable body" path are all covered by `gleam test`.
//
// Every outcome — refused fence (401), validation (400), server trouble (500),
// a network failure with no status at all — arrives as exactly one call to
// `on_done(status, text)`, never a throw. A network failure reports status 0
// with an empty body, and wire.decode_* turns that into the same kind of
// Failure an HTTP error would be.

export function fetch_request(method, path, body, on_done) {
  const init = {
    method,
    credentials: "same-origin",
    headers: { accept: "application/json" },
  };
  if (typeof body === "string" && body !== "") {
    init.headers["content-type"] = "application/json";
    init.body = body;
  }

  fetch(path, init).then(
    (response) => {
      response.text().then(
        (text) => on_done(response.status, text),
        () => on_done(response.status, ""),
      );
    },
    () => on_done(0, ""),
  );
  return undefined;
}

// One-shot timer for the delete confirmation: `callback` runs after `ms`, and
// returns its own cancel handle so a second click can stop the clock.
export function after(ms, callback) {
  const handle = setTimeout(callback, ms);
  return () => clearTimeout(handle);
}
