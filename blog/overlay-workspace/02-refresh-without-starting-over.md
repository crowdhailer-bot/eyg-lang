---
name: Refresh without starting over
description: Overlay now restores completed artifact work, including revisions and layout, in the same browser tab.
date: 2026-10-04
---

# Refresh without starting over

You have a working page in one panel and an earlier revision beside it. The
conversation explains what changed. Refresh should bring back the work you
were looking at.

Overlay now restores completed artifact work in the same browser tab. Your
files, revision history, panel positions and completed sharing links come back
with the conversation. Bundled images, styles and scripts stay with their
revision, so an old preview remains the old preview.

## Continue from the version you chose

The workspace saves after a completed agent turn and when you change its layout
while the agent is idle. Closing a panel keeps it closed after a refresh;
the artifact's history remains available. A shared version retains the
information needed to link a later share to it. Completed sharing links are
saved immediately, including while the agent is still working.

Nothing is published by saving or restoring the workspace. Sharing remains a
separate action you choose. Artifact code still runs in its isolated preview,
without access to the application's session storage.

## Know when the work is saved

The workspace shows **Saved in this tab** once the browser has accepted a
snapshot. If its storage quota is full, the live work stays on screen and a
**Retry saving** action appears. A storage problem should be visible while you
can still act on it.

This is recovery within a tab, not permanent backup. Closing the tab clears
its session storage, a running turn can have unsaved changes, and browser
storage limits can be smaller than Overlay's artifact history limit. Keep the
tab open until changes are saved.

Restoration uses the same file, path and size validation as a new artifact.
Corrupt or unsupported snapshots produce a readable message. A late storage
reply cannot replace work you've already created.

The new regressions cover real refreshes, bundled styles, older revisions,
closed panels, sharing continuity and storage failures. The result is a small
but useful promise: a refresh can be a refresh, without rebuilding the page
that was already working.
