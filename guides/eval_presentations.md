---
name: Presenting agent evaluations
description: Read the eval articles and rebuild the offline talk from its Gleam controller.
---

# Presenting agent evaluations

The [effect evals series](../blog/effect-evals/README.md) explains sessions,
deterministic checks, judges, uncertainty and contexts. The
[38-slide talk](../blog/effect-evals/slides.html) and
[printable PDF](../blog/effect-evals/slides.pdf) retain the source branch's
historical design discussion. Model results are historical, and its remaining
hardening claims describe the original design. The [eval](./overlay_evals.md)
and [sandbox](./sandbox.md) guides describe the current implementation.

Open slides.html directly from disk. Arrow keys, Page Up/Down and Space move
between slides; Home/End jump to the ends. The selector jumps to any slide.
N toggles speaker notes, F toggles fullscreen, and P opens printing. Input
controls retain their normal keys. The reliability sliders illustrate independent
attempts; they are not measured results or finite-sample estimates.

Edit blog/effect-evals/slides.template.html for content and styles. The browser
controller is tracing/eval_slides.gleam, with native DOM bindings in plinthx.
From packages/tracing:

```sh
bun install
gleam run -m tracing/build_slides
gleam test
gleam test --runtime node
CHROME_BIN=/absolute/path/to/chromium gleam run -m tracing/eval_slides_demo
```

The build embeds compiled Gleam in the HTML, so it works offline. The last
command checks navigation, notes, probability controls, fullscreen and resizing
in a real browser, then regenerates the PDF. It also makes the
[checked recording](../packages/tracing/recordings/effect-evals.webm).
Print export includes every slide and restores the selected slide afterward.
No model request is made by these checks.
