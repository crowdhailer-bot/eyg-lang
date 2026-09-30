# EYG in nginx

An nginx request handler written in EYG, compiled to JavaScript and run by
[njs](https://nginx.org/en/docs/njs/). The handler can log and make subrequests,
the two effects `handler.js` answers, and nothing else. The compiled program is a
module, `dist/program.js`, that `handler.js` imports.

```sh
gleam run -m compile -- handler.eyg dist
sudo ./run.sh                      # nginx:1.29-alpine on 127.0.0.1:8196
curl http://127.0.0.1:8196/any/path
gleam test --runtime bun            # compiles the handler and runs it in bun
```

The walk through and the compatibility notes are in
[`guides/embedding_njs.md`](../../guides/embedding_njs.md).
