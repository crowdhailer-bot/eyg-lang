import ash_eyg/actions
import ash_eyg/runtime as ash
import eyg/analysis/type_/binding/debug
import eyg/embedding/packages
import eyg/embedding/runtime
import eyg/hub/cache
import gleam/list
import gleam/result
import gleam/string
import midas/continuation as k
import simplifile

pub fn source(args: List(String)) {
  case args {
    ["-e", source] | ["--eval", source] -> Ok(source)
    [path] ->
      simplifile.read(path)
      |> result.map_error(fn(_) { "Could not read script: " <> path })
    _ -> Error("expected a path to a script or -e followed by a script")
  }
}

pub fn check(args) {
  case source(args) {
    Error(reason) -> k.return(Error(reason))
    Ok(source) -> {
      use #(checked, _) <- k.then(ash.check(
        source,
        cache.empty(),
        loader(),
        options(),
      ))
      k.return(checked)
    }
  }
}

pub fn run(args) {
  case source(args) {
    Error(reason) -> k.return(Error(reason))
    Ok(source) -> {
      use #(value, _) <- k.then(ash.run(
        source,
        cache.empty(),
        loader(),
        options(),
      ))
      k.return(result.map(value, runtime.inspect))
    }
  }
}

pub fn effects() {
  list.map(application_effects(), describe) |> string.join("\n\n")
}

pub fn describe(effect: actions.Effect(m, context)) {
  effect.label
  <> "\n  lift:  "
  <> indent(debug.render_type(effect.lift))
  <> "\n  reply: "
  <> indent(debug.render_type(effect.lower))
}

fn indent(text) {
  string.replace(text, "\n", "\n         ")
}

@external(erlang, "Elixir.AshEyg.Mix", "effects")
fn application_effects() -> List(actions.Effect(m, context))

@external(erlang, "Elixir.AshEyg.Mix", "options")
fn options() -> ash.Options

@external(erlang, "Elixir.AshEyg.Packages", "loader")
fn loader() -> packages.Loader(t)
