---
name: Artifacts and Spring '83
description: How Overlay artifacts compare with Spring '83 boards, and ideas worth borrowing.
date: 2026-09-16
---

[Spring '83](https://github.com/robinsloan/spring-83) (draft 2022-06-29) is a
protocol for following publishers through boards: fragments of HTML up to 2217
bytes, displayed side by side on a 2D canvas. Overlay artifacts are also small
HTML documents arranged on a 2D canvas, but they answer a different question.
A board is how a person speaks to followers. An artifact is how an agent shows
its work to the person it works for, who may then share it.

## Alike

- **HTML is the unit.** Neither defines schemas for content, the richness of
  HTML and CSS is the point. Viewers and layouts in Overlay are EYG modules,
  not platform features, much as Spring leaves display to clients.
- **A canvas of pieces.** Spring clients juxtapose boards on a 2D canvas at an
  aspect ratio of roughly 1:√2. `Show` places panels on a 1000 × 1000
  workspace, tiled by pure EYG layouts.
- **Nothing loads from outside.** Boards may not load images, media or fonts,
  for privacy (no tracking pixels) and safety. Artifacts can have images, fonts
  and video, but only bundled files: the content security policy blocks every
  network request, so the privacy property is the same.
- **No enumeration, pull only.** A Spring server must not list boards it has not
  reviewed. The hub has no index of shared artifacts, a link is the only way in.
- **A wrapper for browsers.** A Spring server may wrap a board in an
  informative page for browsers, as `/artifact/<id>` wraps a shared artifact.

## Different

| | Spring '83 board | Overlay artifact |
| --- | --- | --- |
| Author | a publisher's keypair | an agent's program, shared by a person |
| Size | 2217 bytes, one fragment | 128 files, 2 MiB |
| Scripts | never run, isolation is Shadow DOM plus CSP | run in a sandboxed frame with an opaque origin |
| History | none, one board per key is amended or erased | every save is an immutable version with diffs |
| Identity | Ed25519 key with an expiry baked into its suffix | a name in the session, a random id once shared |
| Integrity | signed, clients verify every board | trusted to the hub, no signature |
| Lifetime | 7 to 22 day TTL on servers | local for the session, shared artifacts are kept |
| Abuse | key generation puzzle, denylist, 429 | size limits and a per address rate limit |
| Interaction | none, forms and links at most | agents drive artifacts through the puppet |

Scripts are the root of most differences. Spring clients must not run a board's
JavaScript, and a board in a Shadow DOM of the client's page would run with the
client's privileges. An opaque origin iframe can run scripts safely, so an
artifact can be an application, and an agent can check that application with
`Puppet`. The cost is weight: a frame per artifact, where Spring renders each
board in a Shadow DOM of one page.

Spring's missing history is deliberate, "a whiteboard that is amended or
erased". Artifacts keep every version because an agent edits in steps and a
person needs to see and undo what changed.

## Worth borrowing

1. **Signatures.** EYG already has signatories with Ed25519 keys for package
   releases. A shared artifact could be signed by the person sharing it, so any
   copy can be verified without trusting the hub.
2. **Content addresses.** Hashing a bundle would make a shared artifact an
   immutable reference that any hub can mirror, like EYG modules. Spring gets
   portability from keys, EYG gets it from content ids.
3. **A board as a release log.** One board per key maps onto the package ledger:
   a signatory publishes versions of a named artifact and followers pull the
   latest. Following would come for free, with history kept.
4. **Expiry for anonymous shares.** Spring servers forget boards after at most
   22 days, and keys expire within two years to keep relationships "live" and
   engaged. Unsigned shares could expire while signed ones persist.
5. **A denylist.** Spring requires one and proves it with an infernal key. The
   hub can withdraw a shared artifact, which is then not found, as Spring
   treats expired and unknown boards alike.
6. **Migration links.** `<link rel="next">` moves followers to a new key or
   server. A shared artifact could point to its newer version the same way.
