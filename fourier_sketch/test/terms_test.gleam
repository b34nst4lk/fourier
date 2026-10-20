import approx
import gleam/list
import gleeunit/should
import resample
import sketch
import terms

const samples = 64

pub fn star_full_count_test() {
  let t = terms.compute(sketch.star(), samples, 1000)
  should.equal(list.length(t), samples)
}

pub fn empty_or_degenerate_dots_give_empty_terms_test() {
  should.equal(terms.compute([], samples, 1000), [])
  should.equal(terms.compute([#(0.0, 0.0), #(1.0, 1.0)], samples, 1000), [])
}

pub fn sorted_by_radius_descending_test() {
  should.be_true(sorted_desc(terms.compute(sketch.star(), samples, 1000)))
}

fn sorted_desc(ts: List(terms.Term)) -> Bool {
  case ts {
    [a, b, ..rest] ->
      case { a.radius >=. b.radius } {
        True -> sorted_desc([b, ..rest])
        False -> False
      }
    _ -> True
  }
}

pub fn truncation_takes_top_slice_test() {
  let full = terms.compute(sketch.star(), samples, 1000)
  let top8 = terms.compute(sketch.star(), samples, 8)
  should.equal(list.length(top8), 8)
  should.equal(top8, list.take(full, 8))
}

pub fn dc_term_carries_the_centroid_test() {
  // star is centred near (50,50) in sketch space, so |c_0| is large
  let dc =
    terms.compute(sketch.star(), samples, 1000)
    |> list.find(fn(t) { t.k == 0 })
  let dc = case dc {
    Ok(t) -> t
    Error(_) -> terms.Term(0, 0.0, 0.0)
  }
  should.be_true(dc.radius >. 40.0)
}

pub fn chain_tip_at_zero_equals_first_sample_test() {
  // p_m = Sigma_k c_k e^{2 pi i k m / N}, so at m = 0:
  // Sigma_k c_k == first resampled sample, EXACTLY (up to float error)
  let dots = sketch.heart()
  let first_sample =
    resample.resample_closed(dots, samples)
    |> list.first
  let assert Ok(first_sample) = first_sample
  let tip = terms.position_at(terms.compute(dots, samples, 1000), 0.0)
  approx.be_close(tip.0, first_sample.0, 0.000_000_001)
  approx.be_close(tip.1, first_sample.1, 0.000_000_001)
}

pub fn position_at_half_period_test() {
  // p_{N/2} for a full term list must equal the midpoint sample
  let dots = sketch.wobble()
  let mid =
    resample.resample_closed(dots, samples)
    |> list.drop(samples / 2)
    |> list.first
  let assert Ok(mid) = mid
  let tip = terms.position_at(terms.compute(dots, samples, 1000), 0.5)
  approx.be_close(tip.0, mid.0, 0.000_000_001)
  approx.be_close(tip.1, mid.1, 0.000_000_001)
}

// ---- csv export (RED first) ------------------------------------------------

pub fn to_csv_header_and_rows_test() {
  let rows = [
    terms.Term(0, 12.5, 0.25),
    terms.Term(-3, 4.0, 3.5),
    terms.Term(7, 0.5, -2.0),
  ]
  terms.to_csv(rows)
  |> should.equal("k,radius,phase\n0,12.5,0.25\n-3,4.0,3.5\n7,0.5,-2.0")
}

pub fn to_csv_empty_is_header_only_test() {
  terms.to_csv([])
  |> should.equal("k,radius,phase")
}

// ---- selection lookup (RED first) ------------------------------------------

pub fn index_of_k_finds_amplitude_sorted_position_test() {
  let rows = [
    terms.Term(5, 9.0, 0.0),
    terms.Term(-2, 3.0, 0.0),
    terms.Term(1, 0.5, 0.0),
  ]
  terms.index_of_k(rows, -2)
  |> should.equal(1)
  terms.index_of_k(rows, 1)
  |> should.equal(2)
}

pub fn index_of_k_missing_is_sentinel_test() {
  terms.index_of_k([terms.Term(3, 1.0, 0.0)], 9)
  |> should.equal(-1)
  terms.index_of_k([], 3)
  |> should.equal(-1)
}
