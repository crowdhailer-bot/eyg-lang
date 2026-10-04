# Overlay

This is the core package for building the overlay agents.
It is runtime and platform agnostic and is so far used in the `overlay_web` and `gleam_cli` packages.

It describes
- configuration
- system messages
- tools available

Currently the only tool available is `run` to run some EYG code with side effects.
All actions of an Overlay agent are expected to be conducted by running EYG code.
This allows all side effects to be managed in the same way.

## Configuration

All overlay configuration is managed by EYG programs.
For example starting the overlay agent in the CLI works as follows

```sh
eyg overlay path/to/.overlay.eyg
```

The `.overlay.eyg` file returns a record with the following fields:

- `llm` the model to use, `{provider, model}`.
  The providers in the CLI are `Ollama({origin: String, api_key: Option(String)})`,
  use `origin: "https://ollama.com"` for Ollama cloud or `"http://localhost:11434"` for a local server,
  `Mistral({api_key: String})`,
  and `OpenAI({origin: String, api_key: Option(String)})` for any OpenAI compatible API.
  `OpenAI` also accepts `path`, default `"/v1/chat/completions"`, and `headers`, a list of `{key, value}` records.
  `Bedrock({region: String, access_key_id: String, secret_access_key: String})` uses Amazon Bedrock, `session_token` can be given for temporary credentials.
  `Codex({access_token: String, account_id: String})` uses a ChatGPT subscription, `codex.read` in the overlay EYG package reads them from `~/.codex/auth.json`.
  A bare provider, e.g. `llm: Ollama({...})`, uses the default model `glm-5.3:cloud`.
