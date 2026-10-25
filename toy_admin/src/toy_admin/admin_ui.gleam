//// The embedded admin UI (PLAN-daily-puzzles.md §3 Q18, phase 4b).
////
//// The admin UI is a Lustre app (toy_admin/admin_ui/) in its own Gleam package,
//// built to ONE self-contained HTML file by scripts/build-admin-ui.sh and baked
//// into this image at priv/admin.html (the Dockerfile's `ui` stage). The server
//// serves those bytes unchanged at /api/admin — no templating, no decoding, no
//// per-request file read. The single-file rule is the house's (§3 Q18); the blog
//// route stays the escape hatch if embedding ever chafes.
////
//// Why the file is read ONCE, at boot (main → load): the bundle is a build
//// artifact of the container, not data. It cannot change while the process runs,
//// so a per-request read would buy nothing but a syscall and a new failure mode
//// ("the page works, then stops working") — and a missing bundle is a broken
//// BUILD, which belongs in the boot log, not in an intermittent 500. The route
//// still answers 500 if the boot read found nothing, because a server without
//// an admin page must say so rather than serve an empty document.
////
//// The bytes are served verbatim, including the doctype and the trailing
//// newline: the bundle is a complete document that esbuild already minified and
//// inlined, and anything this module "improved" would be a second, invisible
//// source of truth for the page.

import gleam/option.{type Option}
import simplifile
import wisp

/// Where the build lands the bundle, relative to the image's /app (the Dockerfile
/// `ui` stage writes /app/priv/admin.html, and wisp/mist run from /app).
pub const bundle_path = "priv/admin.html"

/// The boot read: the bundle's bytes, or `None` when the build never ran (or the
/// image was assembled without its `ui` stage). Never an error value: the caller
/// (toy_admin.load) logs once and the route answers 500.
pub fn load(path: String) -> Option(String) {
  case simplifile.read(path) {
    Ok(html) -> option.Some(html)
    Error(_) -> option.None
  }
}

/// The page, as the route answers it: the bundle's bytes as
/// `text/html; charset=utf-8`, or a plain 500 when the boot read failed.
pub fn page(bundle: Option(String)) -> wisp.Response {
  case bundle {
    option.Some(html) -> wisp.html_response(html, 200)
    option.None -> wisp.internal_server_error()
  }
}
