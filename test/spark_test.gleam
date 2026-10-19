import gleam/string
import gleeunit/should
import sketch
import spark
import terms

pub fn dot_term_flat_line_test() {
  // k = 0: constant x-projection at the wave's own peak (y = mid - amplitude)
  let p = spark.path(terms.Term(0, 1.0, 0.0))
  should.be_true(string.contains(p, "M0,2"))
  should.be_true(string.contains(p, "L35,2"))
  should.be_true(string.contains(p, ",2"))
}

pub fn phase_shift_moves_the_zero_crossing_test() {
  // phase = pi/2: cos(pi/2) = 0 at u = 0, so the wave starts at mid-height
  let p = spark.path(terms.Term(1, 1.0, 1.570_796_327))
  should.be_true(string.contains(p, "M0,8"))
}

pub fn no_phase_starts_at_peak_test() {
  let p = spark.path(terms.Term(1, 1.0, 0.0))
  should.be_true(string.contains(p, "M0,2"))
  // mid-height zero crossing at u = 0.25 -> x = 9
  should.be_true(string.contains(p, "9,8"))
}

pub fn signed_k_same_projection_at_zero_phase_test() {
  // at phi = 0 the x-projection is identical for +k and -k
  should.equal(
    spark.path(terms.Term(1, 1.0, 0.0)),
    spark.path(terms.Term(-1, 1.0, 0.0)),
  )
}

pub fn radius_is_normalised_per_row_test() {
  // shape depends on k and phase, not on the absolute radius
  should.equal(
    spark.path(terms.Term(3, 100.0, 0.5)),
    spark.path(terms.Term(3, 0.001, 0.5)),
  )
}

pub fn real_terms_produce_paths_test() {
  // integration sanity: every term of a real pipeline has a well-formed path
  let waves = terms.compute(sketch.star(), 64, 64)
  waves
  |> list_each(fn(t) {
    let p = spark.path(t)
    should.be_true(string.starts_with(p, "M0,"))
  })
}

fn list_each(items: List(terms.Term), check: fn(terms.Term) -> Nil) -> Nil {
  case items {
    [] -> Nil
    [t, ..rest] -> {
      check(t)
      list_each(rest, check)
    }
  }
}

pub fn format_float2_test() {
  should.equal(spark.format_float2(12.34), "12.34")
  should.equal(spark.format_float2(0.05), "0.05")
  should.equal(spark.format_float2(-1.239), "-1.24")
  should.equal(spark.format_float2(2.0), "2.00")
  should.equal(spark.format_float2(0.0), "0.00")
}
