//// The dial state machine, client-side (PLAN-daily-puzzles.md §3 Q19/Q20,
//// phase 4b).
////
//// PORTED from fourier_toy/puzzle.gleam — the same four dial kinds, the same
//// step sizes, the same clamps:
////   k      ±1, clamped to ±16
////   phase  ±5°, wrapping 0..360
////   radius ±2% of the shape's biggest dialable radius, clamped 0..200%
////   fixed  never moves
//// The numbers are the toy's player experience; the editor must test-play the
//// same controls the player gets, so they are ported rather than re-invented.
////
//// What is NOT ported: the roster of setups (P6..P10). The admin has no roster
//// — a puzzle's dial arrangement arrives with its fixture (`dials`), and the
//// ONE thing this module keeps from the roster is the shipped puzzle's starting
//// perturbation (`standard_patches`: the toy's p6 row), which is where the
//// editor's test play begins. `initial` applies patches by SLOT, so a fixture
//// whose arrangement differs still gets phase/radius/k perturbations in the
//// right places, and a `fixed` slot stays at truth.

import admin_ui/score.{type Term, Term}
import gleam/float
import gleam/int
import gleam/list

pub type Kind {
  KindPhase
  KindRadius
  KindK
  KindFixed
}

/// One starting perturbation for a slot; unpatched fields stay at truth.
pub type Patch {
  PhaseDeg(Float)
  RPct(Float)
  KSet(Int)
  Keep
}

pub const k_min = -16

pub const k_max = 16

/// The wire spellings (fixture_json.gleam) — the same four words.
pub fn parse_kind(name: String) -> Result(Kind, Nil) {
  case name {
    "phase" -> Ok(KindPhase)
    "radius" -> Ok(KindRadius)
    "k" -> Ok(KindK)
    "fixed" -> Ok(KindFixed)
    _ -> Error(Nil)
  }
}

pub fn name_of(kind: Kind) -> String {
  case kind {
    KindPhase -> "phase"
    KindRadius -> "radius"
    KindK -> "k"
    KindFixed -> "fixed"
  }
}

pub fn k_step(term: Term, dir: Int) -> Term {
  let k = term.k + dir
  case k < k_min || k > k_max {
    True -> term
    False -> Term(k, term.radius, term.phase_deg)
  }
}

pub fn phase_step(term: Term, dir: Int) -> Term {
  Term(term.k, term.radius, mod360(term.phase_deg +. int.to_float(dir * 5)))
}

pub fn radius_step(term: Term, dir: Int, max_r: Float) -> Term {
  let unit = 0.02 *. max_r
  let r = term.radius +. int.to_float(dir) *. unit
  let capped = case r <. 0.0 {
    True -> 0.0
    False ->
      case r >. 2.0 *. max_r {
        True -> 2.0 *. max_r
        False -> r
      }
  }
  Term(term.k, capped, term.phase_deg)
}

/// Apply one step to a slot governed by `kind`.
pub fn step(kind: Kind, term: Term, dir: Int, max_r: Float) -> Term {
  case kind {
    KindPhase -> phase_step(term, dir)
    KindRadius -> radius_step(term, dir, max_r)
    KindK -> k_step(term, dir)
    KindFixed -> term
  }
}

/// The editor's FALLBACK start (fourier_toy's P6 row: phase 0°, radius 72% of
/// the biggest dialable radius, k 8, fourth slot untouched).
///
/// A puzzle saved since the patches field exists carries its own start with its
/// fixture (`wire.Fixture.patches`) and this is not consulted — the derived start
/// is the one the toy boots with, and the editor test-plays that. Kept for rows
/// stored before the field: they have no start to read, and an old row that
/// cannot test-play would be worse than one that test-plays the old way.
pub fn standard_patches() -> List(Patch) {
  [PhaseDeg(0.0), RPct(72.0), KSet(8), Keep]
}

/// Apply starting patches to a fixture's dial truth, slot by slot.
///
/// `fixed` slots consume no patch and stay at truth (nothing may move them),
/// so the p6 row's trailing `Keep` is redundant by design — the arrangement and
/// the roster row agree, and a future arrangement that reorders slots still
/// gets its phase/radius/k perturbations in the right places.
pub fn initial(
  dial: List(Term),
  kinds: List(Kind),
  patches: List(Patch),
) -> List(Term) {
  apply_slots(kinds, dial, patches, max_radius(dial))
}

