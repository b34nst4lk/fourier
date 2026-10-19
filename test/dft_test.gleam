import complex
import dft
import gleam/float
import gleam/int
import gleam/list
import gleeunit/should
import resample

const pi = 3.141_592_653_589_793

fn circle(n: Int, radius: Float, clockwise: Bool) -> List(#(Float, Float)) {
  let dir = case clockwise {
    True -> -1.0
    False -> 1.0
  }
  list.range(0, n - 1)
  |> list.map(fn(i) {
    let t = 2.0 *. pi *. { int.to_float(i) /. int.to_float(n) }
    let a = dir *. t
    #(radius *. float.cos(a), radius *. float.sin(a))
  })
}

fn coeff_for(terms: List(#(Int, complex.Complex)), k: Int) -> complex.Complex {
  case list.key_find(terms, k) {
    Ok(c) -> c
    Error(_) -> complex.Complex(0.0, 0.0)
  }
}

fn flat_mag(samples: List(#(Float, Float))) -> Float {
  list.fold(samples, 0.0, fn(acc, p) {
    let m = complex.magnitude(complex.from_xy(p.0, p.1))
    acc +. { m *. m }
  })
}

fn spectrum_energy(terms: List(#(Int, complex.Complex))) -> Float {
  list.fold(terms, 0.0, fn(acc, t) {
    let m = complex.magnitude(t.1)
    acc +. { m *. m }
  })
}

fn worst_pair_error(
  a: List(#(Float, Float)),
  b: List(#(Float, Float)),
) -> Float {
  list.map2(a, b, fn(x, y) {
    complex.magnitude(complex.from_xy({ x.0 -. y.0 }, { x.1 -. y.1 }))
  })
  |> list.fold(0.0, fn(acc, e) {
    case e >. acc {
      True -> e
      False -> acc
    }
  })
}

pub fn term_count_matches_sample_count_test() {
  let terms = dft.forward(circle(32, 1.0, False))
  should.equal(list.length(terms), 32)
}

pub fn pure_circle_lands_in_k_1_test() {
  let terms = dft.forward(circle(64, 2.0, False))
  let c1 = coeff_for(terms, 1)
  should.be_close(complex.magnitude(c1), 2.0, 0.000_001)
  // phase 0: the path starts at (2, 0)
  should.be_close(c1.re, 2.0, 0.000_001)
  should.be_close(c1.im, 0.0, 0.000_001)
}

pub fn reversed_circle_lands_in_minus_1_test() {
  let terms = dft.forward(circle(64, 2.0, True))
  should.be_close(
    complex.magnitude(coeff_for(terms, -1)),
    2.0,
    0.000_001,
  )
  should.be_close(complex.magnitude(coeff_for(terms, 1)), 0.0, 0.000_001)
}

pub fn constant_offset_is_pure_dc_test() {
  let terms = dft.forward(list.repeat(#(5.0, 3.0), 16))
  let dc = coeff_for(terms, 0)
  should.be_close(dc.re, 5.0, 0.000_001)
  should.be_close(dc.im, 3.0, 0.000_001)
  let rest = list.fold(terms, 0.0, fn(acc, t) {
    case t.0 == 0 {
      True -> acc
      False -> acc +. complex.magnitude(t.1)
    }
  })
  should.be_close(rest, 0.0, 0.000_001)
}

pub fn zero_path_is_zero_spectrum_test() {
  let terms = dft.forward(list.repeat(#(0.0, 0.0), 16))
  should.be_true(
    list.all(terms, fn(t) { complex.magnitude(t.1) <. 0.000_000_001 }),
  )
}

pub fn roundtrip_test() {
  let pentagon = [
    #(4.0, 0.0),
    #(0.5, 1.2),
    #(0.0, 3.0),
    #(-1.5, 2.2),
    #(-2.0, -0.5),
    #(0.5, -1.8),
  ]
  let n = 120
  let samples = resample.resample_closed(pentagon, n)
  let rebuilt = samples |> dft.forward |> dft.inverse(n)
  should.be_true(worst_pair_error(samples, rebuilt) <. 0.000_000_001)
}

pub fn parseval_test() {
  let pentagon = [
    #(4.0, 0.0),
    #(0.5, 1.2),
    #(0.0, 3.0),
    #(-1.5, 2.2),
    #(-2.0, -0.5),
    #(0.5, -1.8),
  ]
  let n = 64
  let samples = resample.resample_closed(pentagon, n)
  let terms = dft.forward(samples)
  // discrete Parseval: sum |p_n|^2 == N * sum |c_k|^2
  should.be_close(
    flat_mag(samples),
    { int.to_float(n) *. spectrum_energy(terms) },
    0.000_001,
  )
}