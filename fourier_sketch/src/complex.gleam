//// Minimal complex arithmetic for the Fourier math core.
//// A 2D point (x, y) is modelled as the complex number x + iy.
////
//// Trig and sqrt come through FFI (Erlang `math` / JS `Math`) because
//// gleam_stdlib 1.0 ships neither.
////

pub type Complex {
  Complex(re: Float, im: Float)
}

@external(erlang, "math", "cos")
@external(javascript, "./fourier_sketch_ffi.mjs", "cos")
fn cos(theta: Float) -> Float

@external(erlang, "math", "sin")
@external(javascript, "./fourier_sketch_ffi.mjs", "sin")
fn sin(theta: Float) -> Float

@external(erlang, "math", "atan2")
@external(javascript, "./fourier_sketch_ffi.mjs", "atan2")
fn atan2(y: Float, x: Float) -> Float

@external(erlang, "math", "sqrt")
@external(javascript, "./fourier_sketch_ffi.mjs", "sqrt")
fn sqrt(x: Float) -> Float

pub fn zero() -> Complex {
  Complex(0.0, 0.0)
}

pub fn from_xy(x: Float, y: Float) -> Complex {
  Complex(x, y)
}

pub fn to_xy(c: Complex) -> #(Float, Float) {
  #(c.re, c.im)
}

pub fn add(a: Complex, b: Complex) -> Complex {
  Complex({ a.re +. b.re }, { a.im +. b.im })
}

pub fn mul(a: Complex, b: Complex) -> Complex {
  Complex(
    { a.re *. b.re } -. { a.im *. b.im },
    { a.re *. b.im } +. { a.im *. b.re },
  )
}

pub fn scale(c: Complex, s: Float) -> Complex {
  Complex({ c.re *. s }, { c.im *. s })
}

pub fn magnitude(c: Complex) -> Float {
  sqrt({ c.re *. c.re } +. { c.im *. c.im })
}

/// Principal argument in (-pi, pi].
pub fn argument(c: Complex) -> Float {
  atan2(c.im, c.re)
}

/// Complex number with the given radius at the given angle (radians).
pub fn polar(r: Float, theta: Float) -> Complex {
  Complex({ r *. cos(theta) }, { r *. sin(theta) })
}

/// e^(i * theta)
pub fn exp_i(theta: Float) -> Complex {
  polar(1.0, theta)
}
