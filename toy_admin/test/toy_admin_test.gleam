//// gleeunit entry point — `gleam test` runs this module's main, which
//// discovers every `*_test.gleam` module in test/.

import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}
