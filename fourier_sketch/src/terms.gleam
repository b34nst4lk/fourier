//// The live pipeline as a pure module: closed polygon -> arc-length resample
//// -> forward DFT -> (k, radius, phase) rows sorted by radius descending.
////
//// One row is one epicycle: c_k = radius * e^{i·phase}, spinning at k laps
//// per period (negative k = clockwise). This is the shape of both the panel-3
//// table and the panel-2 animation, per docs/PLAN.md §1 rows 4/16.
////
//// The 3-dot gate lives here (decision #11): below it the pipeline is empty.

import complex
import dft
import gleam/int
import gleam/list
import gleam/order
import resample
import sketch.{type Dot}
import util.{pi}

pub type Term {
  Term(k: Int, radius: Float, phase: Float)
}

/// Run the full pipeline. `keep_terms` truncates the sorted list; pass a
/// number >= sample_count for everything.
pub fn compute(
  dots: List(Dot),
  sample_count: Int,
  keep_terms: Int,
) -> List(Term) {
  case list.length(dots) >= 3 {
    False -> []
    True -> {
      let samples = resample.resample_closed(dots, sample_count)
      samples
      |> dft.forward
      |> list.map(fn(t) {
        Term(t.0, complex.magnitude(t.1), complex.argument(t.1))
      })
      |> list.sort(by_amplitude)
      |> list.take(keep_terms)
    }
  }
}

fn by_amplitude(a: Term, b: Term) -> order.Order {
  case { a.radius == b.radius } {
    True -> int.compare(int.absolute_value(a.k), int.absolute_value(b.k))
    False ->
      case a.radius >. b.radius {
        True -> order.Lt
        False -> order.Gt
      }
  }
}

/// The epicycle chain tip at period time t in 0..1:
/// sum of radius * e^{i(2 pi k t + phase)} — exactly what the canvas draws.
/// Public for the test suite and the sibling smoke — the app itself draws
/// the chain analytically in JS and never calls this.
pub fn position_at(terms: List(Term), t: Float) -> Dot {
  let sum =
    list.fold(terms, complex.zero(), fn(acc, term) {
      complex.add(acc, term_at(term, t))
    })
  complex.to_xy(sum)
}

fn term_at(term: Term, t: Float) -> complex.Complex {
  complex.polar(
    term.radius,
    { 2.0 *. pi *. int.to_float(term.k) *. t } +. term.phase,
  )
}
