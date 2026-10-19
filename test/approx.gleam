//// Float-closeness assertion, since gleeunit 1.11 dropped should.be_close.

import gleam/float
import gleeunit/should

pub fn be_close(actual: Float, expected: Float, tolerance: Float) -> Nil {
  let diff = float.absolute_value({ actual -. expected })
  should.be_true(diff <=. tolerance)
}
