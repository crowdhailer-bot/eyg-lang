---
name: Overlay artifacts and tiling
description: Versioned HTML bundles, local srcdoc isolation, and content-addressed EYG viewers and layouts.
---

# Overlay artifacts and tiling

## Proposal

Overlay artifacts are named, versioned bundles of files, rendered locally in the
browser. They need no deployment, sandbox domain, or per-artifact server. The
agent fetches data using the existing `Fetch` effect and includes that data in a
bundle; artifact JavaScript never receives provider credentials or a general
bridge to Overlay's effects.

Two new browser-Overlay effects are necessary: existing effects cannot retain a
versioned document or place an interactive view in the workspace. `Artifact`
stores a complete snapshot; `Show` places a view. These are general-purpose
document/presentation operations, independent of maps, transport, or a layout.

### Effect contract

```eyg
let saved = perform Artifact({
  name: "map",
  bundle: [{
    path: "index.html",
    media_type: "text/html",
    content: !string_to_binary("<h1>My map</h1>")
  }]
})
perform Show({
  item: Artifact("map"),
  origin: {x: 0, y: 0},
  size: {x: 600, y: 1000}
})
```

`Artifact` returns `Ok(version)` or `Error(reason)`. Every successful call
appends an immutable snapshot, including repeated identical content. Versions
start at 1 independently for each name. Bundles must have a UTF-8 `index.html`,
unique relative paths, and explicit media types. File contents are binary, so
images and other assets do not require a separate file representation.
Current limits are 128 files and 2 MiB of file contents per snapshot, and
16 MiB of retained file contents across the session. Rejected saves do not
create a revision.

`Show` returns `Ok({})` or `Error(reason)`. Points use integer workspace units:
the whole canvas is 1000 by 1000, independent of screen size. Rectangles must be
positive and contained in that canvas. Repeating `Show` for the same item moves
or resizes its existing panel. Different item kinds can coexist:

- `Artifact(name)` follows the latest snapshot.
- `Revision({name, version})` pins a snapshot.
- `History(name)` lists all snapshots and their files.
- `Diff({name, from, to})` compares two snapshot numbers, displaying added,
  removed and changed files, with text changes and binary metadata.

History/diffs are rendered as escaped application UI, never as executable HTML.
History entries can be opened as pinned previews. Closing a panel does not
delete its artifact. State is retained across agent turns in this browser
session; reload persistence is outside this first implementation.

### Local srcdoc wrapper

```text
overlay_public
  └─ trusted wrapper iframe (srcdoc, sandbox="allow-scripts")
       └─ artifact iframe (srcdoc, sandbox="allow-scripts")
```

Neither frame grants `allow-same-origin`, popups, forms, downloads, or ancestor
navigation. The inner document has a distinct opaque origin and cannot read
the wrapper or application DOM, cookies, session storage, local storage, or
IndexedDB. Artifacts have no bridge to Overlay, the only channel is the one way
puppet described under artifact control.

The fixed wrapper puts its CSP before all content. It allows inline scripts and
styles and embedded `data:` resources, denies connections, objects, workers,
base URLs and form actions, and sets `frame-src 'none'`. The inner `srcdoc` is
allowed, but network navigation of the inner frame is blocked by its parent's
policy. The policy therefore lives outside the artifact document. Additional
artifact CSP policies can only restrict it further. The inner HTML is escaped
as an attribute value, never interpolated as wrapper markup.

All `srcdoc` documents inherit the application's CSP. Deployment must keep that
policy compatible with artifact execution; this design cannot weaken an
existing host CSP. This is origin/storage isolation, not CPU/memory isolation.

### Bundle preparation

The entrypoint is parsed with `DOMParser` into an inert document: its scripts
do not run and nothing loads. Local references resolve relative to the file
they appear in, as if the bundle were served from a directory. Assets become
data URLs, linked stylesheets and `@import` rules are inlined recursively, and
a small scanner rewrites `url()` locations in stylesheets and `style`
attributes. Classic external scripts become embedded data URLs. Standalone
module scripts are possible, but arbitrary module graphs, workers, service
workers, runtime relative `fetch`, and multi-page navigation are not a virtual
filesystem: bundle those applications first. Use `src` rather than `srcset`.
External network resources are blocked by CSP; fetch required data/assets in
the agent's EYG program and include them in the bundle.

Paths, media types and sizes are validated before a snapshot is retained.
Missing resources produce a visible preparation error rather than loading a
URL from the application origin. A reference the scanner misses is still
blocked by the policy. Previews are memoised by bundle so streaming chat
updates do not reload them. Preparation is Gleam using plinth bindings, there
is no FFI in the overlay packages.

Binary values over 1 KiB in tool-result text are reported as `BinarySummary`
with a byte count, rather than base64. This is only presentation: the
interpreter and saved snapshots keep the full bytes. Fetch/decode or
fetch/create-artifact should happen in one program. Returning a video response
must not exhaust the model's context window.

### Layout modules

Layout is pure EYG, shared to the local hub by content ID:

