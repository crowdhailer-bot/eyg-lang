import gleam/javascript/array
import plinthx/browser/fetch
import plinthx/javascript/array as native_array

pub fn fallible_native_constructors_return_results_test() {
  let assert Ok(response) = fetch.get_response()
  let assert Error(_) = fetch.new_response(response, "", 999, [])
}

pub fn array_methods_preserve_native_mutation_test() {
  let values = array.from_list([1, 2])
  assert native_array.push(values, 3) == Ok(3)
  let assert Ok(removed) = native_array.splice(values, 0, 2, [4])
  assert array.to_list(removed) == [1, 2]
  assert array.to_list(values) == [4, 3]
}
