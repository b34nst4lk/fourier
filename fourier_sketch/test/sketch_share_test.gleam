import gleam/list
import gleeunit/should
import sketch
import sketch_share

const diamond = [
  #(5.0, 50.0),
  #(50.0, 5.0),
  #(95.0, 50.0),
  #(50.0, 95.0),
]

pub fn to_query_is_versioned_params_test() {
  sketch_share.to_query(diamond)
  |> should.equal("v=1&sk=500,5000;5000,500;9500,5000;5000,9500")
}

pub fn encode_clamps_to_grid_test() {
  // coordinates snap to the 0.01 grid and never leave the 0..100 box
  let dots = [#(-4.0, 50.0), #(50.0, 104.0), #(23.4567, 50.0)]
  let assert Ok(decoded) = sketch_share.from_query(sketch_share.to_query(dots))
  decoded
  |> should.equal([#(0.0, 50.0), #(50.0, 100.0), #(23.46, 50.0)])
}

pub fn from_query_round_trip_test() {
  let dots = [
    #(5.0, 50.0),
    #(23.45, 47.8),
    #(50.0, 5.0),
    #(95.0, 50.0),
    #(50.0, 95.0),
  ]
  let assert Ok(decoded) = sketch_share.from_query(sketch_share.to_query(dots))
  list.length(decoded)
  |> should.equal(5)
  list.first(decoded)
  |> should.equal(Ok(#(5.0, 50.0)))
}

pub fn from_query_accepts_full_url_test() {
  sketch_share.from_query(
    "https://jacks.im/toys/fourier-sketch/?v=1&sk="
    <> "500,5000;5000,500;9500,5000;5000,9500",
  )
  |> should.equal(Ok(diamond))
}

pub fn from_query_rejects_unknown_version_test() {
  "v=2&sk=500,5000"
  |> sketch_share.from_query
  |> should.equal(Error(Nil))
  "sk=500,5000"
  |> sketch_share.from_query
  |> should.equal(Error(Nil))
}

pub fn from_query_rejects_garbage_test() {
  "v=1&sk=not-a-drawing"
  |> sketch_share.from_query
  |> should.equal(Error(Nil))
  "v=1&sk=500,5000;oops"
  |> sketch_share.from_query
  |> should.equal(Error(Nil))
}

pub fn to_query_empty_and_round_trip_test() {
  let sk = sketch.start([]) |> sketch.dots
  sk
  |> should.equal([])
  sketch_share.to_query([])
  |> should.equal("v=1&sk=")
  let assert Ok(decoded) = sketch_share.from_query("v=1&sk=")
  decoded
  |> should.equal([])
}
