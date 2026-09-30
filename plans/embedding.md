# Making EYG easier to embed

Four hosts were built on published packages to find out what embedding EYG costs today:
a shell and an agent for the [hashi](https://github.com/giacomocavalieri/hashi) puzzle,
an nginx handler compiled for njs, and TodoMVC twice, in Lustre and in TypeScript,
with a shell and an agent that query tasks using `@standard`.

Each host worked. Each also hit the same problems, and copied the same few hundred lines from the last.
This plan lists what would make the next one shorter, smallest and most valuable first.

## Easy wins

Each is one package, a few dozen lines, and a test that fails today.

1. **`block.resume` loses the shell's scope.** `eyg_interpreter`.
   A block that resumed after an effect performed inside a closure reported the closure's scope.
   `hashi.islands({})` in a shell, then `hashi` was undefined. Fixed on main, released in `eyg_interpreter` 8.0.0.
2. **`ir.map_annotation` overflows the stack.** `eyg_ir`.
   It is built on the continuation passing `rewrite`, whose stack grows with the number of nodes, not the depth.
   `@standard` overflows headless Chromium, and the hub cache calls it on every module it fetches.
   `list_references`, `list_builtins` and `get_annotation` share the problem through `fold`.
3. **Hub reads have no CORS headers.** `hub`.
   A browser could not fetch a module or pull the release log from eyg.run, so every page proxied `/modules` and `/packages`. Fixed on main.
4. **overlay_llm panics on a line that is not JSON.** `overlay_llm`.
   The Ollama stream parser `let assert`s every line, including an empty one or an HTML error page.
5. **`infer` has no way to add variables to a context.** `eyg_analysis`.
   Every host writes `infer.Context(..context, env: ...)`, and overlay has a private `with_scope`
   marked "TODO move to infer module".
6. **The JavaScript compiler.** `eyg_compiler`.
   Strings escaped for HTML, `string_starts_with` and `string_ends_with` returning `Ok(rest)` where the spec says booleans,
   and missing builtins. The `spec-compiler` branch runs the shared spec against the compiler and fixes these.
   Record overwrite still compiles to object spread, which njs's own engine rejects; QuickJS accepts it.

Not easy wins, but found on the way:

- `eyg_compiler` on hex requires `eyg_ir` 1.x and cannot be used with current packages. It needs a release, not code.
- `eyg check` does not fetch references, `eyg eval` does.
- A record with an unexpected field is reported as `missing row 'form'`, naming the field the program has rather than the one the type expects.
  The unifier does not know which side was expected, so fixing the wording means carrying that through.

## Involved features

After the easy wins, the hosts still repeat three things: running a program against their effects,
keeping a shell, and running an agent. And a host that is not written in Gleam cannot start.
These are larger, and change what a host is made of rather than fixing a line in it.

### A package for hosts: `eyg_embed`

The shell code in the hashi example was copied into the TodoMVC example, and again into the TypeScript bridge,
changing only the effects and where references come from. It belongs in one package, `packages/gleam_embed`,
depending on the parser, the analysis and the interpreter, and not on the hub, so it can be published.

- **`eyg/embed/run`** run a program to the end against a handler, `fn(state, label, lift) -> Result(#(state, reply), reason)`,
  resolving references with a function the host gives. One loop for every host, including the reference case each one forgot.
- **`eyg/embed/shell`** parse a block, check it against the effects and the variables so far, run it, and keep its variables and their types.
  The hashi, TodoMVC and TypeScript shells are each about 250 lines of this.
- **`eyg/embed/agent`** the agent from the examples: pure, one `run` tool, a readme and the syntax guide in its prompt, the host sends the requests.
- **`eyg/embed/json`** EYG values as plain JSON, effect types described as data, and a check that a reply has the type it claims.
  What a host in another language needs, see below.
- **`eyg/embed/browser`** `fetch` and `hash` for JavaScript hosts, in the shape `eyg_hub` takes them.

### Loading packages in one call

`cache.load(cache, source, origin, fetch, hash, meta)` in `gleam_hub`, a continuation that finishes when every reference in the source
is in the cache or has failed. It is the sixty lines the TodoMVC example spent driving the cache, including fetching the module a pulled
`@name` points to. With `eyg/embed/browser`, loading `@standard` in a page is one call.

### Compiling to a module

`compiler.to_module(source, refs)` returning an ES module whose default export holds the program, and a `run` and `runAsync`
for the host to answer effects, and refusing a program that does not type check.
The njs glue becomes an import. It sits beside `to_js` and changes nothing the `spec-compiler` branch changes.

### EYG for JavaScript without Gleam

A TypeScript host wrote a Gleam project to reach EYG. `eyg_embed` compiled and bundled into one ES module with a `.d.ts`,
exposing `eyg/embed/json` and the shell in plain JavaScript, lets a JavaScript host vendor a file instead.
Publishing it to npm is a release decision; building it is not.

### Not attempted here

- **overlay_web's agent** is tied to the browser harness. Rebuilding it on `eyg/embed/agent` would let the overlay page and any host share one agent,
  but the page also streams, fetches contexts from the hub and asks for providers, and is a change to a product rather than a library.
- **Type errors that say which side was expected**, for records and effects with an unexpected field.
- **`eyg check` fetching references** like `eyg eval` does.

## Status

On the `embedable` branch, on top of main's block and CORS fixes:

- Easy wins 2, 4 and 5, each with a test that failed before it. The compiler fixes are left to `spec-compiler`.
- `eyg_embed`, in `packages/gleam_embed`: `run`, `shell`, `json`, `agent` and `browser`.
- `cache.load` in `gleam_hub`.
- `compiler.to_module` in `eyg_compiler`.
- `dist/eyg.mjs`, built by `packages/embed_js`. Its `runAsync` loads the packages a piece of code refers to before running it,
  which the Gleam shell leaves to the host.

The examples are built on these in the `embedable-examples` branch.
