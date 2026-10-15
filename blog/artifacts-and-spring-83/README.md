---
name: Artifacts and Spring '83
description: Compare small HTML publishing with executable, versioned agent artifacts.
date: 2026-10-15
---

# Artifacts and Spring '83

The [29 June 2022 Spring '83 draft](https://github.com/robinsloan/spring-83/blob/main/draft-20220629.md)
describes signed HTML boards: one mutable fragment per publisher key, limited
to 2,217 bytes. Clients verify signatures, put boards in separate Shadow DOMs,
execute no board JavaScript and load no linked images, media or fonts. A 2D
display is encouraged; servers retain boards for 7–22 days. This is a draft
protocol comparison, not a claim about a deployed service.

Overlay also presents pieces of HTML together, but its
[artifacts](../../guides/overlay_artifacts.md) are applications an agent edits
and a person can inspect, control and share.

| Property | Spring '83 draft | Overlay artifact |
| --- | --- | --- |
| Unit | One HTML fragment per key | Bundle, up to 128 files and 2 MiB per snapshot |
| Code | Board scripts are inert | Scripts execute in an opaque-origin frame |
| Revisions | Board is replaced or cleared | Immutable revisions with diffs and reopening |
| Identity | Publisher's Ed25519 key | Session name; random ID for a hub share |
| Integrity | Signature verified by the client | Shared bytes served by the hub; no publisher signature |
| Lifetime | Server TTL | Session persistence and explicit hub withdrawal |
| Layout | Client-defined canvas | Pure EYG layout functions |

Shadow DOM scopes presentation; it is not an origin boundary for executable
code. Overlay therefore uses separate sandboxed frames and a restrictive CSP.
Bundled images, fonts and video are available, while external resource loads
are blocked. The checked artifact guide tests actual network isolation and
host-storage boundaries. Neither a frame nor CSP imposes CPU or heap quotas.

The Spring draft leaves discovery outside the protocol and restricts server
enumeration to reviewed publishers. Overlay's hub supplies no public listing
of shared artifacts. A link makes a share available, so possession of a link
still matters when deciding which bytes to publish.

Three ideas remain useful proposals. Signing a shared revision would make its
authorship independently verifiable. Content-addressing the complete bundle
could let another hub mirror it without changing its identity. Expiry could
bound anonymous retention, with an explicit distinction between an expired
share and a person's retained workspace.

Spring's migration link is another useful precedent. Overlay already links
successive shares using the previous share's ownership secret. A signed release
ledger could extend this into following a publisher's named artifact while
retaining immutable history. That ledger and signed artifacts are not current
features.
