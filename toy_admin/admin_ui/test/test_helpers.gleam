//// Float-closeness assertion with useful diagnostics (admin_ui is its own
//// package, so it cannot import toy_admin's test/helpers; this is the sibling
//// convention from fourier_sketch's tests).

import gleam/float
import gleeunit/should

pub fn close(actual: Float, expected: Float, tolerance: Float) -> Nil {
  let diff = float.absolute_value({ actual -. expected })
  case diff <=. tolerance {
    True -> Nil
    False ->
      should.equal(
        "expected "
          <> float.to_string(actual)
          <> " to be within "
          <> float.to_string(tolerance)
          <> " of "
          <> float.to_string(expected),
        "within tolerance",
      )
  }
}
