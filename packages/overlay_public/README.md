# overlay_public

Public instance of overlay_web has development setup

Users choose an Ollama Cloud or Mistral model and provide their own API token.
The selection and token are kept in browser session storage and are cleared when
the tab is closed. Ollama calls use the deployment's fixed same-origin proxy
because Ollama Cloud does not allow browser CORS requests. Mistral calls are made
directly from the browser.

## Development

Browser APIs are used through [plinth](https://github.com/CrowdHailer/plinth) rather
than FFI in this package or `overlay_web`. Bindings that are not released yet are
developed in a local clone, which `pal` and this package depend on by path.

```sh
git clone git@github.com:CrowdHailer/plinth.git ../plinth
```

```sh
bun run dev
```

Browser tests run against the development server, started on port 5173 unless
`OVERLAY_PORT` is set:

```sh
bun x playwright install chromium
bun run test:browser
```
