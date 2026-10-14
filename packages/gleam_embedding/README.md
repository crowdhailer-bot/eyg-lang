# EYG for BEAM hosts

Shared Gleam parsing, type checking, evaluation and validated package loading
for the Erlang, Elixir and Ash examples. Hosts implement their own effects and
retain the cache returned by every call.

`eyg/embedding/runtime.check(source, cache, loader, signatures)` checks without
performing effects. `run(source, cache, loader, signatures, handle)` checks first,
then calls `handle(label, value)` for each effect. Both return continuations whose
result is `#(result, cache)`. `inspect(value)` renders a returned EYG value.
`eyg/embedding/beam.loader(hub)` supplies the existing BEAM HTTP/hash libraries;
`packages.Loader` accepts injected callbacks for tests or other transports.

Missing references load through the existing hub codecs, CID checks and cache
resolver. Named packages, versions, full pins and content references are supported.
Pins must agree with the hub release mapping. Downloaded modules and their
dependencies must evaluate purely and pass type checking. Relative imports are
outside this loader's contract.

A failed package batch returns the caller's original cache. A valid batch remains
cached even when the script subsequently fails checking or evaluation. Already
cached references need no network request. Fresh empty caches are independent;
a host can keep one per application, session or caller. The examples use an OTP
process when several callers should share it.

The cache contains interpreted EYG values, types and release mappings. The
[BEAM code server](https://www.erlang.org/doc/system/code_loading.html) loads the
compiled Gleam and host modules for the VM. Keeping an EYG cache in a process
does not load EYG packages as BEAM modules or give them BEAM hot-code replacement.
Restarting its owner discards that in-memory cache.

```sh
gleam format --check src test
gleam build --warnings-as-errors
gleam test
```

The fixtures exercise real hub encoders and content identifiers, cache reuse,
all reference forms, dependencies, failed batch rollback, rejected modules,
checks before effects, host failures and source diagnostics. Native host adapters
only marshal configuration, callbacks and OTP/framework lifecycle operations.

Mix compiler hooks can run `gleam run -m eyg/embedding/install_beams -- <ebin>`
from their Gleam project directory. Gleam builds that project first; the module
copies its compiled BEAM files into the application's compile path. Mix only
needs to invoke this command and report its exit status. This bridges local
Gleam dependencies while their Erlang releases are not published.
