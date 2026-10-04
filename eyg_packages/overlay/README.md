# overlay

EYG helpers for configuring [overlay agents](../../packages/overlay/README.md).

## policy

Policies for an overlay agent's `.overlay.eyg`, in the CLI's `Pass`/`Mock` vocabulary.
An effect without a policy field is refused, so only list what the agent may do.
File paths given to policies are absolute.

```eyg
let {policy} = import "<path to>/eyg_packages/overlay/index.eyg"
let root = match perform CWD({}) { Ok(cwd) -> { cwd } Error(_) -> { "/" } }

// read anything in the project, never .env.eyg files
let rules = policy.read_only([root])
// use every effect but writing files
let relaxed = {write_file: policy.deny("read only"), ..policy.allow_all}
```

- `allow_all` every effect except `Exit` and `StandardIn`, reading `.env.eyg` files is denied.
- `read_only(roots)` read files under the absolute roots, plus effects that only observe such as `Now` and `StandardOut`.
- `read_write(roots)` as `read_only` and write, append, delete and make directories under the roots.
- `pass`, `deny(reason)` single rules, `deny` mocks an `Error(reason)`.
- `under(effect, roots, path_of)` allow a file effect under roots.
- `hide_secrets(read_file)` deny reading `.env.eyg` files.
- `with_header(host, key, value, otherwise)` add a header, i.e. an API token, to requests for a host.
- `fetch_hosts(hosts)` allow https requests to the listed hosts.

Record update can only overwrite fields, to change a rule overwrite it `{write_file: policy.deny("no"), ..policy.allow_all}`.
To add a rule to `read_only` build the record listing all the fields you need.

## codex

Use a ChatGPT subscription as the model, after logging in with `codex login`.

```eyg
let {codex} = import "<path to>/eyg_packages/overlay/index.eyg"
let provider = match codex.read("/home/me/.codex/auth.json") {
  Ok(provider) -> { provider }
  Error(reason) -> { !never(perform Abort(reason)) }
}
// llm: {provider, model: "gpt-5.5"}
```

`codex.refresh(path)` exchanges the refresh token for new tokens, writes them back to the file, and returns the provider.
Use it when `read` gives a provider that is rejected because its token expired.

Deny the agent reading the auth file.

## skills

The overlay harness has no concept of skills, they are loaded by the config.
A skill is a file `<root>/.agents/skills/<dir>/SKILL.md` with `name` and `description` frontmatter.

```eyg
let {skills} = import "<path to>/eyg_packages/overlay/index.eyg"
let found = skills.read(root)
let readme = !string_append("This project...", skills.print(found))
// context: {readme, skills: found}
```

- `read(root)` every skill under the absolute root as `{name, description, path, body}`.
- `print(skills)` a readme section listing the skills.
- `parse(text, fallback_name)` parse one skill file.
- `read_text(path)` read a utf-8 file, the path must be absolute.
