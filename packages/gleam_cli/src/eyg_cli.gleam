import argv
import eyg/cli/args
import eyg/cli/check
import eyg/cli/compile
import eyg/cli/eval
import eyg/cli/fetch
import eyg/cli/inspect
import eyg/cli/internal/config
import eyg/cli/overlay
import eyg/cli/parse
import eyg/cli/profile
import eyg/cli/publish
import eyg/cli/record
import eyg/cli/replay
import eyg/cli/run
import eyg/cli/script
import eyg/cli/share
import eyg/cli/shell
import eyg/cli/signatory
import eyg/cli/tui
import eyg/cli/upload
import eyg/cli/version
import gleam/option
import gleam/result
import loam/system

pub fn main() {
  let arguments = argv.load().arguments
  case args.parse(arguments) {
    args.Tui(input) -> tui.run(input)
    _ -> system.run(start(arguments))
  }
}

/// Run CLI arguments, including output and process exit, through system effects.
pub fn start(arguments: List(String)) -> system.Effect(Nil) {
  use result <- system.then(execute(args.parse(arguments)))
  case result {
    Ok(n) -> system.exit(n)
    Error(reason) -> {
      use Nil <- system.then(system.write_stderr(reason <> "\n"))
      system.exit(1)
    }
  }
}

fn execute(parsed: args.Args) -> system.Effect(Result(Int, String)) {
  case parsed {
    args.Help -> help()
    args.Version -> version()
    args.InvalidArguments(message) -> system.Done(Error(message))

    _ -> with_config(parsed)
  }
}

fn help() {
  use Nil <- system.map(system.stdout(args.help_text))
  Ok(0)
}

fn version() {
  use Nil <- system.map(system.stdout("eyg " <> version.string()))
  Ok(0)
}

fn with_config(parsed) {
  use config <- system.then(config.load())
  use config <- system.try(
    config |> result.replace_error("failed to load config"),
  )
  case parsed {
    args.Help | args.Version | args.InvalidArguments(_) ->
      panic as "handled above"
    args.Shell(input) -> shell.execute(input, config)
    args.Tui(_) -> system.Done(Error("the tui runs from the eyg command"))
    args.Run(input:) -> run.execute(input, config)
    args.Profile(input:) -> profile.execute(input, config)
    args.Script(input:, arguments:) -> script.execute(input, arguments, config)
    args.Eval(input:) -> eval.execute(input, config)
    args.Check(input:) -> check.execute(input, config)
    args.Compile(input:) -> compile.execute(input, config)
    args.Parse(input:) -> parse.execute(input, config)
    args.Share(input:) -> share.execute(input, config)
    args.Fetch(cid:) -> fetch.execute(cid, config)
    args.Publish(package:, file:) -> publish.execute(package, file, config)
    args.SignatoryInitial(name:) -> signatory.initial(name, config)
    args.SignatoryList -> signatory.list(config)
    args.SignatoryShow(alias:) -> signatory.show(alias, config)
    args.Record(input, arguments) -> {
      let mode = case arguments {
        option.None -> record.Block
        option.Some(arguments) -> record.Script(arguments)
      }
      record.execute(input, mode, config)
    }
    args.RecordShell -> shell.record(config)
    args.Replay(path) -> replay.execute(path, config)
    args.Inspect(path, step) -> inspect.execute(path, step, config)
    args.Upload(path) -> upload.execute(path, config)
    args.Overlay(input:) -> overlay.execute(input, config)
  }
}
