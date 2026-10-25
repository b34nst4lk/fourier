//// Float-closeness assertion with useful diagnostics.
//// (gleeunit 1.11 dropped `should.be_close`; the sketch's approx module is
//// the sibling convention. An `assert` failure prints the values in scope.)

import gleam/float

pub fn be_close(actual: Float, expected: Float, tolerance: Float) -> Nil {
  let diff = float.absolute_value({ actual -. expected })
  assert diff <=. tolerance
  Nil
}
