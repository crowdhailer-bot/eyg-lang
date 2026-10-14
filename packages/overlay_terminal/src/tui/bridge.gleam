//// Typed boundary shared by the terminal frontends and the existing EYG tools.

import eyg/cli/args
import eyg/cli/internal/config
import eyg/cli/shell
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import loam/execute
import loam/system

pub fn initialize(arguments: List(String)) {
  use config <- system.then(config.load())
  use config <- system.try(result.replace_error(config, "failed to load config"))
  let input = case args.parse(arguments) {
    args.Shell(input) -> input
    _ -> None
  }
  shell.initialize(input, config)
}

pub fn packages(state: execute.State) {
  use state <- system.map(execute.pull(state))
  #(state, cache_names(state))
}

pub fn cache_names(state: execute.State) {
  state.cache.packages
  |> dict.keys
  |> list.sort(string.compare)
}
