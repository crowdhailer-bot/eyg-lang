# overlay_web

The state, view model, and tool implementation for the overlay agent.
`overlay_public` runs this state machine in the browser.

## Context

Every overlay session runs with a context module: a record whose `readme` field
explains the rest of its typed API. The readme is given to the agent as part of
the system prompt and the module is in scope, as `context`, for every program
the run tool executes.

The browser deployment reads the requested module from the page query:

| query | selected module |
| --- | --- |
| `?reference=<cid>` | module with that content ID |
| `?package=<name>` | latest release of the package |
| `?package=<name>&version=<n>` | positive release `n` |

A session that asks for none, or for one that cannot be loaded, runs against the
built-in default module, whose readme describes the overlay agent itself. So a
program can always read `context.readme`. A request that could not be met is
shown on the page with its reason, rather than the session starting as though
nothing had been asked for.

The page refuses prompts while a requested module is still being looked up.

## Development

```sh
gleam test
```

To use a context in the browser, run the public page against a hub:

```sh
cd ../overlay_public
EYG_HUB=http://localhost:8080 bun run dev
```

`EYG_HUB` selects the hub proxied by the development server for module and
package lookups. It defaults to `https://eyg.run`.
