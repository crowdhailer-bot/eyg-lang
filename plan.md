Overlay needs to be able to produce and validate artifacts.
That is what this branch is demonstrating

Tasks

- [x] effect to create artifact
- [x] effect to show artifact
- [x] implement the puppet pattern to control the artifact, see puppet.md
- [x] implement a screenshot command for the artifact
- [x] implement an EYG playwright library that follows the playwrite API but instead postsMessage to the puppet script inside the iframe.
- [x] Do not use ffi in overlay_web or overlay_public instead add plinth (and gitignore) as a package and suggest changes to plinth.
- [x] Compare and contrast the artifacts idea with the Spring 83 protocol.
- [x] Add backend support in the hub for creating artifacts. /artifact/:uuid should show the artifact.
    - It should be possible to create artifacts locally without them ending up in the artifacts service.
    - When share is clicked they are transparently moved to the artifact service.
- [x] Create a polished video. Mock responses from calls to ollama local. Create a test artifacts context with very strong modern design guidelines. the returned response should create a fresh modern crisp artifacts for everything it's showing. 
- [x] Review the video, check it really is impressive and improve until it is.
- [x] rework this branch in the following order
    - idependent fixes that could be merged without any features
    - Local artifacts
    - artifact control
    - remote and shared artifacts.

Future work found along the way

- [x] Withdraw a shared artifact from the hub, the denylist Spring '83 requires.
- [x] Show people when the agent takes a screenshot, a flash over the preview.
- [x] Show the artifact workspace before the first artifact.
- [x] Check bundles with one set of rules in Overlay and the hub, `eyg/hub/artifact` in `gleam_hub`.
- [ ] Release the plinth bindings, then depend on plinth from hex in `pal` and `overlay_public` instead of the local clone.
      Needs a fork of plinth for the bot, or a maintainer to apply the branch.
- [ ] Sign shared artifacts with the sharer's signatory key, so copies can be verified without trusting the hub.
      Not attempted, signatory keys live in the CLI's store and Overlay has none, keys in the browser need a design.
- [ ] Expire anonymous shares. Not attempted, a policy decision: Spring '83 forgets boards after at most 22 days.
- [x] Point a shared artifact to its newer version, like Spring '83 `<link rel="next">`.
- [ ] Puppet outside the browser, a CLI handler driving a headless browser, so scripts can check artifacts too.
      Not attempted, the CLI has no browser driver yet.

## Notes

### Branch

`main..artifacts` is the reworked history, rebased on `main` at "newsletter issue 11".
The original single commit is kept locally as `artifacts-original`.

1. Independent fixes: chat scrolling, binary summaries in tool results, browser tests with a scripted agent, `PORT` for the hub, `OLLAMA_ORIGIN` for the dev server.
2. Local artifacts: local plinth, `Artifact` and `Show`, bundle inlining, sandboxed workspace panels, tiling, viewers, guide.
3. Artifact control: `RequestFrame` in pal, `Puppet`, the puppet script, screenshots, the EYG playwright library, guide.
4. Remote and shared artifacts: bundle rules moved to `eyg_hub`, hub storage, sandboxed serving and `/artifact/<id>`, share button, Spring '83 note, guide, withdrawing, links to newer versions.
5. Demo: workspace polish, the studio context, the recorder and the video.

The first demo (real Ollama, live data, `speed-up-thinking.py`) was dropped, python is not used and the scripted demo replaces it.

### Video

`packages/overlay_public/recordings/overlay-artifacts.mp4`, 66 seconds, recorded with `EYG_HUB=http://127.0.0.1:8081 bun demo/record.mjs`.
The video is committed, frames, stills and cards are made in the ignored `recordings/work`.

- Model replies are scripted by a local mock of the Ollama chat API, everything else is real: programs, live TfL and Open-Meteo data, previews, puppet and hub.
- Frames come from the DevTools screencast. Preparing large previews blocks the page for up to 2s, the recorder shortens such frame gaps.
  A 1px heartbeat keeps the page repainting so only stalls are shortened.
