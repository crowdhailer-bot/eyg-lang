# Gleam Playwright

Thin bindings to the Playwright JavaScript library. Browser workflows, assertions,
mock services and video scripts are written in Gleam. Platform APIs belong in
`plinthx`; this package only adapts Playwright calls and promise failures.

Run `bun install` and `bunx playwright install chromium` before building a
consumer. Pass an empty executable path to `launch` for Playwright's browser,
or supply a custom Chromium path. Create a recording context, retain the page's
`video`, and close the context before `save_video` so the video finishes writing.
