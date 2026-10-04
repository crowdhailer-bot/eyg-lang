---
name: Artifact workspace imports
description: Why portable imports start in an empty tab and use a selected-file browser operation.
date: 2026-10-04
---

Import starts in an empty, idle workspace. Merging would require a naming and
revision policy: panels and shares refer to an artifact by name and version,
so appending histories with colliding names would change those references.
The file-read completion checks the workspace again to preserve work begun
while the read was pending.

Portable copies omit sharing secrets. They preserve content and layout,
without granting control of the original public links.

Pal's `ReadTextFile` reads a native File explicitly selected by the person.
The existing directory-handle operations cannot read that object. It is a
reusable browser text-import operation with read failures as values, not a new
EYG effect or an additional agent capability. The native File check is in Plinth.