- `policy` A record with a function for each effect the agent may perform, see [Policies](#policies).
- `context` Any value. It is in scope as the `context` variable of every program the agent runs.
  If it is a record with a string `readme` field the readme is added to the system prompt.

The config is type checked and then evaluated once when the session starts, it can perform effects such as reading files.
Each policy field must be a pure function from the effect's lift type to `Pass(lift) | Mock(lower)`.
The type of the context is given to the agent when there is no readme, and the agent's code is type checked against it before it runs.
Configuration errors name the field at fault but do not print values, as they often contain secrets.

An example configuration

```eyg
let {api_key} = import "./.env.eyg"

let read_text = (path) -> {
  match perform ReadFile({path, offset: 0, limit: 1000000}) {
    Ok(bytes) -> {
      match !string_from_binary(bytes) {
        Ok(text) -> { text }
        Error(_) -> { "" }
      }
    }
    Error(_) -> { "" }
  }
}

let pass = (lift) -> { Pass(lift) }

let policy = {
  read_file: (request) -> {
    match !string_ends_with(request.path, ".env.eyg") {
      True(_) -> { Mock(Error("secrets are not readable")) }
      False(_) -> { Pass(request) }
    }
  },
  read_directory: pass,
  cwd: pass,
  now: pass,
  standard_out: pass,
  fetch: pass,
  write_file: (_) -> { Mock(Error("read only access to the file system")) }
}

{
  llm: {
    provider: Ollama({origin: "https://ollama.com", api_key: Some(api_key)}),
    model: "glm-5.3:cloud"
  },
  policy: policy,
  context: {readme: read_text("./README.md")}
}
```

Always deny reading `.env.eyg` files, otherwise the agent can read the secrets they hold.

The overlay harness has no concept of skills or AGENT.md.
Instead because the configuration is fully scriptable it is expected to be implemented as EYG libraries.
The [overlay EYG package](../../eyg_packages/overlay/) has `policy` helpers, i.e. `read_only(roots)` and `allow_all`, and `skills` helpers to load `.agents/skills/*/SKILL.md` files.
It is not yet published so import it by path.

NOTE: Relative imports in the agent's code go through the same permission check as `ReadFile`

NOTE: in `overlay_web` the llm configuration is provided through the UI and there is no policy yet, every browser effect is allowed.

### Exporting chats

Type `/export [path]` at the prompt to save the chat as JSON in the opencode session export format.
Tool results are recorded in the state of the tool parts of the assistant message that called them.
Overlay does not record when each message was sent so all timestamps are the export time.

### Policies

A policy field is named as the effect label in snake case, i.e. `read_file` for `ReadFile` and `cwd` for `CWD`.
The function receives the value the program performed the effect with and returns:

- `Pass(value)` to perform the effect, the value can be modified, i.e. to add an authorization header.
- `Mock(value)` to resume the program with `value` without performing the effect, i.e. `Mock(Error("denied"))`.
- `Ask({question, denied})` to ask the user, if they answer `y` the effect is performed otherwise the program resumes with `denied`.

File paths given to the policy, and the path of relative imports checked by `read_file`, are absolute.
They are resolved from the directory of the code performing the effect, for the agent's code that is the working directory.

An effect without a policy field is refused, the program is aborted with an explanation.
`DecodeJSON`, `EYGParse` and `Hash` do no IO and are always allowed.
An unknown field is an error when the agent starts, the error lists the valid field names.

Policy functions are pure, they cannot perform effects.

An optional `audit` field in the config is called with `{effect, input, decision}` for every effect the agent performs.
The decision is `pass`, `mock` or `refused`, and `input` is the effect's value as text.
The audit function can perform effects, i.e. append to a log file, and is not checked by the policy.

With a `state` field in the config every rule is also given the current state and returns `{decision, state}`.
The state lasts for the whole session, i.e. to allow an effect only once:

```eyg
state: 0,
policy: {
  now: (lift, count) -> {
    match !int_compare(count, 1) {
      Lt(_) -> { {decision: Pass(lift), state: !int_add(count, 1)} }
      | (_) -> { {decision: Mock(0), state: count} }
    }
  }
}
```

A `reference` field limits which published modules the agent's code can load.
It is given the reference as text, i.e. `@standard`, `@standard:1` or `#<cid>`, and returns `Pass(reference)` or `Mock(reason)`.
References are checked before the code is type checked, so a denied module is never fetched.
Without the field every reference is loaded, the dependencies of a loaded module are trusted.

An optional `context_policy` applies to effects performed by code from the config's files, such as functions in the context.
The agent can then be limited to the context's API, i.e. reading a file only through a context function.
Code from published modules uses `policy`, even when called by a context function.

Do not allow `standard_in`, it reads all remaining input which is the input for the chat.

Write policies in a module of their own that takes values, such as the project root, as arguments.
The module is pure so can be tested with `eyg eval` or a test suite, the config performs the effects and passes in the values.

### Conventions

Projects define their own specific rules in an `.overlay.eyg`.
This allows precise control over what an agent can access.
A project can define multiple i.e. `.overlay.planner.eyg` that can only read files in this directory
or `overlay.search.eyg` that can read README files from any directory.

Secrets can be kept from the agent by adding them to requests in the policy functions.
A fetch policy can check the request origin and if known add an authorization token.
If keeping secrets on the file system the should still be structured, so convention is a `.env.eyg` file that is gitignored.

## Development

```sh
gleam test
```

## Plans

Add a helper that would check that all env files have the same type.
If possible this would be built in EYG and added to an `entry.eyg` file.
This might require an effect, like EYGParse, but that takes a flat AST and checks it.
A flat representation of types would also be needed.

Create an `Overlay({llm, policy, context})` effect available in the CLI.
This would allow users to define scripts and agents of a project in the same `entry.eyg` file.
Benefits are less files, EYG tries to make structuring using the file system optional.
It is potentially not necessary as an Overlay agent could be implemented purely in EYG in the future.
Implementing a pure EYG agent is blocked by their not being `Eval` capabilities.

Replace the non interactive terminal implementation with an interactive one.
This could be built in Gleam with existing TUI libraries but this might not give the control performance required.
Another option would be to rebuild the the CLI on another technology, opentui is a prefered direction here.
This would allow a rich Overlay agent UI in the terminal but would also allow reimplementing the structured editor as a TUI.

Add a generator, `eyg @overlay.generate .`, that adds overlay configuration to a project.
It would create `.overlay.eyg`, an `.env.eyg` and gitignore the env file.
This requires the `overlay` EYG package to be published.

Publish the `overlay` EYG package so configs can use `@overlay.policy` and `@overlay.skills` rather than importing by path.

Add an export button to the web overlay, downloading the chat with `overlay/export`.
