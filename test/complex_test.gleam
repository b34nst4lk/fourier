import approx
import complex
import gleeunit/should

pub fn add_test() {
  let a = complex.Complex(1.0, 2.0)
  let b = complex.Complex(3.0, 4.0)
  should.equal(complex.add(a, b), complex.Complex(4.0, 6.0))
}

pub fn i_squared_is_minus_one_test() {
  let i = complex.Complex(0.0, 1.0)
  should.equal(complex.mul(i, i), complex.Complex(-1.0, 0.0))
}

pub fn magnitude_3_4_is_5_test() {
  approx.be_close(
    complex.magnitude(complex.Complex(3.0, 4.0)),
    5.0,
    0.000_000_001,
  )
}

pub fn argument_of_1_plus_i_test() {
  approx.be_close(
    complex.argument(complex.Complex(1.0, 1.0)),
    0.785_398_163,
    0.000_001,
  )
}

pub fn polar_rect_roundtrip_test() {
  let c = complex.Complex(-2.5, 1.75)
  let rebuilt = complex.polar(complex.magnitude(c), complex.argument(c))
  approx.be_close(rebuilt.re, -2.5, 0.000_000_001)
  approx.be_close(rebuilt.im, 1.75, 0.000_000_001)
}

pub fn exp_i_zero_is_one_test() {
  should.equal(complex.exp_i(0.0), complex.Complex(1.0, 0.0))
}

pub fn exp_i_quarter_turn_test() {
  let rotated = complex.exp_i(1.570_796_327)
  approx.be_close(rotated.re, 0.0, 0.000_001)
  approx.be_close(rotated.im, 1.0, 0.000_001)
}

pub fn from_xy_matches_constructor_test() {
  should.equal(complex.from_xy(-0.5, 3.25), complex.Complex(-0.5, 3.25))
}
