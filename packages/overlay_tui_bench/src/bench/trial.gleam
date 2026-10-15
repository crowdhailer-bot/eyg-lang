import benchmark
import core/native_view
import gleam/bit_array
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import plinthx/browser/performance
import plinthx/javascript/foreign
import plinthx/node/process
import sha256
import signals/view
import simplifile
import terminal_lustre/mount

pub fn number(value) {
  json.parse(value, decode.float) |> result.unwrap(0.0)
}

pub fn percentile(samples, percentile) {
  let sorted = list.sort(samples, float.compare)
  let index =
    float.ceiling(percentile *. int.to_float(list.length(samples)))
    |> float.truncate
  list.drop(sorted, int.max(0, index - 1)) |> list.first |> result.unwrap(0.0)
}

pub fn mean(values) {
  float.sum(values) /. int.to_float(list.length(values))
}

pub fn run(variant, workload, rows, trial) {
  assert list.contains(["core", "signals", "lustre"], variant)
  assert list.contains(["stream", "typing"], workload)
  assert rows >= 0 && rows <= 1000 && trial > 0
  let mount = case variant {
    "core" -> native_view.mount
    "signals" -> view.mount
    _ -> mount.mount
  }
  let assert Ok(clock) = performance.get()
  let started = performance.now(clock)
  use session <- promise.await(benchmark.start(workload == "stream", mount))
  use _ <- promise.await(benchmark.render(session))
  let mount_ms = performance.now(clock) -. started
  let warm = case workload {
    "stream" -> benchmark.warm_parser()
    _ -> promise.resolve(Nil)
  }
  use _ <- promise.await(warm)
  let history_start = performance.now(clock)
  int.range(0, rows, with: Nil, run: fn(_, index) {
    let id = 0 - index - 1
    benchmark.emit(
      session,
      json.to_string(
        json.object([
          #("type", json.string("tool")),
          #("id", json.int(id)),
          #("name", json.string("run")),
          #("code", json.string("!int_add(" <> int.to_string(index) <> ", 22)")),
        ]),
      ),
    )
    benchmark.emit(
      session,
      json.to_string(
        json.object([
          #("type", json.string("tool-result")),
          #("id", json.int(id)),
          #("text", json.string(int.to_string(index + 22))),
          #("error", json.bool(False)),
          #("duration", json.int(1)),
        ]),
      ),
    )
  })
  use _ <- promise.await(benchmark.render(session))
  let history_ms = performance.now(clock) -. history_start
  let begin = case workload {
    "stream" -> {
      use _ <- promise.map(benchmark.type_text(
        session,
        "Render the benchmark response",
      ))
      benchmark.key(session, "RETURN")
    }
    _ -> promise.resolve(Nil)
  }
  use _ <- promise.await(begin)
  let checked =
    {
      use samples <- promise.map(samples(session, clock, workload, 0, []))
      let frame = benchmark.capture(session)
      assert string.contains(frame, case workload {
        "stream" -> "Chunk 159"
        _ -> "let value"
      })
        as frame
      #(samples, frame)
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.await(checked)
  let drain = case workload {
    "stream" -> benchmark.drain_parser()
    _ -> promise.resolve(Nil)
  }
  use _ <- promise.await(drain)
  use _ <- promise.map(benchmark.stop(session))
  let #(latencies, frame) = case checked {
    Ok(value) -> value
    Error(reason) -> foreign.raise(reason)
  }
  let assert Ok(host) = process.get()
  let versions = foreign.property(foreign.to_dynamic(host), "versions")
  let bun =
    foreign.property(versions, "bun")
    |> decode.run(decode.string)
    |> result.unwrap("unknown")
  let cpu =
    simplifile.read("/proc/cpuinfo")
    |> result.unwrap("unknown")
    |> string.split("\n")
    |> list.find(string.starts_with(_, "model name"))
    |> result.unwrap("unknown")
  json.object([
    #("variant", json.string(variant)),
    #("workload", json.string(workload)),
    #("history_rows", json.int(rows)),
    #("trial", json.int(trial)),
    #(
      "recorded_unix_ms",
      json.float(performance.time_origin(clock) +. performance.now(clock)),
    ),
    #("bun", json.string(bun)),
    #("cpu", json.string(cpu)),
    #("opentui", json.string("0.5.14")),
    #("columns", json.int(110)),
    #("lines", json.int(34)),
    #("warmup", json.int(40)),
    #("samples", json.int(120)),
    #("mount_ms", json.float(mount_ms)),
    #("history_ms", json.float(history_ms)),
    #("mean_ms", json.float(mean(latencies))),
    #("p95_ms", json.float(percentile(latencies, 0.95))),
    #("latencies_ms", json.array(latencies, json.float)),
    #(
      "frame_sha256",
      json.string(sha256.hash(<<frame:utf8>>) |> bit_array.base16_encode),
    ),
  ])
}

fn samples(session, clock, workload, index, collected) {
  case index == 160 {
    True -> promise.resolve(list.reverse(collected))
    False -> {
      let started = performance.now(clock)
      let work = case workload {
        "stream" -> {
          benchmark.emit(
            session,
            json.to_string(
              json.object([
                #("type", json.string("assistant")),
                #("id", json.int(-100_000)),
                #(
                  "text",
                  json.string(
                    "Chunk "
                    <> int.to_string(index)
                    <> ". **Measured** text and `code`.\n\n",
                  ),
                ),
              ]),
            ),
          )
          promise.resolve(Nil)
        }
        _ -> {
          let chars = string.to_graphemes("let value = !int_add(20, 22) ")
          let assert Ok(char) =
            list.drop(chars, index % list.length(chars)) |> list.first
          benchmark.type_text(session, char)
        }
      }
      use _ <- promise.await(work)
      use _ <- promise.await(benchmark.render(session))
      let elapsed = performance.now(clock) -. started
      let collected = case index >= 40 {
        True -> [elapsed, ..collected]
        False -> collected
      }
      samples(session, clock, workload, index + 1, collected)
    }
  }
}
