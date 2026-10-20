//// Arc-length resampling of a closed polygon.
////
//// The dot list defines a closed path (last dot connects to first). This
//// module converts it to `n` samples evenly spaced by distance along the
//// path — the precondition the DFT assumes: uniform sampling.
////
//// Degenerate inputs (single dot, all dots identical) produce flat lists —
//// never NaN and never a crash.

import gleam/int
import gleam/list

@external(erlang, "math", "sqrt")
@external(javascript, "./fourier_sketch_ffi.mjs", "sqrt")
fn sqrt(x: Float) -> Float

/// Index sequence [0, 1, .., n-1] — gleam_stdlib 1.0 has no list.range.
fn indices(n: Int) -> List(Int) {
  list.repeat(Nil, n)
  |> list.index_map(fn(_, i) { i })
}

/// An edge of the polygon: two consecutive vertices (already closed).
type Edge =
  #(#(Float, Float), #(Float, Float))

/// Resample the closed polygon defined by `dots` into `n` points evenly
/// spaced (by arc length) along the closed loop, starting at the first dot.
///
/// Returns an empty list if `n <= 0` or `dots` is empty.
pub fn resample_closed(
  dots: List(#(Float, Float)),
  n: Int,
) -> List(#(Float, Float)) {
  case n <= 0, dots {
    True, _ -> []
    _, [] -> []
    _, _ -> {
      let edges = polygon_edges(dots)
      let total = list.fold(edges, 0.0, fn(acc, e) { acc +. edge_len(e) })
      let step = total /. int.to_float(n)
      indices(n)
      |> list.map(fn(i) { sample_at(edges, { int.to_float(i) *. step }) })
    }
  }
}

fn polygon_edges(dots: List(#(Float, Float))) -> List(Edge) {
  let closed = case list.first(dots) {
    Ok(first) -> list.append(dots, [first])
    Error(_) -> dots
  }
  list.zip(closed, list.drop(closed, 1))
}

fn edge_len(edge: Edge) -> Float {
  let #(#(x1, y1), #(x2, y2)) = edge
  sqrt({ { x2 -. x1 } *. { x2 -. x1 } } +. { { y2 -. y1 } *. { y2 -. y1 } })
}

/// Point at distance `target` along the edge chain (cumulative from 0).
fn sample_at(edges: List(Edge), target: Float) -> #(Float, Float) {
  walk(edges, 0.0, target)
}

fn walk(edges: List(Edge), offset: Float, target: Float) -> #(Float, Float) {
  case edges {
    [] -> #(0.0, 0.0)
    [edge, ..rest] -> {
      let len = edge_len(edge)
      case target <=. { offset +. len } {
        True -> lerp(edge, len, { target -. offset })
        False -> walk(rest, { offset +. len }, target)
      }
    }
  }
}

/// Linear interpolation along an edge; zero-length edges return the start.
fn lerp(edge: Edge, len: Float, t: Float) -> #(Float, Float) {
  case len >. 0.0 {
    False -> edge.0
    True -> {
      let u = t /. len
      let #(#(x1, y1), #(x2, y2)) = edge
      #({ x1 +. { u *. { x2 -. x1 } } }, { y1 +. { u *. { y2 -. y1 } } })
    }
  }
}
