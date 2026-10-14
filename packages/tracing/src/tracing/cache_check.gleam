//// Verify persistent CLI packages in independent processes, including offline reuse.

import filepath
import gleam/dict
import gleam/io
import gleam/javascript/promise
import gleam/result
import gleam/string
import loam/system
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/bun/subprocess
import plinthx/node/process
import tracing/package_fixture

pub fn main() {
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let env = process.env(host) |> dict.from_list
  let binary =
    dict.get(env, "EYG_BIN") |> result.unwrap("../gleam_cli/dist/eyg")
  use directory <- promise.await(system.run(system.temporary_directory()))
  let assert Ok(directory) = directory
  let env =
    env
    |> dict.insert("EYG_ORIGIN", "http://127.0.0.1:7207")
    |> dict.insert("XDG_CACHE_HOME", filepath.join(directory, "cache"))
    |> dict.insert("XDG_CONFIG_HOME", filepath.join(directory, "config"))
    |> dict.to_list
  let assert Ok(fixture) = package_fixture.start()
  let code = fixture.reference <> ".integer.add(40, 2)"
  let outcome =
    {
      use first <- promise.await(evaluate(bun, env, binary, code))
      assert first == "42"
      let initially = fixture.count()
      assert initially == 3
      use repeated <- promise.map(evaluate(bun, env, binary, code))
      assert repeated == "42"
      assert fixture.count() == initially + 2
        as "Only ledger pages refresh in a new online process"
      Nil
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use stopped <- promise.await(server.stop(fixture.server, True))
  let assert Ok(_) = stopped
  let assert Ok(_) = outcome
  use offline <- promise.map(evaluate(bun, env, binary, code))
  assert offline == "42"
  io.println(
    "PASS persistent CLI packages: cold load, online module reuse and new offline process",
  )
}

fn evaluate(bun, env, binary, code) {
  let assert Ok(child) =
    subprocess.spawn(
      bun,
      subprocess.Options(
        [binary, "eval", "-c", code],
        ".",
        env,
        "ignore",
        "pipe",
        "pipe",
      ),
    )
  let assert Ok(stdout) = subprocess.stdout(child)
  let assert Ok(stderr) = subprocess.stderr(child)
  use output <- promise.await(subprocess.readable_stream_to_text(bun, stdout))
  use errors <- promise.await(subprocess.readable_stream_to_text(bun, stderr))
  use status <- promise.map(subprocess.exited(child))
  let assert Ok(0) = status as string.inspect(errors)
  let assert Ok(output) = output
  string.trim(output)
}