- **Dwindle:** a binary split tree, successively subdividing the remaining tile
  and alternating horizontal and vertical splits.
- **Main and stack:** the first item occupies the main column; remaining items
  split the stack column vertically.

Both produce `{item, origin, size}` placements consumed by `Show`. Layout
modules do not need new effects. A common helper shows their placements.

### Viewers are ordinary content-addressed functions

The platform does not associate file extensions or schemas with applications.
It understands HTML bundles and generic revision metadata. Image carousels,
video players, and Bluesky lexicon viewers are ordinary EYG modules: their pure
functions accept data and return bundles. Callers reference their shared content
IDs, call the function, then use `Artifact` and `Show`. They can replace or fork
any viewer without changing the platform. Examples include a carousel of
bundled images, a video player with playback speed controls, and a viewer for
`app.bsky.feed.getAuthorFeed` JSON containing `app.bsky.feed.post` records. Data
retrieval remains in the calling program, separate from presentation.

## Artifact control

An agent that creates an artifact should check that it works and looks right.
Existing effects cannot see or use a rendered document, so a third effect,
`Puppet`, drives a shown preview. It is not specific to Overlay: any runtime
that renders HTML, for example the CLI with a headless browser, can implement
the same contract, and the same programs then test artifacts outside Overlay.

```eyg
perform Puppet({
  page: Artifact("departures"),
  locator: [Role({role: "button", name: "Refresh"})],
  action: Click({}),
  timeout: 5000
})
```

`page` is a shown `Artifact(name)` or `Revision({name, version})`. A locator
narrows from the whole document with `Css`, `Text`, `Role`, `Label`,
`Placeholder`, `TestId`, `HasText` and `Nth` steps. Actions follow Playwright:
interactions wait for exactly one visible, enabled element, queries return text,
counts and flags, `Expect` retries a condition until the timeout, and
`Screenshot` returns a PNG. `Puppet` returns `Ok(reply)` or `Error(reason)`, for
example when a locator matches several elements. The
[`playwright`](../eyg_packages/playwright/) package wraps the effect in
Playwright's names: `click(get_by_role(page("departures"), "button", "Refresh"))`.

### The puppet pattern

A sandboxed frame without `allow-same-origin` cannot be reached by the
application and cannot reach the application. Control is one way: a trusted
puppet script is the first script of every prepared document.

1. The application posts `{id, request}` to the artifact frame, below the
   wrapper, with a `MessagePort` for the reply. Frames that are still loading
   miss messages, so copies with the same id are sent with backoff.
2. The puppet only accepts messages whose source is the application window,
   acts once per id and posts the reply to every port it received for that id.
3. The application reads the reply from its own port, as data. It never runs
   code from an artifact.

An artifact can interfere with its own puppet, which only affects what is
reported about that artifact. It cannot reach another artifact's puppet
because the source of its messages is not the application. Text and images
read from an artifact are untrusted input to the agent, like fetched data.
The puppet outlines each element as it acts, so the user sees the agent at work.

### Screenshots

Screenshots render inside the sandbox. The document is cloned with the state of
form fields and canvases, serialized into SVG `foreignObject` and drawn to a
canvas. Bundles carry all their styles, so styles come from the document
itself; `:root` rules apply to the cloned `html` element and animations show
their final frame. Hover states and the scroll position of inner containers are
not captured. The most recent screenshots of a tool call are shown to the model
with its result and as thumbnails in the chat.

## Shared artifacts

Artifacts stay in the browser session until a person clicks share on a panel.
The version the panel shows is posted to the hub and the panel links to
`/artifact/<id>`. There is no effect for agents to share, publishing is always
a person's choice.

The hub checks the bundle with the same rules as `Artifact`, stores its files
and returns a random id. `/artifact/<id>` is a page showing the artifact in a
sandboxed frame. Files are served from `/artifacts/<id>/files/<path>`, so
relative references work without preparation. Every file response has a
content security policy beginning `sandbox allow-scripts`: documents get an
opaque origin and cannot read the hub's cookies or storage, they may load the
hub's files and data URLs, and connections, forms and other frames are blocked
as in local previews. Only the hub's own pages may frame the files.
`GET /artifacts/<id>` returns the bundle as JSON.

Ids are capability links, the hub has no index of artifacts. Shares are
limited per address. [Artifacts and Spring '83](../notes/artifacts-and-spring-83.md)
compares this with a protocol for publishing small HTML documents and lists
ideas that could follow, such as signed and content addressed artifacts.

### Verification

Test effect decoding and type checking, version retention across turns and
effect suspension, invalid bundles and rectangles, revision selection, and file
diffs. Run browser tests against actual nested frames: scripts and bundled
resources work, storage and parent access fail, injected CSP cannot relax
restrictions, and self-navigation makes no network request. Drive artifacts
through the puppet, including screenshots, and check another artifact cannot.
Check that shared files are sandboxed and nothing is shared without a click.
Test layout coverage, order, odd dimensions, empty and singleton inputs, and
zero-size rejection. Run the repository EYG suite before sharing modules.
