//// Scripted runs of the playground, replayed with mocked Jev answers for recordings.
//// Each demo has a task and the program Jev should end up with,
//// the actions are found by synthesis so they stay in step with the editor.

import eyg/parser
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import jev_playground/action.{type Action}
import jev_playground/agent
import jev_playground/compound
import jev_playground/environment.{type Environment}
import jev_playground/options
import jev_playground/synthesis
import jev_playground/vocabulary
import morph/editable as e

pub type Demo {
  Demo(
    slug: String,
    title: String,
    task: String,
    target: Target,
    environment: Environment,
    config: options.Config,
    /// Add a list of the names and literals in the target to the task,
    /// Jev chooses from offered names and literals so it needs them spelled out.
    spec: Bool,
  )
}

/// The program Jev should end up with.
pub type Target {
  Code(source: String)
  /// The source of a library, as loaded into the environment, without some definitions.
  LibrarySource(name: String, without: List(String))
}

pub fn all() -> List(Demo) {
  [github(), http(), http_compound(), github_library()]
}

pub fn find(slug) {
  list.find(all(), fn(demo) { demo.slug == slug })
}

/// The task and scripted actions once the environment, with any libraries, is known.
pub type Prepared {
  Prepared(task: String, actions: List(Action))
}

pub fn prepare(
  demo: Demo,
  environment: Environment,
) -> Result(Prepared, String) {
  use target <- result.try(target(demo, environment))
  let task = case demo.spec {
    True -> demo.task <> "\n" <> spec(target)
    False -> demo.task
  }
  use actions <- result.map(synthesis.script(target, environment))
  // Libraries the program uses are opened first, when Jev can search for them.
  let opened = case demo.config.search_libraries {
    True ->
      vocabulary.references(target)
      |> list.filter(fn(package) {
        !list.contains(demo.config.open_libraries, package)
      })
      |> list.map(action.OpenLibrary)
    False -> []
  }
  let actions =
    list.flatten([opened, actions, [action.RunTests, action.Finish]])
  let actions = case demo.config.compounds {
    [] -> actions
    _ ->
      compound.compress(
        actions,
        agent.new(task, e.Vacant, environment, demo.config),
      )
  }
  Prepared(task:, actions:)
}

/// The actions Jev is scripted to choose, ending by running the tests and finishing.
pub fn script(
  demo: Demo,
  environment: Environment,
) -> Result(List(Action), String) {
  prepare(demo, environment) |> result.map(fn(prepared) { prepared.actions })
}

pub fn target(demo: Demo, environment) -> Result(e.Expression, String) {
  case demo.target {
    Code(source) ->
      parser.all_from_string(source)
      |> result.map(e.from_annotated)
      |> result.replace_error(
        "the target of " <> demo.slug <> " does not parse",
      )
    LibrarySource(name, without) ->
      environment.find_library(environment, name)
      |> result.map(fn(library) {
        e.from_annotated(library.source) |> remove(without)
      })
      |> result.replace_error("the library " <> name <> " is not loaded")
  }
}

// Remove top level definitions and the fields that export them.
fn remove(source, names) {
  case source {
    e.Block(assigns, e.Record(fields, None), open) -> {
      let assigns =
        list.filter(assigns, fn(assign) {
          case assign.0 {
            e.Bind(name) -> !list.contains(names, name)
            _ -> True
          }
        })
      let fields =
        list.filter(fields, fn(field) { !list.contains(names, field.0) })
      e.Block(assigns, e.Record(fields, None), open)
    }
    _ -> source
  }
}

/// The names, record shapes, tags and literals a program uses, written out for a task.
pub fn spec(target) -> String {
  let found = vocabulary.from_program(target)
  let code = fn(items) {
    list.map(items, fn(item) { "`" <> item <> "`" }) |> string.join(", ")
  }
  let quoted = fn(items) {
    list.map(items, fn(item) { "\"" <> item <> "\"" }) |> string.join(", ")
  }
  [
    "Names: " <> code(list.unique(list.append(found.names, found.labels))),
    "Patterns: "
      <> code(
      list.map(found.patterns, fn(fields) {
        let fields =
          list.map(fields, fn(field) {
            case field.0 == field.1 {
              True -> field.0
              False -> field.0 <> ": " <> field.1
            }
          })
        "{" <> string.join(fields, ", ") <> "}"
      })
      |> list.unique,
    ),
    "Records: "
      <> code(
      list.map(found.records, fn(labels) {
        "{" <> string.join(labels, ", ") <> "}"
      })
      |> list.unique,
    ),
    "Tags: " <> code(list.unique(found.tags)),
    "Builtins: "
      <> code(list.map(list.unique(found.builtins), fn(name) { "!" <> name })),
    "Strings: " <> quoted(list.unique(found.strings)),
    "Integers: "
      <> string.join(list.map(list.unique(found.integers), int.to_string), ", "),
  ]
  |> string.join("\n")
}

pub fn http() {
  Demo(
    slug: "http",
    title: "HTTP library",
    task: "Write the @http library for working with HTTP operations, requests and responses: helpers for percent and form encoding, origins, operations for each method, responses for each status, content and headers, and dispatch that performs `Fetch`.",
    target: LibrarySource("http", without: ["readme"]),
    environment: environment.browser(),
    config: options.Config(..options.default_config(), open_libraries: [
      "standard",
    ]),
    spec: True,
  )
}

pub fn http_compound() {
  Demo(
    ..http(),
    slug: "http-compound",
    title: "HTTP library with compound moves",
    config: options.Config(..http().config, compounds: compound.mined()),
  )
}

