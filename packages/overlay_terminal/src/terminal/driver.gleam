//// A typed effect interpreter that gives the frontend terminal ownership.
//// Every nonterminal operation still runs through the existing Loam driver.

import gleam/dynamic.{type Dynamic}
import gleam/http/request
import gleam/int
import gleam/javascript/promise
import gleam/option.{None}
import gleam/result
import gleam/string
import gleam/uri
import loam/system as s
import plinthx/browser/performance
import plinthx/javascript/string as js_string
import plinthx/node/util

pub type IO {
  IO(
    output: fn(String, Bool) -> Nil,
    prompt: fn(String) -> promise.Promise(String),
    fetch: fn(String) -> Nil,
  )
}

pub fn now() -> Float {
  let assert Ok(clock) = performance.get()
  performance.now(clock)
}

pub fn clean(text: String) -> String {
  util.strip_vt_control_characters(text)
}

pub fn error_message(error: Dynamic) -> String {
  js_string.convert(error) |> result.unwrap("Unknown JavaScript error")
}

pub fn drive(effect: s.Effect(a), io: IO) -> promise.Promise(a) {
  case effect {
    s.Done(value) -> promise.resolve(value)
    s.Exit(code) -> {
      let message = "Program exited with status " <> int.to_string(code)
      panic as message
    }
    s.Stdout(text, next) -> {
      io.output(clean(text) <> "\n", False)
      drive(next(Nil), io)
    }
    s.WriteStdout(text, next) | s.WriteStderr(text, next) -> {
      io.output(clean(text), case effect {
        s.WriteStderr(..) -> True
        _ -> False
      })
      drive(next(Nil), io)
    }
    s.Prompt(text, next) -> {
      let text = clean(text) |> string.split("\r") |> last
      use answer <- promise.await(io.prompt(text))
      drive(next(Ok(answer)), io)
    }
    s.Stdin(next) -> {
      use answer <- promise.await(io.prompt("Standard input"))
      drive(next(Ok(answer)), io)
    }
    s.Fetch(req, next) -> {
      io.fetch(public_url(req))
      resume(s.Fetch(req, s.Done), next, io)
    }
    s.FetchStream(req, next) -> {
      io.fetch(public_url(req))
      resume(s.FetchStream(req, s.Done), next, io)
    }
    s.ReadChunk(reader, next) -> resume(s.ReadChunk(reader, s.Done), next, io)
    s.AppendFileBits(path, bits, next) ->
      resume(s.AppendFileBits(path, bits, s.Done), next, io)
    s.CreateDirectory(path, next) ->
      resume(s.CreateDirectory(path, s.Done), next, io)
    s.Cwd(next) -> resume(s.Cwd(s.Done), next, io)
    s.DeleteFile(path, next) -> resume(s.DeleteFile(path, s.Done), next, io)
    s.Env(name, next) -> resume(s.Env(name, s.Done), next, io)
    s.FileInfo(path, next) -> resume(s.FileInfo(path, s.Done), next, io)
    s.GenerateKey(next) -> resume(s.GenerateKey(s.Done), next, io)
    s.Hash(algorithm, bits, next) ->
      resume(s.Hash(algorithm, bits, s.Done), next, io)
    s.Now(next) -> resume(s.Now(s.Done), next, io)
    s.Random(max, next) -> resume(s.Random(max, s.Done), next, io)
    s.ReadDirectory(path, next) ->
      resume(s.ReadDirectory(path, s.Done), next, io)
    s.ReadFile(path, next) -> resume(s.ReadFile(path, s.Done), next, io)
    s.ReadFileRange(path, offset, limit, next) ->
      resume(s.ReadFileRange(path, offset, limit, s.Done), next, io)
    s.SetPermissions(path, mode, next) ->
      resume(s.SetPermissions(path, mode, s.Done), next, io)
    s.Wait(ms, next) -> resume(s.Wait(ms, s.Done), next, io)
    s.WriteFile(path, text, next) ->
      resume(s.WriteFile(path, text, s.Done), next, io)
    s.WriteFileBits(path, bits, next) ->
      resume(s.WriteFileBits(path, bits, s.Done), next, io)
  }
}

fn resume(
  effect: s.Effect(a),
  next: fn(a) -> s.Effect(b),
  io: IO,
) -> promise.Promise(b) {
  use value <- promise.await(s.run(effect))
  drive(next(value), io)
}

fn last(values) {
  case values {
    [] -> ""
    [value] -> value
    [_, ..rest] -> last(rest)
  }
}

fn public_url(req) {
  let parsed = request.to_uri(req)
  uri.to_string(uri.Uri(..parsed, userinfo: None, query: None, fragment: None))
}
