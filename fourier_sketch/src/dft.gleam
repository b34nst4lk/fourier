//// Forward and inverse 1D Discrete Fourier Transform over a closed path.
////
//// A 2D point (x, y) is treated as the complex number x + iy, so the DFT of
//// the path decomposes the drawing into rotating vectors (epicycles).
////
//// Convention (the contract encoded in tests — see docs/PLAN.md §3):
////   forward:  c_k = (1/N) * Σ_m p_m * e^(-2πi k m / N)
////   inverse:  p_m =        Σ_k c_k * e^(+2πi k m / N)
////
//// Coefficients are returned with **signed k**: for even N, k > N/2 folds to
//// k - N, so the spectrum runs from -N/2 (exclusive) through N/2. Negative k
//// means the circle spins clockwise.

import complex
import gleam/int
import gleam/list
import util.{indices, pi}

// ---- forward DFT -----------------------------------------------------------
// Performance (bench: fourier_sketch/bench, decision #8 live recompute):
// the naive per-(k,m) exp_i costs ~2·N² trig calls (~7.7 ms at 512 points,
// 96% of the 8 ms budget before rendering). Instead we build ONE twiddle
// table w[m] = e^{−2πim/N} (N trig calls total) and, for each k, walk the
// samples with a multiplicatively rotating twiddle: tw_{m+1} = tw_m · w[k].
// Rotated-product rounding error over 511 steps ~1e−13, far inside the
// round-trip tolerance the tests enforce.

/// Forward DFT: N samples -> N terms with signed k.
pub fn forward(
  samples: List(#(Float, Float)),
) -> List(#(Int, complex.Complex)) {
  let n = list.length(samples)
  let nf = int.to_float(n)
  let pcx = list.map(samples, fn(p) { complex.from_xy(p.0, p.1) })
  let half = n / 2
  twiddle_table(n)
  |> list.index_map(fn(wk, k) {
    let sum = rotate_sum(pcx, wk, complex.zero(), complex.Complex(1.0, 0.0))
    let signed = case k > half {
      True -> k - n
      False -> k
    }
    #(signed, complex.scale(sum, 1.0 /. nf))
  })
}

fn rotate_sum(
  ps: List(complex.Complex),
  wk: complex.Complex,
  acc: complex.Complex,
  tw: complex.Complex,
) -> complex.Complex {
  case ps {
    [] -> acc
    [p, ..rest] ->
      rotate_sum(
        rest,
        wk,
        complex.add(acc, complex.mul(p, tw)),
        complex.mul(tw, wk),
      )
  }
}

/// w[m] = e^{−2πim/N} for m in 0..N-1 — N trig calls, shared by every k.
fn twiddle_table(n: Int) -> List(complex.Complex) {
  let nf = int.to_float(n)
  indices(n)
  |> list.map(fn(m) { complex.exp_i({ -2.0 *. pi *. int.to_float(m) } /. nf) })
}

/// Inverse DFT: signed-k terms -> reconstruction of the path sampled at
/// `n` points over one period.
/// Note: test-only at production scale (the canvas reconstructs analytically
/// from (k, radius, phase)) — the naive exp_i-per-use cost is fine here.
pub fn inverse(
  terms: List(#(Int, complex.Complex)),
  n: Int,
) -> List(#(Float, Float)) {
  let nf = int.to_float(n)
  indices(n)
  |> list.map(fn(m) {
    let s =
      list.fold(terms, complex.zero(), fn(acc, t) {
        let base = { 2.0 *. pi *. int.to_float(t.0) } /. nf
        complex.add(
          acc,
          complex.mul(t.1, complex.exp_i({ base *. int.to_float(m) })),
        )
      })
    #(s.re, s.im)
  })
}
