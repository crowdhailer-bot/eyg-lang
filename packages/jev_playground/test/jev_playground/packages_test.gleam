import gleam/json
import gleam/list
import gleam/string
import jev_playground/library
import jev_playground/packages

pub fn eyg_packages_load_as_libraries_test() {
  let assert Ok(environment) = packages.environment()
  let names = list.map(environment.libraries, fn(library) { library.name })
  assert list.contains(names, "standard")
  assert list.contains(names, "http")
}

pub fn bundle_round_trips_through_json_test() {
  let assert Ok(bundle) = packages.bundle()
  let encoded = json.to_string(library.to_json(bundle))
  let decoded = json.parse(encoded, library.decoder())
  case decoded {
    Ok(decoded) -> {
      assert decoded.releases == bundle.releases
      assert decoded.modules == bundle.modules
    }
    Error(reason) -> panic as string.inspect(reason)
  }
}
