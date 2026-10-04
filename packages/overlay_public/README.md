# overlay_public

Public instance of overlay_web has development setup

Users choose an Ollama Cloud or Mistral model and provide their own API token.
The selection and token are kept in browser session storage and are cleared when
the tab is closed. Ollama calls use the deployment's fixed same-origin proxy
because Ollama Cloud does not allow browser CORS requests. Mistral calls are made
directly from the browser.

## Development

```sh
bun run dev
```

Open [localhost:5173/overlay/](http://localhost:5173/overlay/), the page is served under `/overlay/`.
Use `bunx vite --port <port>` for another port.
Add `?package=<name>` to the URL to use a published package as the context, see the [overlay_web README](../overlay_web/README.md).

The browser agent can use the effects listed in its system prompt, there is no file system access.
`Fetch` only reaches servers that allow cross origin requests.