fn apply_slots(
  kinds: List(Kind),
  dial: List(Term),
  patches: List(Patch),
  max_r: Float,
) -> List(Term) {
  case kinds, dial {
    [kind, ..kinds_rest], [truth, ..dial_rest] -> {
      let #(patched, patches_rest) = case kind, patches {
        KindFixed, _ -> #(truth, patches)
        _, [patch, ..rest] -> #(apply_patch(patch, truth, max_r), rest)
        _, [] -> #(truth, [])
      }
      [patched, ..apply_slots(kinds_rest, dial_rest, patches_rest, max_r)]
    }
    _, _ -> []
  }
}

fn apply_patch(patch: Patch, truth: Term, max_r: Float) -> Term {
  case patch {
    PhaseDeg(deg) -> Term(truth.k, truth.radius, deg)
    RPct(pct) -> Term(truth.k, 0.01 *. pct *. max_r, truth.phase_deg)
    KSet(k) -> Term(k, truth.radius, truth.phase_deg)
    Keep -> truth
  }
}

/// The biggest dialable radius — the radius dial's unit and the 200% ceiling.
pub fn max_radius(terms: List(Term)) -> Float {
  list.fold(terms, 0.0, fn(acc, term) {
    case term.radius >. acc {
      True -> term.radius
      False -> acc
    }
  })
}

pub fn mod360(x: Float) -> Float {
  case x <. 0.0, x >=. 360.0 {
    True, _ -> mod360(x +. 360.0)
    False, True -> mod360(x -. 360.0)
    False, False -> x
  }
}

// ---------- display formatting (ported from fourier_toy/puzzle.gleam) ----------

pub fn fmt_k(k: Int) -> String {
  case k < 0 {
    True -> "−" <> int.to_string(int.absolute_value(k))
    False -> "+" <> int.to_string(k)
  }
}

fn pct(r: Float, max_r: Float) -> String {
  case max_r >. 0.0 {
    True -> int.to_string(float.round(r /. max_r *. 100.0)) <> "%"
    False -> "—"
  }
}

fn deg(d: Float) -> String {
  int.to_string(float.round(d)) <> "°"
}

/// The value shown in a dial row's readout.
pub fn slot_value(kind: Kind, term: Term, max_r: Float) -> String {
  case kind {
    KindPhase -> deg(term.phase_deg)
    KindRadius -> pct(term.radius, max_r)
    KindK -> "k " <> fmt_k(term.k)
    KindFixed -> "not a dial"
  }
}

/// The fixture's own numbers for one slot, on one line. The authoring view
/// prints these before a save (plan Q2/Q3: "the derived truths are shown before
/// save"), so what the derivation decided is visible rather than inferred from
/// the board — and the words match the dial row's, so the readout and the
/// stepper cannot drift apart.
pub fn truth_text(term: Term, max_r: Float) -> String {
  "r "
  <> pct(term.radius, max_r)
  <> " · φ "
  <> deg(term.phase_deg)
  <> " · k "
  <> fmt_k(term.k)
}

/// The row's small print: what this slot does NOT let you change.
pub fn locked_note(kind: Kind, term: Term, max_r: Float) -> String {
  case kind {
    KindPhase ->
      "locked: r " <> pct(term.radius, max_r) <> " · k " <> fmt_k(term.k)
    KindRadius ->
      "locked: k " <> fmt_k(term.k) <> " · φ " <> deg(term.phase_deg)
    KindK ->
      "locked: r " <> pct(term.radius, max_r) <> " · φ " <> deg(term.phase_deg)
    KindFixed ->
      "fixed, correct: k "
      <> fmt_k(term.k)
      <> " · r "
      <> pct(term.radius, max_r)
      <> " · φ "
      <> deg(term.phase_deg)
  }
}

/// One-decimal match display — the toy's fmt1, ported: round to tenths, then
/// let float.to_string print it (which keeps the trailing `.0` on whole
/// numbers, the stdlib 1.x behaviour the toys already show).
pub fn fmt1(m: Float) -> String {
  float.to_string(int.to_float(float.round(m *. 10.0)) /. 10.0)
}