pub fn github() {
  Demo(
    slug: "github",
    title: "GitHub API client",
    task: "Write a client for three GitHub API endpoints, performing the `GitHub` effect for each request.
Define `get = (path)` that performs `GitHub` with the operation `{method, path, query, headers, body}`, where `method` is `GET`, `query` is `None`, `headers` is an empty list and `body` is `!string_to_binary` of \"\".
Then define `get_user = (username)` for \"/users/\" followed by the username,
`list_repos = (username)` for \"/users/\" username \"/repos\",
and `get_repo = (owner, repo)` for \"/repos/\" owner \"/\" repo, joining paths with `!string_append`.
Test the paths without the network: `path_of = (request)` handles `GitHub` with `(operation, resume)` returning `Error(operation.path)`.
Return `{get_user, list_repos, get_repo, tests}` where each test `{name, test}` checks with `!equal` that `path_of` gives `Error` of \"/users/octocat\", \"/users/octocat/repos\" and \"/repos/gleam-lang/gleam\" for the user \"octocat\" and the repository \"gleam-lang\" \"gleam\".
Name the tests \"get user\", \"list repos\" and \"get repo\". Run the tests before finishing.",
    target: Code(github_target),
    environment: environment.browser(),
    config: options.default_config(),
    spec: False,
  )
}

const github_target = "let get = (path) -> {
  perform GitHub({method: GET({}), path, query: None({}), headers: [], body: !string_to_binary(\"\")})
}
let get_user = (username) -> { get(!string_append(\"/users/\", username)) }
let list_repos = (username) -> {
  get(!string_append(!string_append(\"/users/\", username), \"/repos\"))
}
let get_repo = (owner, repo) -> {
  get(!string_append(!string_append(!string_append(\"/repos/\", owner), \"/\"), repo))
}
let path_of = (request) -> {
  handle GitHub((operation, resume) -> { Error(operation.path) }, (_) -> { request({}) })
}
{
  get_user,
  list_repos,
  get_repo,
  tests: [
    {name: \"get user\", test: (_) -> { !equal(path_of((_) -> { get_user(\"octocat\") }), Error(\"/users/octocat\")) }},
    {name: \"list repos\", test: (_) -> { !equal(path_of((_) -> { list_repos(\"octocat\") }), Error(\"/users/octocat/repos\")) }},
    {name: \"get repo\", test: (_) -> { !equal(path_of((_) -> { get_repo(\"gleam-lang\", \"gleam\") }), Error(\"/repos/gleam-lang/gleam\")) }}
  ]
}"

pub fn prepared_to_json(prepared: Prepared) {
  json.object([
    #("task", json.string(prepared.task)),
    #("actions", json.array(prepared.actions, action.to_json)),
  ])
}

pub fn prepared_decoder() {
  use task <- decode.field("task", decode.string)
  use actions <- decode.field("actions", decode.list(action.decoder()))
  decode.success(Prepared(task:, actions:))
}

pub fn github_library() {
  Demo(
    slug: "github-library",
    title: "GitHub client with @http and compound moves",
    task: "Write a client for three GitHub API endpoints using the @http library, search for it first.
Define `http` as the library, `origin` as `http.origin.https` of \"api.github.com\", and `get = (path)` that calls `http.dispatch` with `http.operation.get` of the path and the origin.
Then define `get_user = (username)` for \"/users/\" followed by the username,
`list_repos = (username)` for \"/users/\" username \"/repos\",
and `get_repo = (owner, repo)` for \"/repos/\" owner \"/\" repo, joining paths with `!string_append`.
`dispatch` performs the `Fetch` effect, test the paths without the network: `path_of = (request)` handles `Fetch` with `(sent, resume)` returning `Error(sent.path)`.
Return `{get_user, list_repos, get_repo, tests}` where each test `{name, test}` checks with `!equal` that `path_of` gives `Error` of \"/users/octocat\", \"/users/octocat/repos\" and \"/repos/gleam-lang/gleam\" for the user \"octocat\" and the repository \"gleam-lang\" \"gleam\".
Name the tests \"get user\", \"list repos\" and \"get repo\". Run the tests before finishing.",
    target: Code(github_library_target),
    environment: environment.browser(),
    config: options.Config(
      ..options.default_config(),
      compounds: compound.mined(),
      search_libraries: True,
    ),
    spec: False,
  )
}

const github_library_target = "let http = @http:3:baguqeeraqt2dscwwimthggq3gu5ji3j4vxk6diirk7plmtkiaihllacfln5q
let origin = http.origin.https(\"api.github.com\")
let get = (path) -> { http.dispatch(http.operation.get(path), origin) }
let get_user = (username) -> { get(!string_append(\"/users/\", username)) }
let list_repos = (username) -> {
  get(!string_append(!string_append(\"/users/\", username), \"/repos\"))
}
let get_repo = (owner, repo) -> {
  get(!string_append(!string_append(!string_append(\"/repos/\", owner), \"/\"), repo))
}
let path_of = (request) -> {
  handle Fetch((sent, resume) -> { Error(sent.path) }, (_) -> { request({}) })
}
{
  get_user,
  list_repos,
  get_repo,
  tests: [
    {name: \"get user\", test: (_) -> { !equal(path_of((_) -> { get_user(\"octocat\") }), Error(\"/users/octocat\")) }},
    {name: \"list repos\", test: (_) -> { !equal(path_of((_) -> { list_repos(\"octocat\") }), Error(\"/users/octocat/repos\")) }},
    {name: \"get repo\", test: (_) -> { !equal(path_of((_) -> { get_repo(\"gleam-lang\", \"gleam\") }), Error(\"/repos/gleam-lang/gleam\")) }}
  ]
}"
