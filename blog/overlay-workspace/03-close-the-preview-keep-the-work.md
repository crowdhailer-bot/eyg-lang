---
name: Close the preview. Keep the work.
description: Reopen saved artifacts and revision history directly from the empty workspace, without another model call.
date: 2026-10-04
---

# Close the preview. Keep the work.

A closed preview should mean less on the screen, not work you have to ask an
agent to find again.

When you close every preview, Overlay now shows the artifacts still in your
workspace. Each entry gives you its name, its version count and two choices:
**Open** the latest version, or inspect its **History**.

No prompt is needed. Opening a saved artifact uses the files already in your
tab and makes no model call. History opens the same revision inspector used by
the live workspace, so earlier versions stay a click away.

The list also returns after a refresh once the workspace has been saved. You
can clear the canvas, reload the page and choose where to continue. Closing a
panel changes your view; it does not delete the artifact.

The browser regression follows that whole path: create two versions, close
the last preview, refresh, inspect history and reopen the latest version.
It checks that the model request count stays unchanged while navigating.

Less clutter, with the next step still in reach.
