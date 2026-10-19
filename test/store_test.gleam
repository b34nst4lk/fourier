import gleeunit/should
import store

pub fn roundtrip_test() {
  let dots = [#(1.5, -2.25), #(0.0, 100.0), #(-7.125, 0.125)]
  should.equal(store.decode(store.encode(dots)), Ok(dots))
}

pub fn roundtrip_empty_test() {
  should.equal(store.decode(store.encode([])), Ok([]))
}

pub fn decode_empty_string_is_error_test() {
  should.equal(store.decode(""), Error(Nil))
}

pub fn decode_corrupt_is_error_test() {
  should.equal(store.decode("{definitely not json"), Error(Nil))
}

pub fn decode_wrong_version_is_error_test() {
  should.equal(store.decode("{\"v\":99,\"dots\":[]}"), Error(Nil))
}

pub fn decode_missing_dots_is_error_test() {
  should.equal(store.decode("{\"v\":1}"), Error(Nil))
}

pub fn decode_wrong_shape_is_error_test() {
  should.equal(
    store.decode("{\"v\":1,\"dots\":[[1,2,3]]}"),
    Error(Nil),
  )
  should.equal(
    store.decode("{\"v\":1,\"dots\":[[\"a\",2]]}"),
    Error(Nil),
  )
}