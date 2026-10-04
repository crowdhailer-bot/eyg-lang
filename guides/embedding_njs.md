---
name: EYG handlers in nginx
description: Compile an EYG program to a JavaScript module and run it as an njs request handler, with the host choosing its effects.
---

# EYG handlers in nginx

nginx can run JavaScript in the request path with [njs](https://nginx.org/en/docs/njs/).
EYG compiles to JavaScript. This post puts the two together: a request handler written in EYG,
checked, compiled, and served by nginx, that can do exactly two things, log and make subrequests.

The code is in [`examples/njs`](../examples/njs). It uses `nginx:1.29-alpine`, which ships njs 0.9.6 with both of its engines,
its own and QuickJS, and the handler runs on both.

## The handler

```eyg
let count = (items) -> { !list_fold(items, 0, (_, n) -> { !int_add(n, 1) }) }

let describe = (request) -> {
  !string_append(!int_to_string(count(request.headers)), !string_append(" headers, path ", request.path))
}

let respond = (request) -> {
  let _ = perform Log(describe(request))
  match request.method {
    GET(_) -> {
      let upstream = perform Subrequest("/upstream")
      {
        status: 200,
        body: !string_append("EYG handled ", !string_append(describe(request), !string_append(". Upstream said: ", upstream.body)))
      }
    }
    | (_) -> { {status: 405, body: "Only GET is handled by EYG"} }
  }
}
respond
```

`eyg check handler.eyg` gives its type, effects included:

```text
(
  {headers: List(162), path: String, method: [GET: 163 | ..164], ..165}
  <Log(↑String ↓166), Subrequest(↑String ↓{body: String, ..167}), ..168>,
) -> {status: Integer, body: String}
```

Everything the handler can do to the world is in that effect row. There is no way to write a reference to
`ngx`, `r`, or any other JavaScript global in EYG, so compiling it cannot add any.

## Compiling to a module

`compiler.to_module` in `eyg_compiler` type checks the program and refuses it if it does not check.
Otherwise it returns an ES module whose default export holds the program and a runner for its effects:

```gleam
pub fn compile(code) {
  use source <- result.try(
    parser.all_from_string(code) |> result.replace_error("did not parse"),
  )
  compiler.to_module(source, dict.new())
  |> result.map_error(fn(errors) { string.inspect(errors) })
}
```

Effects compile to values: `perform Log(x)` returns an `Eff` holding the label, the value and the rest of the program.
`run` and `runAsync` answer them with a handler for each label, and `runAsync` waits for handlers that return a promise.
The export is a single default, `{program, run, runAsync, Eff}`, because njs's own engine supports no other kind.

## The entry point

What the effects mean in nginx is [`handler.js`](../examples/njs/handler.js), written by hand and twenty lines long:

```js
import eyg from "program.js";

async function handle(r) {
  const request = {
    method: { $T: r.method, $V: {} },
    path: r.uri,
    headers: Object.keys(r.headersIn).reduceRight((tail, name) => [name, tail], []),
  };
  const response = await eyg.runAsync(eyg.program(request), {
    Log: (message) => {
      r.log(message);
      return {};
    },
    Subrequest: async (path) => {
      const reply = await r.subrequest(path);
      return { status: reply.status, body: reply.responseText };
    },
  });
  r.return(response.status, response.body);
}

export default { handle };
```

`Subrequest` is asynchronous in njs and synchronous in EYG. The program does not know, `runAsync` awaits between effects.
The request is built in the compiler's representation, tags as `{$T, $V}` and lists as `[head, tail]` pairs.

## Running

```nginx
js_engine qjs;
js_path /etc/nginx/njs;
js_import main from handler.js;

server {
  listen 8080;
  location / { js_content main.handle; }
  location = /upstream { return 200 "a plain nginx location"; }
}
```

```text
$ curl http://127.0.0.1:8196/some/path -H "X-Demo: 1"
EYG handled 4 headers, path /some/path. Upstream said: a plain nginx location
$ curl -X POST http://127.0.0.1:8196/
Only GET is handled by EYG
```

and in the error log, from the `Log` effect:

```text
[info] 30#30: *1 js: 3 headers, path /x
```

With `js_engine njs` the answers are the same.

## What had to change

The first version of this example compiled with `to_js`, which is what `eyg compile` on the command line still produces.
The JavaScript was compatible with njs, and the rough edges were in the compiler:

- The output was a script that ended by running the program with the compiler's own browser effects, and the glue relied on a variable the compiler happened to name `program`.
  `to_module` makes it a module, and the host passes its handlers, synchronous or not.
- Ill typed programs were compiled. `to_module` refuses them.
- njs's own engine does not allow named exports, or `await` inside a call's arguments, so the module avoids both.
- String literals were escaped for HTML, and `!string_starts_with` and `!string_ends_with` returned `Ok(rest)` where the spec says `True` or `False`.
  The `spec-compiler` branch fixes these, and runs the shared spec against the compiler; this handler uses none of them.
- Record overwrite compiles to object spread, which njs's own engine rejects. The example configures QuickJS, and this handler does not overwrite a record, so it runs on both.

Still open: the published `eyg_compiler` on hex depends on `eyg_ir` 1.x, so the example depends on the repository by path.

The handler is tested by compiling it and running the module under Bun with the same handlers, in `test/njs_test.gleam`.
