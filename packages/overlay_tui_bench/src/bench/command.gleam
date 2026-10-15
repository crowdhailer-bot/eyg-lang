import gleam/javascript/promise
import plinthx/bun/runtime
import plinthx/bun/subprocess
import plinthx/node/process

pub fn run(arguments) {
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let assert Ok(child) =
    subprocess.spawn(
      bun,
      subprocess.Options(
        arguments,
        ".",
        process.env(host),
        "ignore",
        "pipe",
        "pipe",
      ),
    )
  let assert Ok(stdout) = subprocess.stdout(child)
  let assert Ok(stderr) = subprocess.stderr(child)
  let out = subprocess.readable_stream_to_text(bun, stdout)
  let err = subprocess.readable_stream_to_text(bun, stderr)
  use status <- promise.await(subprocess.exited(child))
  use out <- promise.await(out)
  use err <- promise.map(err)
  let assert Ok(status) = status
  let assert Ok(out) = out
  let assert Ok(err) = err
  #(status, out, err)
}
