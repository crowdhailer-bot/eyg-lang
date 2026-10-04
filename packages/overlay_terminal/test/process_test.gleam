import gleam/int
import gleam/javascript/promise
import gleam/option.{None, Some}
import gleeunit/should
import plinthx/browser/response
import plinthx/bun
import plinthx/bun/server
import terminal/cell
import terminal/driver
import terminal/process
import terminal/protocol as p

fn within(work) {
  promise.race_list([
    promise.map(work, Ok),
    promise.wait(5000) |> promise.map(fn(_) { Error("Timed out") }),
  ])
}

pub fn subprocess_roundtrip_and_prompt_does_not_deadlock_test() {
  let #(ready, mark_ready) = promise.start()
  let #(done, mark_done) = promise.start()
  let runtime_ref = cell.new(None)
  let runtime =
    process.start(
      fn(event) {
        case event {
          p.Ready(_) -> mark_ready(Nil)
          p.Prompt(_, _) -> {
            let assert Some(runtime) = cell.read(runtime_ref)
            process.send(runtime, p.Reply("hello from IPC")) |> should.be_ok
          }
          p.Complete(_, results, _, _) -> mark_done(results)
          p.Failure(_, message) -> panic as message
          _ -> Nil
        }
      },
      [],
    )
    |> should.be_ok
  cell.write(runtime_ref, Some(runtime))
  process.send(runtime, p.Initialize([])) |> should.be_ok
  use initialized <- promise.await(within(ready))
  should.be_ok(initialized)
  process.send(
    runtime,
    p.Evaluate(
      1,
      "match perform StandardIn({}) { Ok(bytes) -> { !string_from_binary(bytes) } Error(e) -> { Error(e) } }",
      False,
    ),
  )
  |> should.be_ok
  use returned <- promise.await(within(done))
  use _ <- promise.map(process.terminate(runtime))
  should.be_ok(returned) |> should.equal([Ok("Ok(\"hello from IPC\")")])
  process.send(runtime, p.Evaluate(2, "42", False)) |> should.be_error
}

pub fn subprocess_terminates_during_infinite_evaluation_test() {
  let #(ready, mark_ready) = promise.start()
  let runtime =
    process.start(
      fn(event) {
        case event {
          p.Ready(_) -> mark_ready(Nil)
          _ -> Nil
        }
      },
      [],
    )
    |> should.be_ok
  process.send(runtime, p.Initialize([])) |> should.be_ok
  use initialized <- promise.await(within(ready))
  should.be_ok(initialized)
  process.send(
    runtime,
    p.Evaluate(1, "let forever = (f) -> { f(f) } forever(forever)", False),
  )
  |> should.be_ok
  use Nil <- promise.await(promise.wait(100))
  let started = driver.now()
  use exited <- promise.map(within(process.terminate(runtime)))
  should.be_ok(exited) |> should.be_ok
  { driver.now() -. started <. 1000.0 } |> should.be_true
}

fn shutdown_requests(remaining, origin, requests) -> promise.Promise(Nil) {
  case remaining {
    0 -> promise.resolve(Nil)
    _ -> {
      let before = cell.read(requests)
      let #(ready, resolve) = promise.start()
      let runtime =
        process.start(
          fn(event) {
            case event {
              p.Ready(_) -> resolve(Nil)
              _ -> Nil
            }
          },
          [#("EYG_ORIGIN", origin)],
        )
        |> should.be_ok
      process.send(runtime, p.Initialize([])) |> should.be_ok
      use initialized <- promise.await(within(ready))
      should.be_ok(initialized)
      use observed <- promise.await(wait_for_request(requests, before, 100))
      use exited <- promise.await(within(process.terminate(runtime)))
      should.be_true(observed)
      should.be_ok(exited) |> should.be_ok |> should.not_equal(139)
      shutdown_requests(remaining - 1, origin, requests)
    }
  }
}

pub fn repeated_subprocess_shutdown_during_fetch_test() {
  let host = bun.get() |> should.be_ok
  let requests = cell.new(0)
  let server =
    server.serve(
      host,
      server.Options("127.0.0.1", 0, fn(_, _) {
        cell.write(requests, cell.read(requests) + 1)
        use Nil <- promise.map(promise.new(fn(_) { Nil }))
        response.new("[]", response.Options(200, [])) |> should.be_ok
      }),
    )
    |> should.be_ok
  let origin = "http://127.0.0.1:" <> int.to_string(server.port(server))
  use Nil <- promise.await(shutdown_requests(8, origin, requests))
  use stopped <- promise.map(server.stop(server, True))
  should.be_ok(stopped)
}

fn wait_for_request(requests, before, attempts) {
  case cell.read(requests) > before, attempts {
    True, _ -> promise.resolve(True)
    False, 0 -> promise.resolve(False)
    False, _ -> {
      use Nil <- promise.await(promise.wait(5))
      wait_for_request(requests, before, attempts - 1)
    }
  }
}
