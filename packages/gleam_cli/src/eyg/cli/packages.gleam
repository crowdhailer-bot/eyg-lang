import eyg/cli/internal/config
import eyg/hub/cache
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import loam/execute
import loam/system

/// List the packages published on the hub with their latest version.
pub fn execute(config: config.Config) -> system.Effect(Result(Int, String)) {
  let state = execute.State(config.client.origin, cache.empty())
  use state <- system.then(execute.pull(state))
  case state.cache.cursor_status {
    cache.PullFailed(reason) ->
      system.Done(Error("error: failed to pull packages: " <> reason))
    _ -> {
      let lines =
        dict.to_list(state.cache.packages)
        |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
        |> list.map(fn(package) {
          let #(name, cache.Entry(version:, ..)) = package
          "@" <> name <> ":" <> int.to_string(version)
        })
      let hint = "\nInspect a package with: eyg eval -c '@<name>'"
      use Nil <- system.then(system.stdout(string.join(lines, "\n") <> hint))
      system.Done(Ok(0))
    }
  }
}
