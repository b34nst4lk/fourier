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

const pi = 3.141_592_653_589_793

/// Index sequence [0, 1, .., n-1] — gleam_stdlib 1.0 has no list.range.
fn indices(n: Int) -> List(Int) {
  list.repeat(Nil, n)
  |> list.index_map(fn(_, i) { i })
}

/// Forward DFT: N samples -> N terms with signed k.
pub fn forward(
  samples: List(#(Float, Float)),
) -> List(#(Int, complex.Complex)) {
  let n = list.length(samples)
  let fn_ = int.to_float(n)
  let pcx = list.map(samples, fn(p) { complex.from_xy(p.0, p.1) })
  let half = n / 2
  indices(n)
  |> list.map(fn(k) {
    let base = { -2.0 *. pi *. int.to_float(k) } /. fn_
    let sum = go_sum(pcx, base, 0, complex.zero())
    let signed = case k > half {
      True -> k - n
      False -> k
    }
    #(signed, complex.scale(sum, 1.0 /. fn_))
  })
}

/// Inverse DFT: signed-k terms -> reconstruction of the path sampled at
/// `n` points over one period.
pub fn inverse(
  terms: List(#(Int, complex.Complex)),
  n: Int,
) -> List(#(Float, Float)) {
  let fn_ = int.to_float(n)
  indices(n)
  |> list.map(fn(m) {
    let s =
      list.fold(terms, complex.zero(), fn(acc, t) {
        let base = { 2.0 *. pi *. int.to_float(t.0) } /. fn_
        complex.add(
          acc,
          complex.mul(t.1, complex.exp_i({ base *. int.to_float(m) })),
        )
      })
    #(s.re, s.im)
  })
}

fn go_sum(
  ps: List(complex.Complex),
  base: Float,
  idx: Int,
  acc: complex.Complex,
) -> complex.Complex {
  case ps {
    [] -> acc
    [p, ..rest] -> {
      let twiddle = complex.exp_i({ base *. int.to_float(idx) })
      go_sum(rest, base, idx + 1, complex.add(acc, complex.mul(p, twiddle)))
    }
  }
}
