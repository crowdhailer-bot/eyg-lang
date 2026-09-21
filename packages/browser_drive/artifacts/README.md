# Recorded walkthroughs

Captured on 2026-09-21 with Chromium through Playwright 1.63.0.
The assistant uses the mocked provider and the real EYG interpreter in every
recording. MP4 files use H.264 and fast-start metadata; there is no audio.

| File | Duration | Content |
| --- | --- | --- |
| [di-demo.mp4](di-demo.mp4) | 35 seconds | Local injection recipe, chart enlargement, hover, code, focus toggle, docking and dragging |
| [sj-demo.mp4](sj-demo.mp4) | 31 seconds | Local injection recipe, computed shortlist, expanded effects/code, toggle and panel controls |
| [di-live.mp4](di-live.mp4) | 46 seconds | Actual di.se, local bundle injection, larger plotted chart, hover and working focus toggle |
| [sj-live.mp4](sj-live.mp4) | 41 seconds | Actual sj.se, journey search, local bundle injection, price-based direct-train shortlist and toggle |

The local pages are clearly labeled recreations with fictional data. The live
recordings use the sites' real DOM and the prices displayed at capture time.
No ticket was purchased. Optional cookies were rejected.
The injection card is a recording aid that inserts the real built bundle; it
does not impersonate the browser's developer tools. Pasting the bundle into a
DevTools snippet provides the equivalent manual workflow.

The `*-before.png` and `*-after.png` files show the states before and after
the conversations. `gallery.png` and `gallery-mobile.png` capture the demo
landing page. The text transcripts preserve the visible effect traces.

## Validation

- `npm test`: 10 browser tests passed using the repository's parser/interpreter.
- `npm run check`: Gleam and JavaScript/CSS/HTML formatting passed.
- Both recorders assert the resulting DOM before saving the final videos.
- MP4 durations and encodings were checked with `ffprobe`.
- Tested with Gleam 1.16.0 and Node.js 24.15.0.

The separate repository command `eyg script entry.eyg` was attempted. The
installed `eyg 0.0.0` executable fails in
`src/eyg/parser/lexer.gleam:byte_slice_range` with a pattern-match error before
reporting test results. This is outside the browser-drive test suite; no
`eyg_packages` files were changed.

Regenerate with `npm run record` and `npm run record:live`. These commands start
their own local server and require Chromium and `ffmpeg`. Live recordings depend
on the sites' current markup and journey availability.
