---
name: release process
description: Notes on release tags, nightly builds and installer latest resolution.
---

## Tagging

The repository currently has one GitHub release stream: the EYG CLI.
Stable release tags still use the package prefix:

```text
gleam_cli-v0.0.2
```

Plain tags such as `v0.0.2` would also work while there is only one
release stream, and they would make pinned installer commands shorter.
However the prefixed tag is kept because it matches the package tag
prefix already declared in `packages/gleam_cli/gleam.toml`, leaves room
for package-specific tags elsewhere in the repository, and makes old and
new CLI release tags consistent.

Do not try to hide the prefix by giving the GitHub release a bare title
such as `v0.0.2`. GitHub releases are attached to git tags, so the tag
remains visible in the release URL, API response and pinned installer
argument. The stable release title should instead be explicit:

```text
Gleam CLI v0.0.2
```

The CLI nightly build uses the moving tag `gleam_cli-nightly`. Stable CLI
release automation should match `gleam_cli-v*`, not `gleam_cli-*`, so the
nightly tag cannot trigger the stable release workflow.

## CLI Release Workflow

The CLI release workflow handles both release kinds:

- branch pushes build a nightly release for the pushed commit SHA
- `gleam_cli-v*` tag pushes build a stable release for that tag

The workflow can safely push the moving `gleam_cli-nightly` tag because it
only listens for stable `gleam_cli-v*` tags. Updating `gleam_cli-nightly`
therefore will not recursively trigger another stable release run.

## GitHub Latest

GitHub has one `latest` release per repository. It does not have separate
`latest` releases per tool.

This means `/releases/latest` only works for installers when the repository
has a single release stream, or when every latest release contains assets
for every tool. If another tool publishes a newer release, then
`/releases/latest/download/eyg-linux-x64` will point at that other tool's
release and the CLI asset may not exist.

For independent tools in one repository, installers should not rely on
`/releases/latest`. They should resolve the latest release matching their
own tag prefix, then download assets from that explicit tag.

## Installer Latest Resolution

The installer should support both forms:

```sh
install.sh                 # resolves latest gleam_cli-v* release
install.sh gleam_cli-v0.0.2 # installs a pinned release
```

For `latest`, query the releases list endpoint and filter by tag prefix.
The robust form uses `jq` so drafts and prereleases can be ignored:

```sh
REPO="CrowdHailer/eyg-lang"
TAG_PREFIX="gleam_cli-v"
VERSION="${1:-latest}"

if [ "$VERSION" = "latest" ]; then
  VERSION="$(
    curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=100" |
      jq -r --arg prefix "$TAG_PREFIX" '
        [
          .[]
          | select(.draft == false)
          | select(.prerelease == false)
          | select(.tag_name | startswith($prefix))
        ]
        | sort_by(.created_at)
        | reverse
        | .[0].tag_name // empty
      '
  )"

  if [ -z "$VERSION" ]; then
    echo "no release found with tag prefix: $TAG_PREFIX" >&2
    exit 1
  fi
fi

base="https://github.com/$REPO/releases/download/$VERSION"
```

The rest of the installer can continue to download and verify assets from
that explicit tag:

```sh
curl -fsSL "$base/$asset" -o "$tmp/$asset"
curl -fsSL "$base/SHA256SUMS" -o "$tmp/SHA256SUMS"
```

If `jq` is not acceptable for the one-command installer, either require a
pinned tag for dependency-free installs or use a simpler parser for the
predictable tag format:

```sh
VERSION="$(
  curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=100" |
    sed -n 's/.*"tag_name": "\(gleam_cli-v[^"]*\)".*/\1/p' |
    head -n 1
)"
```

The `sed` form depends on GitHub returning releases newest-first and does
not inspect `draft` or `prerelease`, so prefer the `jq` form when possible.
