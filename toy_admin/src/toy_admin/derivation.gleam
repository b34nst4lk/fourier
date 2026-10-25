//// Fixture derivation (PLAN-daily-puzzles.md §3 Q2). Runs once, at save time:
//// dots are the source of truth and both the dots and this derived fixture are
//// stored, so a re-derive is always possible.
////
//// Pipeline (shared with the toys — the core is fourier_sketch's, never a
//// fork): dots -> 512-point arc-length resample -> forward DFT with signed k.
//// Then:
////   - k = 0        -> the centroid (the DC term: the shape's offset)
////   - top-4 by |c_k|, k != 0 -> the dial truth (what the player may turn)
////   - every other k != 0     -> fixed extras (baked into target and synthesis)
////   - the resampled points   -> the 512-point target trace
////
//// Units are dial-facing, matching the toy's TermState: radius in sketch units
//// (0..100 space), phase in degrees 0..360 (the DFT's argument is radians in
//// (−π, π]).
////
//// The trace is the resample itself, not a second inverse DFT: the full
//// spectrum reconstructs exactly those samples (dft.inverse(forward(samples))
//// == samples), so paying for an O(N²) inverse here would buy nothing.
//// derive_test pins that claim by rebuilding the trace from centroid + dial +
//// extras.

import complex
import dft
import gleam/int
import gleam/list
import gleam/order
import resample
import sketch.{type Dot}
import util.{pi}

/// The DFT size the toys use (fourier_toy/shapes.gleam n_samples).
pub const sample_count = 512

/// Four dials, the toy's standard board.
pub const dial_slots = 4

/// The dial arrangement (Q19): the fixture carries its own list so a future
/// experiment needs no format migration. v1 always emits the standard pattern
/// (phase / radius / k / fixed, in amplitude order).
pub type DialKind {
  DialPhase
  DialRadius
  DialK
  DialFixed
}

/// One synthesis row in dial-facing units.
pub type Dial {
  Dial(k: Int, radius: Float, phase_deg: Float)
}

pub type Fixture {
  Fixture(
    name: String,
    show_date: String,
    /// The k = 0 term's position: centroid + sum of terms.
    centroid: #(Float, Float),
    /// Always `standard_dial_arrangement()` in v1.
    dials: List(DialKind),
    /// The top-4 movables, amplitude-ordered.
    dial: List(Dial),
    /// The rest of the spectrum, amplitude-ordered and held fixed.
    extras: List(Dial),
    /// The 512-point comparison trace.
    target: List(#(Float, Float)),
  )
}

/// v1's dial pattern: slot 1 phase, slot 2 radius, slot 3 k, slot 4 fixed.
pub fn standard_dial_arrangement() -> List(DialKind) {
  [DialPhase, DialRadius, DialK, DialFixed]
}

/// The core's 3-dot gate (terms.compute), named for callers outside the
/// pipeline: a drawing with fewer than three dots has no polygon, so there is
/// nothing to derive. The admin route refuses to save such a drawing.
pub fn can_derive(dots: List(Dot)) -> Bool {
  list.length(dots) >= 3
}

/// True when derivation hit the gate: nothing renderable came out (empty dial,
/// extras and target). The admin's save check asks this of the FIXTURE rather
/// than counting dots a second time — the empty fixture is the observable.
pub fn is_degenerate(fixture: Fixture) -> Bool {
  fixture.dial == [] && fixture.extras == [] && fixture.target == []
}

/// Derive the fixture for a drawing. Below the core's 3-dot gate
/// (terms.compute) there is no spectrum: the result is empty rather than a
/// crash — the admin refuses to save such a drawing.
pub fn derive_fixture(
  dots: List(Dot),
  name: String,
  show_date: String,
) -> Fixture {
  case can_derive(dots) {
    False -> Fixture(name, show_date, #(0.0, 0.0), [], [], [], [])
    True -> {
      let samples = resample.resample_closed(dots, sample_count)
      let spectrum = dft.forward(samples)
      let centroid = case list.key_find(spectrum, 0) {
        Ok(coefficient) -> complex.to_xy(coefficient)
        Error(_) -> #(0.0, 0.0)
      }
      let rows =
        spectrum
        |> list.filter(fn(term) { term.0 != 0 })
        |> list.map(fn(term) {
          Dial(term.0, complex.magnitude(term.1), phase_deg(term.1))
        })
        |> list.sort(by_radius)
      let dial = list.take(rows, dial_slots)
      let dial_ks = list.map(dial, fn(row) { row.k })
      let extras = list.filter(rows, fn(row) { !list.contains(dial_ks, row.k) })
      Fixture(
        name,
        show_date,
        centroid,
        standard_dial_arrangement(),
        dial,
        extras,
        samples,
      )
    }
  }
}

/// The core's amplitude order (terms.by_amplitude): biggest radius first,
/// ties broken by |k| so the order is deterministic run to run.
fn by_radius(a: Dial, b: Dial) -> order.Order {
  case a.radius == b.radius {
    True -> int.compare(int.absolute_value(a.k), int.absolute_value(b.k))
    False ->
      case a.radius >. b.radius {
        True -> order.Lt
        False -> order.Gt
      }
  }
}

/// Radians (−π, π] -> dial degrees [0, 360).
fn phase_deg(coefficient: complex.Complex) -> Float {
  let degrees = complex.argument(coefficient) /. pi *. 180.0
  case degrees <. 0.0 {
    True -> degrees +. 360.0
    False -> degrees
  }
}
