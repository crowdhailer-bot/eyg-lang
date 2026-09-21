//// Scripted runs of the playground, replayed with mocked Jev answers for recordings.
//// Each demo has a task and the program Jev should end up with,
//// the actions are found by synthesis so they stay in step with the editor.

import eyg/parser
import gleam/list
import gleam/result
import jev_playground/action.{type Action}
import jev_playground/environment.{type Environment}
import jev_playground/options
import jev_playground/synthesis
import morph/editable as e

pub type Demo {
  Demo(
    slug: String,
    title: String,
    task: String,
    target: Target,
    environment: Environment,
    config: options.Config,
  )
}

/// The program Jev should end up with.
pub type Target {
  Code(source: String)
  /// The source of a library, as loaded into the environment.
  LibrarySource(name: String)
}

pub fn all() -> List(Demo) {
  [github()]
}

pub fn find(slug) {
  list.find(all(), fn(demo) { demo.slug == slug })
}

/// The actions Jev is scripted to choose, ending by running the tests and finishing.
/// The environment is the demo environment with any libraries loaded.
pub fn script(
  demo: Demo,
  environment: Environment,
) -> Result(List(Action), String) {
  use target <- result.try(target(demo, environment))
  use actions <- result.map(synthesis.script(target, environment))
  list.append(actions, [action.RunTests, action.Finish])
}

pub fn target(demo: Demo, environment) -> Result(e.Expression, String) {
  case demo.target {
    Code(source) ->
      parser.all_from_string(source)
      |> result.map(e.from_annotated)
      |> result.replace_error(
        "the target of " <> demo.slug <> " does not parse",
      )
    LibrarySource(name) ->
      environment.find_library(environment, name)
      |> result.map(fn(library) { e.from_annotated(library.source) })
      |> result.replace_error("the library " <> name <> " is not loaded")
  }
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
