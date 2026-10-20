//// Small shared numeric helpers for the math core.
////
//// Single home for constants/helpers that several core modules used to
//// repeat (extracted 2026-10-20 code-review pass: 5-way `indices` and
//// 4-way `pi` copies).
//// π — gleam_stdlib has no pi constant.

import gleam/list

pub const pi = 3.141_592_653_589_793

/// Index sequence [0, 1, .., n-1] — gleam_stdlib 1.0 has no list.range.
pub fn indices(n: Int) -> List(Int) {
  list.repeat(Nil, n)
  |> list.index_map(fn(_, i) { i })
}
