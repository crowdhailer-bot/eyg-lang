//// Application-owned mutable reference, backed by a native array.

import gleam/javascript/array
import plinthx/javascript/array as mutable

pub opaque type Cell(a) {
  Cell(array.Array(a))
}

pub fn new(value: a) -> Cell(a) {
  Cell(array.from_list([value]))
}

pub fn read(cell: Cell(a)) -> a {
  let Cell(values) = cell
  let assert Ok(value) = array.get(values, 0)
  value
}

pub fn write(cell: Cell(a), value: a) -> Nil {
  let Cell(values) = cell
  let assert Ok(Nil) = mutable.set(values, 0, value)
  Nil
}
