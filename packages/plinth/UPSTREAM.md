# Plinth source

Vendored from CrowdHailer/plinth at `ba246f26ff05ef933a5e1664def8d59ffbde317d`.
The Apache-2.0 license is retained in LICENSE. Local additions provide native
Fetch Request/Response and queueMicrotask bindings used by terminal hosts.
Browser APIs belong here even when Bun or Node implements them.

Keep these additions small and suitable for upstreaming. Consumers use a path
dependency so the bindings are available in a fresh checkout without an
unpublished remote branch.
