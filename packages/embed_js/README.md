# EYG for JavaScript

`dist/eyg.mjs` is EYG for a JavaScript or TypeScript host that does not use Gleam:
a shell that checks and runs code against the effects the host describes, with
packages from an EYG hub. It is `eyg_embed` and `eyg_hub` compiled and bundled.

```sh
bun run build   # dist/eyg.mjs and dist/eyg.d.ts
bun run test
```

```ts
import { createShell } from "./eyg.mjs";

const shell = await createShell({
  effects: { Add: { lift: "integer", lower: "integer" } },
  hub: "https://eyg.run",
  modules: { lib: librarySource },
});
let total = 0;
shell.run("perform Add(2)", { Add: (n) => (total += n) });  // {value: 2, display: "2"}
await shell.runAsync("@standard.list.length([1, 2])", {});  // loads @standard first
```

Types are described with plain data, see `eyg.d.ts`. Values cross as plain JavaScript:
numbers, strings, arrays, objects, booleans for `True({})` and `False({})`, and
`{$: "Ok", value}` for other tags. A handler's reply is checked against the type it declared.
