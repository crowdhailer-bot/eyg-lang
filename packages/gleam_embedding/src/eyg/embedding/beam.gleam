//// Default BEAM HTTP/hash callbacks. Applications can inject deterministic callbacks.

import eyg/embedding/packages
import gleam/crypto
import gleam/httpc
import gleam/result
import gleam/string
import midas/continuation
import midas/effect

pub fn loader(hub) {
  packages.Loader(
    hub:,
    fetch: fn(request) {
      fn(done) {
        httpc.send_bits(request)
        |> result.map_error(fn(reason) {
          effect.NetworkError(string.inspect(reason))
        })
        |> done
      }
    },
    hash: hash,
  )
}

pub fn hash(algorithm, bytes) {
  let algorithm = case algorithm {
    effect.Sha1 -> crypto.Sha1
    effect.Sha256 -> crypto.Sha256
    effect.Sha384 -> crypto.Sha384
    effect.Sha512 -> crypto.Sha512
  }
  continuation.return(crypto.hash(algorithm, bytes))
}
