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
////
//// Starting patches (PLAN-varied-starts §1/§2: the per-puzzle draw)
//// -----------------------------------------------------------------
//// A daily puzzle never opens at truth — the player's job is to walk four
//// perturbed dials back onto it. The vocabulary is four constructors, one per
//// dial slot (unchanged):
////
////   Patch = PhaseDeg(Float) | RPct(Float) | KSet(Int) | Keep
////
//// Since 2026-10-27 the perturbation is DRAWN per puzzle at save time, so no
//// two days open the same way (the retired fixed start — +90°, k −2 — was the
//// shipped quaver's own, and a returning player learned the recipe instead of
//// solving: rotate −90, add 2). The draw is a pure function of the puzzle: a
//// hash over the dial truth, which derives deterministically from the drawing.
//// No RNG state, no OTP entropy, no per-player anything — and the result is
//// stored in the fixture, so every player of that day starts identically.
////
////   seed = fnv1a(dial rows flattened as ints)
////          per row [k, round(radius × 1e6), round(phase_deg × 100)]
////
////   slot 1 (phase)   PhaseDeg(snap5(truth_phase + offset)),
////                    offset = 45 + 5·(seed mod 55) — 45°..315° in 5° steps:
////                    at least a 45° turn from truth either direction (315° is
////                    −45°), never a whole circle, always step-able. NB: the snap
////                    runs AFTER the offset is added, and the truth phase itself
////                    is off-grid, so the OBSERVED turn can land at 42.5° — the
////                    plan's amended floor (PLAN-varied-starts §1 decision 2)
////   slot 2 (radius)  RPct(73.0) — 73% of dial_max_r: THE anchor the ring's
////                    meaning is built on. Not flagged by the playtest, not
////                    varied.
////   slot 3 (k)       KSet(truth_k + shift), shift = k_shifts((seed / 55) mod 6)
////                    over {−3,−2,−1,+1,+2,+3}: always moves, never far. A
////                    shift that would fall below k_min (−16) flips sign
////                    instead of clamping, so the player always has room to
////                    step back.
////   slot 4 (fixed)   Keep — a fixed term is already correct, and the player
////                    cannot turn it anyway
////
//// Why snap to 5°: the phase dial steps in 5°, so an off-grid start could never
//// be stepped onto. Why the radius is NOT drawn: it is the one dial whose
//// meaning is fixed by the ring, and the playtest's complaint was the recipe,
//// not the difficulty.
////
//// The toy's quaver FALLBACK keeps its own fixed start (it is not part of the
//// daily sequence, fourier_toy/puzzle.gleam p9); served dailies no longer
//// reproduce it, by design.
////
//// Patches are resolved against the SHAPE, not baked here: RPct is a percentage
//// of the shape's biggest dialable radius and KSet is an absolute kind. The toy
//// resolves them (fourier_toy/puzzle.initial); the wire shape is documented in
//// fixture_json.

import complex
import dft
import gleam/float
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
    /// The deterministic start, one patch per dial slot (see the header).
    patches: List(Patch),
    /// The 512-point comparison trace.
    target: List(#(Float, Float)),
  )
}

/// How one dial slot starts, before the player touches it (see the header for
/// the formula). Resolved against the shape by the toy: `RPct` is a percentage
/// of the biggest dialable radius, not a unit length.
pub type Patch {
  PhaseDeg(Float)
  RPct(Float)
  KSet(Int)
  Keep
}

/// The dial's lower k bound (fourier_toy/puzzle.gleam k_min): the k shift
/// flips rather than pushes a slot outside the dial.
pub const k_min = -16

/// The start's constant parts, named so a test can point at them: the radius
/// anchor (never drawn) and the pool the k shift is drawn from (never zero).
pub const start_radius_pct = 73.0

/// §1 decision 3: the k shifts the draw may pick from — nonzero on purpose.
pub const k_shifts = [-3, -2, -1, 1, 2, 3]

/// §1 decision 2: the phase offset's draw space — 45° + 5·idx for
/// idx in 0..54, i.e. 45°..315° in 5° steps (315° ≡ −45°).
pub const phase_offset_min_deg = 45

pub const phase_offset_steps = 55

// FNV-1a, 32-bit (the classic parameters). The hash runs over the flattened
// dial, so its byte representation is part of the contract: the draw for a
// given drawing must never drift between saves or machines.
const fnv_offset_basis = 2_166_136_261

const fnv_prime = 16_777_619

const two_32 = 4_294_967_296

