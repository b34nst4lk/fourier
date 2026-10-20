//// Scaffold smoke tests: prove the fourier_sketch math-core path dependency
//// links and runs on the JavaScript target. NOT product logic — real suites
//// land per phase (RED→GREEN per docs/PLAN.md).

import complex
import dft
import gleam/float
import gleam/list
import gleeunit
import gleeunit/should
import terms

pub fn main() {
  gleeunit.main()
}

pub fn dep_smoke_complex_arithmetic_test() {
  complex.mul(complex.exp_i(0.0), complex.from_xy(3.0, 4.0))
  |> complex.to_xy
  |> should.equal(#(3.0, 4.0))
}

pub fn dep_smoke_terms_pipeline_test() {
  // ≥3 dots required by the terms gate (PLAN #11 contract).
  let dots = [#(1.0, 0.0), #(0.0, 1.0), #(-1.0, 0.0)]
  let computed = terms.compute(dots, 8, 8)

  computed
  |> list.is_empty
  |> should.be_false

  // The chain pose at t=0 with the FULL term set reproduces the start of the
  // path — every term is exp(0)·c_k summed, i.e. the first resampled point.
  // (Radius/phase round-trips through polar/argument cost a few ulps, so
  // assert coordinate-wise with a tolerance, not exact equality.)
  let pose = terms.position_at(computed, 0.0)
  should.be_true(float.absolute_value({ pose.0 -. 1.0 }) <. 0.000_000_001)
  should.be_true(float.absolute_value(pose.1) <. 0.000_000_001)
}

pub fn dep_smoke_dft_signed_k_test() {
  // Four samples tracing one full CCW unit circle: the exact spectrum is
  // c_1 = 1, all other signed-k coefficients = 0.
  let samples = [#(1.0, 0.0), #(0.0, 1.0), #(-1.0, 0.0), #(0.0, -1.0)]
  let forward = dft.forward(samples)

  forward
  |> list.filter(fn(pair) { pair.0 == 1 })
  |> list.map(fn(pair) { complex.magnitude(pair.1) })
  |> should.equal([1.0])

  forward
  |> list.filter(fn(pair) { pair.0 == -1 })
  |> list.map(fn(pair) { complex.magnitude(pair.1) })
  |> list.each(fn(mag) { should.be_true(mag <. 0.000_000_001) })
}
