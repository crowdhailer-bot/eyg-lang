---
name: Take your workspace with you
description: Download artifact files, revisions and layout, then reopen them in a new Overlay tab without a model call.
date: 2026-10-04
---

# Take your workspace with you

Your artifact work can now leave the tab as a file.

Choose **Download workspace** to keep the files, their revision history and the
layout you were using. Open a new Overlay tab, choose **Import workspace**, and
continue from the same previews. Bundled styles and images come with them.
There is no model call to recreate what already exists.

This also gives you a way to keep work when the browser's session storage is
full. Download uses the live workspace, so a failed automatic save does not
prevent you from taking a copy.

## A copy of the work

The workspace file contains artifact contents. It leaves out provider
credentials, conversation history and the secrets that control existing public
shares. An imported artifact can be shared as its own copy; it does not take
over the original's links.

Imports open only in an empty, idle workspace. They pass the same validation
as artifacts created in Overlay, and a late file read cannot replace work you
have started while it was loading. Invalid files explain the problem and leave
the empty workspace ready for another choice. The import limit is 32 MiB.

The browser test follows the complete trip: create two revisions, share one,
download the workspace, import it in another tab and refresh that tab. It
checks the bundled styling, confirms that private keys are absent from the
file and verifies that importing makes no model request.

Build in the tab. Keep a copy where you keep your work.
