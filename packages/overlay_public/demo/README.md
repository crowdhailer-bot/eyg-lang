# Artifacts demo

A recording of an agent in Overlay that builds, checks, controls and shares
artifacts.

The model's replies are scripted by [`mock_ollama.mjs`](./mock_ollama.mjs), a
local stand in for the Ollama chat API. Everything else is real: Overlay runs
the EYG programs in [`agent/`](./agent/), fetches live data from TfL and
Open-Meteo, previews each artifact in a sandbox, drives it through the puppet
and shares one to a hub. Replies that describe results read them from the tool
results Overlay sends back.

| Prompt | Programs |
| --- | --- |
| Build a live departures board for the bus stops at Camden Town Station | [`01-departures.eyg`](./agent/01-departures.eyg), [`02-check.eyg`](./agent/02-check.eyg) |
| Add the weather for the next few hours and a map of the routes | [`03-weather-and-map.eyg`](./agent/03-weather-and-map.eyg) |
| Only show the 24 and 88, and switch the board to light mode | [`04-routes-and-theme.eyg`](./agent/04-routes-and-theme.eyg) |

Then the person shares the board and opens its page on the hub.

## Studio context

[`studio.eyg`](./studio.eyg) is the context module of the session. Its readme
gives the agent design guidelines, components and an API. `studio.page` builds
a page on the design system and bundles Inter and JetBrains Mono, fetched from
jsDelivr, so artifacts look consistent without loading anything at runtime. The
module also has network helpers, the tiling layouts and the playwright library.

```sh
eyg script packages/overlay_public/demo/test.eyg
```

## Record

Requires a hub from this branch, the eyg CLI, Bun, Playwright's Chromium and
ffmpeg with libx264.

```sh
# packages/hub
(set -a; source ../eyg.run/.env; POSTGRES_HOST=localhost; PORT=8081; set +a; gleam dev migrate && gleam run)
```

```sh
# packages/overlay_public
EYG_HUB=http://127.0.0.1:8081 bun demo/record.mjs
```

The recorder shares the context to the hub, serves the mock on port 11434
(`OLLAMA_PORT`) and starts Vite on port 5380 (`OVERLAY_PORT`) with `/api`
proxied to the mock. It drives Chromium at 1600×900 with a device scale of 1.2,
drawing a pointer and captions into the page. DevTools screencast frames are
encoded with title and end cards to
[`recordings/overlay-artifacts.mp4`](../recordings/overlay-artifacts.mp4) at
1920×1080, the video is committed. Frames, stills and cards are made in the
ignored `recordings/work`. `VIDEO=0` rehearses the session and saves a
screenshot of each scene there instead.
