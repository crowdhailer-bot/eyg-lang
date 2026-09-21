# Phantom — EYG browser drive

A single injected script adds a draggable chat assistant to a web page.
The agent is mocked; parsing, evaluation, DOM inspection, CSS, button insertion
and the effect trace use the real EYG interpreter.

## Run

Requires Gleam, Node.js 22+, and npm. From this directory:

```sh
npm ci
npm run build
npm start
```

Open http://127.0.0.1:4173. Choose a demo, click **Inject Phantom**, review the
injection code, and run it. Suggested prompts fill the composer; Enter or the
send button submits. Shift+Enter inserts a line break.

The local DI and SJ pages use fictional data and are labeled as independent
recreations. They work offline after building. The live recordings use the actual
sites and their displayed data.

## Inject into a real page

Open the target page, open **DevTools → Sources → Snippets**, paste the contents
of the built `dist/phantom.js` into a new snippet, and run it. This uses the local
bundle directly, as the live recorder does.

Alternatively, with the local server running and the page's policy permitting
localhost scripts, open the browser developer console and run:

```js
const script = document.createElement('script');
script.src = 'http://127.0.0.1:4173/dist/phantom.js';
document.head.append(script);
```

For DI, open https://www.di.se/ and find its market chart. Ask for a bigger graph,
a hover effect, and a focus mode button.
For SJ, use https://www.sj.se/ to search for a journey, then ask to shortlist
the two cheapest direct trains and add a shortlist toggle.
The mock understands these prepared requests; it is not a general LLM.
It reads actual tool results and reports missing elements or unsupported
requests instead of inventing a result. Live markup and availability can change.

Some sites prohibit injected scripts, inline styles, or blob workers through
Content Security Policy. Browser local-network policy can also block a localhost
script. In that case use the local demos or a host you control; this project
does not disable those protections. An HTTPS-hosted copy of the same bundle can
be used where the host policy permits it.

`phantom.js` is the plugin filename; this does not depend on the legacy PhantomJS
browser. It bundles the parser, interpreter, worker source, UI, mock provider and
canonical EYG syntax guide. No remote model, hub or CDN is needed.

## Interface

- Drag the header to float the panel, or use the left/right dock controls.
- Expand code and effects independently. More than four effects collapse into a
  summary; every completed effect retains its check mark.
- The square stop button cancels an active response. Errors roll back writes
  from that run. Completed earlier runs remain available to undo.
- **Undo change** reverses the last mutating EYG run. The injected button toggles
  all current page changes. Closing Phantom undoes all changes and removes it.
- Repeated injection opens the existing panel. No account or storage is used.

## Capabilities

| Effect         | Argument            | Result / behavior                                                                                                                |
| -------------- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `GetElements`  | CSS selector string | Up to 40 rendered element snapshots with opaque ID, selector, tag, text, label, width and height; no DOM objects or input values |
| `WriteCSS`     | CSS string          | Validated presentation rules; returns a rule count                                                                               |
| `InsertButton` | Label string        | Host-owned button toggling Phantom changes; returns its label and action                                                         |
| `SetAttribute` | `{id, name, value}` | Sets only `data-eyg-*` presentation markers on inspected nodes                                                                   |

`SetAttribute` is the only additional effect beyond the plan's three.
It lets EYG mark a computed set of elements without exposing arbitrary HTML,
JavaScript or event handlers. The same capability supports shortlists,
annotations and comparison views on other sites.

CSS properties are allowlisted, including their browser-expanded longhands.
At-rules, resources, escapes, CSS variables and generated content are rejected.
Runs are bounded by 32,000 source characters, 250,000 interpreter steps, 64
effects, a 5-second worker deadline and 128,000-character transport messages.

The trusted JavaScript host defines the boundary. A worker keeps EYG off the UI
thread, but is not a separate-origin security boundary against a hostile host
page. See the [embedding guide](../../guides/browser_drive.md) for the exact
sandbox guarantees, agent protocol and provider integration.

## Tests and recordings

```sh
npx playwright install chromium
npm test
npm run record
npm run record:live
```

Recording also requires `ffmpeg`. The local recorder starts its own server,
records typing, injection, effects, code expansion, toggles, docking and dragging,
and verifies the resulting DOM. Live recordings do not disable CSP, log in,
purchase tickets or accept optional cookies. They require network access and
available journey results. Use `node test/record-live.mjs di` or `sj` to record
just one. `npm run check:live` collects a diagnostic page snapshot.

| Walkthrough | Recording                            | Final screenshot                                 |
| ----------- | ------------------------------------ | ------------------------------------------------ |
| DI local    | [di-demo.mp4](artifacts/di-demo.mp4) | [di-after.png](artifacts/di-after.png)           |
| SJ local    | [sj-demo.mp4](artifacts/sj-demo.mp4) | [sj-after.png](artifacts/sj-after.png)           |
| DI live     | [di-live.mp4](artifacts/di-live.mp4) | [di-live-after.png](artifacts/di-live-after.png) |
| SJ live     | [sj-live.mp4](artifacts/sj-live.mp4) | [sj-live-after.png](artifacts/sj-live-after.png) |

Build outputs and raw capture files are ignored. The final videos, screenshots,
and transcripts are kept in `artifacts`. Rebuild after changing any source.

## Files

- `src/worker.mjs`: Gleam parser/interpreter bridge, value conversion, step budget.
- `src/runtime.mjs`: Promise API, worker lifetime, effect dispatch, cancellation.
- `src/effects.mjs`: validated DOM capabilities and reversible transactions.
- `src/agent.mjs`: full system prompt, single-tool schema and bounded agent loop.
- `src/mock.mjs`: deterministic provider consuming the same protocol as an LLM.
- `src/phantom.mjs`, `src/phantom.css`: the injected chat interface.
- `demo/`: gallery and reproducible demo pages.
- `dist/eyg.js`: generated ESM embedding API.
- `dist/system-prompt.txt`: generated complete prompt, including the syntax guide.