- Reviewed five takes from contact sheets, caption strips, brightness of the workspace per frame and full frames. Fixed:
  a blank opening (empty workspace state), captions covering artifacts, the shared page falling back from Inter (fonts need CORS from an opaque origin),
  cards overlapping their stills, an invisible screenshot flash (encoding blocked painting),
  code expanding only after the turn and never collapsing (Playwright's click waits for the scrolling chat to settle, the recorder dispatches the click),
  and a caption replaced before it could be read (captions now stay up at least 2.8s).
- New previews are blank for about 0.4s while they load, left as is.

### plinth

- Bindings are on branch `overlay-artifacts` of the clone at `packages/plinth`, three commits:
  a fix for `element.query_selector` returning a JS `Error` and `add_event_listener` not returning a remover,
  DOMParser, `document_element`, `outer_html`/`inner_html`/`local_name`/`has_attribute`,
  and iframe `content_window`, `window_proxy.frame`, `post_message_with_transfer`, `MessageChannel`, `MessagePort`.
- The bot key cannot push to CrowdHailer/plinth and there is no crowdhailer-bot fork, so the branch is local only.

### CI

Runs on crowdhailer-bot/eyg-lang, read from the public API.

- `pal`, `overlay_web`, `overlay_public` and `website` fail, `gleam deps download` needs `packages/plinth`.
  `overlay_web` and `website` also fail on `main` at "newsletter issue 11".
- `test-db` fails at `gleam dev migrate` on the fork, also for the fork's `js-compiler` branch which does not change the hub.
  The migrations apply to a fresh local database and the hub tests pass locally, the log needs a sign in.
- `gleam_cli` failed on two of four pushes, it passes locally (105 tests) when `TEMP` is writable for birdie snapshots.
- `.agents/scratch/github_runs.eyg` in mono imports `dark/gh_actions` from a `dark-gh` branch that is on neither remote.

### Decisions

- Previews parse with DOMParser rather than a template, keeping `<html>` attributes and `<head>`.
  A leading `<script>` is now in the head, as when the file is opened directly, so `document.body` is null there.
- `css-tree` is replaced by a scanner in `overlay_web` (`artifact/css.gleam`), a missed reference is still blocked by the CSP.
- `gleam/uri` on JavaScript parses `./a.css` with scheme `.`, bundle references are resolved by hand in `artifact/inline.gleam`.
- Binary summaries only apply over 1 KiB and no longer cut nested values at depth 8.
- The puppet talks over a `MessageChannel` transferred with each request, with no ack step.
  Requests are resent with backoff under one id, the puppet acts once per id and replies to every port.
  It checks `event.source === parent.parent`, so one artifact cannot drive another (browser tested).
- Screenshots serialize a clone of the document into SVG `foreignObject`, which matched real rendering closely,
  including `:root` tokens, pseudo elements, canvases and form state. Animations are frozen at their end.
  No html2canvas, it would have to be inlined into every preview as the CSP blocks CDNs.
- Locators are records narrowed by functions, not objects with methods: EYG has no recursive types.
- Bundle rules live in `eyg/hub/artifact`, Overlay converts its files to `ArtifactFile` to check them.
  Both import it `as rules`, the hub controller has an `artifact` variable.
- Shared files are served from `/artifacts/<id>/files/<path>` with a CSP starting `sandbox allow-scripts`.
  Checked in Chromium: `'self'` still matches the hub under the sandbox, relative CSS, scripts and images load,
  the origin is `null` and cookies, storage, parent access and fetch are blocked.
  File responses allow any origin, fonts and module scripts from an opaque origin are CORS requests.
- Withdrawn artifacts are not found rather than gone, like Spring '83 treating expired and unknown boards the same.
- Sharing has no effect, an agent cannot publish, only a person clicking share.
- A newer version is linked with a secret returned when the earlier version was shared, a capability rather than an identity.
  The hub keeps its SHA-256, Overlay keeps it in the session, so after a reload a new share starts unlinked. Signatures could replace it.

### Environment

- Use the eyg CLI release in `mono/tmp/eyg-0.0.5`, the `eyg` on PATH is an old local build without `StandardOut` in scripts.
  The viewers browser tests run `eyg run`, put the release first on PATH.
- Node for Playwright is in `mono/tmp/node-v24.15.0-linux-x64/bin`, Playwright's Chromium 1243 is installed.
- Old agent sessions left servers on 5173 (`bun serve.js`), 8001 (`python -m http.server`) and 8080 (`gleam run` hub, Sep 2).
  Run browser tests with `OVERLAY_PORT` set to a free port.
- Vite can hang on a request made while vite-gleam runs `gleam build`,
  so Playwright waits for Vite's `ready in` output instead of polling a URL.
- The dev database on localhost:5432 has the `artifacts` migration applied. Start a dev hub from this branch with `PORT=8081` for recordings, see `packages/overlay_public/demo/README.md`.
  Editing the unreleased migration needs `gleam dev rollback 1` then `gleam dev migrate`, which drops the dev artifacts.
- Never `git add packages`, the checkout has untracked user files under `packages/gleam_compiler` and `packages/soundness`.
