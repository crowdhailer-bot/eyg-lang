//// The libraries in `eyg_packages` offered to Jev, loaded from disk.
//// `gleam run -m jev_playground/packages --runtime bun` lists them with their content ids.

import gleam/int
import gleam/io
import gleam/list
import gleam/result.{try}
import jev_playground/environment
import jev_playground/library
import multiformats/cid/v1
import simplifile

pub const root = "../../eyg_packages"

pub fn bundle() -> Result(library.Bundle, String) {
  let release = fn(bundle, name, version, path) {
    library.release(bundle, name, version, root <> path, read, sha256)
  }
  use bundle <- try(release(
    library.empty,
    "standard",
    1,
    "/standard/index.eyg.json",
  ))
  use bundle <- try(release(bundle, "http", 3, "/http/index.eyg"))
  use bundle <- try(release(bundle, "json", 1, "/json/index.eyg"))
  release(bundle, "option", 1, "/option/index.eyg")
}

pub fn read(path) {
  simplifile.read_bits(path) |> result.map_error(simplifile.describe_error)
}

/// The browser environment with every library.
pub fn environment() -> Result(environment.Environment, String) {
  use bundle <- try(bundle())
  library.environment(bundle, environment.browser())
}

pub fn main() {
  case bundle() {
    Ok(bundle) -> {
      list.each(bundle.modules, fn(module) {
        let name = case
          list.find(bundle.releases, fn(r) { r.module == module.cid })
        {
          Ok(release) -> release.name
          Error(Nil) -> "(imported)"
        }
        io.println(v1.to_string(module.cid) <> " " <> name)
      })
      case environment() {
        Ok(environment) ->
          io.println(
            "loaded "
            <> int.to_string(list.length(environment.libraries))
            <> " libraries",
          )
        Error(reason) -> io.println(reason)
      }
    }
    Error(reason) -> io.println(reason)
  }
}

@external(javascript, "./node_ffi.mjs", "sha256")
pub fn sha256(bits: BitArray) -> BitArray