/// The puzzle's draw seed: FNV-1a over the dial rows flattened as ints, per
/// row `[k, round(radius × 1e6), round(phase_deg × 100)]`.
///
/// The floats are scaled onto an integer grid because a hash needs bytes, and
/// the scale is deliberately finer than the numbers are meaningful: the dial
/// is a derived truth, so two different drawings must not collide on a
/// rounded-away digit. The dial itself is deterministic (sorted by amplitude,
/// ties by |k|), so the seed is a pure function of the puzzle — no RNG, no
/// clock, no OTP.
pub fn dial_seed(dial: List(Dial)) -> Int {
  dial
  |> list.flat_map(fn(row) {
    [
      row.k,
      float.round(row.radius *. 1_000_000.0),
      float.round(row.phase_deg *. 100.0),
    ]
  })
  |> list.fold(fnv_offset_basis, fn(hash, value) {
    list.fold(unsigned_bytes(value), hash, fn(hash, byte) {
      { int.bitwise_exclusive_or(hash, byte) * fnv_prime } % two_32
    })
  })
}

/// The four bytes of an int's unsigned 32-bit two's-complement form, low byte
/// first (a negative k hashes as itself, never as a clamped zero).
fn unsigned_bytes(value: Int) -> List(Int) {
  let remainder = value % two_32
  let unsigned = case remainder < 0 {
    True -> remainder + two_32
    False -> remainder
  }
  [
    unsigned % 256,
    unsigned / 256 % 256,
    unsigned / 65_536 % 256,
    unsigned / 16_777_216 % 256,
  ]
}

/// §1 decision 2: the phase turn the seed draws, in degrees (45..315, 5° steps).
pub fn phase_offset_deg(seed: Int) -> Int {
  phase_offset_min_deg + { 5 * { seed % phase_offset_steps } }
}

/// §1 decision 3: the k shift the seed draws — one of `k_shifts`, never zero.
/// The draw is `(seed / 55) mod 6`, i.e. the seed's next base-55 digit, so the
/// phase and the k draws are independent slices of the same hash.
pub fn drawn_k_shift(seed: Int) -> Int {
  let index = { seed / phase_offset_steps } % list.length(k_shifts)
  case list.drop(k_shifts, index) {
    [shift, ..] -> shift
    [] -> panic as "k_shifts is indexed out of range"
  }
}

/// The generalized wall flip: the shift applies, unless it would push the slot
/// below `k_min` (−16) — then it flips sign instead of clamping, so the player
/// always has room to step back to truth.
pub fn shifted_k(truth_k: Int, shift: Int) -> Int {
  let shifted = truth_k + shift
  case shifted < k_min {
    True -> truth_k - shift
    False -> shifted
  }
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
    False -> Fixture(name, show_date, #(0.0, 0.0), [], [], [], [], [])
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
        varied_patches(dial),
        samples,
      )
    }
  }
}

/// The starting patches for a derived dial, in slot order — the per-puzzle
/// draw (see the header for the formula).
///
/// Public so the vocabulary is observable outside the pipeline and so the k
/// wall at `k_min` can be tested without hunting for a drawing that lands on
/// it.
pub fn varied_patches(dial: List(Dial)) -> List(Patch) {
  case dial {
    [] -> []
    [phase_slot, _radius_slot, k_slot, _fixed_slot, ..rest] -> {
      let _ = rest
      let seed = dial_seed(dial)
      [
        PhaseDeg(snap5(
          phase_slot.phase_deg +. int.to_float(phase_offset_deg(seed)),
        )),
        RPct(start_radius_pct),
        KSet(shifted_k(k_slot.k, drawn_k_shift(seed))),
        Keep,
      ]
    }
    // A short dial (only reachable below the 3-dot gate, which yields an empty
    // dial) has nothing to perturb per slot: emit what the slots we have can
    // express, and let the toy refuse anything but four.
    short -> list.map(short, fn(_row) { Keep })
  }
}

/// Snap to the dial's 5° grid, [0, 360) — the same grid the toy's phase row
/// steps along (fourier_toy/shapes.snap5).
pub fn snap5(degrees: Float) -> Float {
  mod360(int.to_float(float.round(degrees /. 5.0)) *. 5.0)
}

fn mod360(degrees: Float) -> Float {
  case degrees <. 0.0 {
    True -> mod360(degrees +. 360.0)
    False ->
      case degrees >=. 360.0 {
        True -> mod360(degrees -. 360.0)
        False -> degrees
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
