//// Render the playground: task and checks, the program with its selection,
//// the options Jev was offered and the most recent selections.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/regexp
import gleam/string
import jev_playground/action
import jev_playground/agent
import jev_playground/app.{type Model, type Selection}
import jev_playground/environment
import jev_playground/eval
import jev_playground/library
import jev_playground/options
import lustre/attribute as a
import lustre/element.{type Element, text}
import lustre/element/html as h
import lustre/element/keyed
import lustre/event

pub fn render(model: Model) -> Element(app.Message) {
  h.div([a.class("app")], [
    header(model),
    // The status in the header changes on every tick, the panels only when Jev answers.
    h.main([a.class("grid")], [
      element.memo(
        [
          element.ref(model.agent),
          element.ref(model.task),
          element.ref(model.running),
        ],
        fn() { task_panel(model) },
      ),
      element.memo([element.ref(model.agent)], fn() { program_panel(model) }),
      element.memo(
        [
          element.ref(model.agent),
          element.ref(model.offered),
          element.ref(is_thinking(model)),
        ],
        fn() { options_panel(model) },
      ),
    ]),
    element.memo([element.ref(model.selections)], fn() { history(model) }),
  ])
}

fn header(model: Model) {
  let steps = list.length(model.agent.history)
  let cost = int.to_float(model.tokens) *. 0.042 /. 1_000_000.0
  let mode = case model.source {
    app.Live(model: jev_model, ..) -> jev_model
    app.Replay(demo:, ..) -> "replay · " <> demo.title
    app.Recorded(run: option.Some(run), ..) ->
      "eval · " <> run.eval.title <> " · " <> eval.variant_name(run.variant)
    app.Recorded(name:, ..) -> "eval · " <> name
  }
  h.header([a.class("bar")], [
    h.span([a.class("logo")], [text("JEV")]),
    h.span([a.class("title")], [text("playground")]),
    chip("mode", mode),
    chip("step", int.to_string(steps)),
    chip("tokens", thousands(model.tokens)),
    chip("cost", "$" <> float.to_string(float.to_precision(cost, 5))),
    status(model),
  ])
}

fn chip(label, value) {
  h.span([a.class("chip")], [
    h.span([a.class("chip-label")], [text(label)]),
    text(value),
  ])
}

fn status(model: Model) {
  let #(class, label) = case model.status {
    app.Loading -> #("idle", "loading libraries")
    app.Idle -> #("idle", "ready")
    app.Thinking(..) -> {
      let ms = option.unwrap(app.thinking_ms(model), 0)
      #("thinking", "thinking " <> int.to_string(ms) <> "ms")
    }
    app.Waiting -> #("waiting", "applying edit")
    app.Paused -> #("idle", "paused")
    app.Finished -> #("finished", "finished")
    app.Failed(reason) -> #("failed", "failed: " <> reason)
  }
  h.span([a.class("status " <> class)], [
    h.span([a.class("dot")], []),
    text(label),
  ])
}

fn task_panel(model: Model) {
  let readonly = case model.source {
    app.Replay(..) | app.Recorded(..) -> True
    app.Live(..) -> False
  }
  let agent = model.agent
  let errors = agent.type_error_count(agent)
  let holes = count_holes(agent.program_text(agent))
  h.section([a.class("panel task")], [
    h.h2([], [text("Task")]),
    h.textarea(
      [
        a.class("task-input"),
        a.readonly(readonly),
        a.placeholder("Describe the program for Jev to write..."),
        event.on_input(app.UserEditedTask),
      ],
      model.task,
    ),
    h.div([a.class("controls")], [
      button("Run", app.UserClickedRun, model.running),
      button("Step", app.UserClickedStep, model.running),
      button("Pause", app.UserClickedPause, !model.running),
      button("Reset", app.UserClickedReset, False),
    ]),
    h.h2([], [text("Checks")]),
    h.dl([a.class("checks")], [
      check("holes", int.to_string(holes), holes == 0),
      check("type errors", int.to_string(errors), errors == 0),
      check(
        "tests",
        tests_label(agent.test_results),
        tests_pass(agent.test_results),
      ),
    ]),
    case agent.test_results {
      Some(results) -> h.pre([a.class("tests")], [text(results)])
      None -> element.none()
    },
    h.h2([], [text("Effects")]),
    h.div(
      [a.class("effects")],
      list.map(agent.environment.effects, fn(effect) {
        h.span([a.class("effect")], [text(effect.0)])
      }),
    ),
    case list.filter(agent.environment.libraries, library.is_released) {
      [] -> element.none()
      libraries ->
        h.div([], [
          h.h2([], [text("Libraries")]),
          h.div(
            [a.class("effects")],
            list.map(libraries, fn(library: environment.Library) {
              let open =
                list.contains(agent.config.open_libraries, library.name)
              h.span([a.classes([#("effect", True), #("open", open)])], [
                text("@" <> library.name),
              ])
            }),
          ),
        ])
    },
  ])
}

fn button(label, message, disabled) {
  h.button([a.class("button"), a.disabled(disabled), event.on_click(message)], [
    text(label),
  ])
}

fn check(label, value, ok) {
  h.div([a.classes([#("check", True), #("ok", ok)])], [
    h.dt([], [text(label)]),
    h.dd([], [text(value)]),
  ])
}

fn tests_label(results) {
  case results {
    Some(results) ->
      case string.split(results, "\n") {
        [first, ..] -> first
        [] -> results
      }
    None -> "not run"
  }
}

fn tests_pass(results) {
  case results {
    Some(results) -> {
      let assert Ok(re) = regexp.from_string("^(\\d+) of (\\d+) tests passed")
      case regexp.scan(re, results) {
        [regexp.Match(submatches: [Some(a), Some(b)], ..)] -> a == b && a != "0"
        _ -> False
      }
    }
    None -> False
  }
}

fn count_holes(code) {
  string.to_graphemes(code) |> list.count(fn(g) { g == "?" })
}

fn program_panel(model: Model) {
  let code = agent.program_text(model.agent)
  h.section([a.class("panel program")], [
    h.h2([], [
      text("Program"),
      h.span([a.class("hint")], [text(options.focus_kind(model.agent.buffer))]),
    ]),
    h.pre([a.class("code")], highlight_program(code)),
  ])
}

/// Split out the selection marked with « and » and highlight the rest.
pub fn highlight_program(code) -> List(Element(a)) {
  case string.split_once(code, "«") {
    Ok(#(before, rest)) ->
      case split_selection(rest) {
        Ok(#(selected, after)) ->
          list.flatten([
            highlight(before),
            [h.span([a.class("selection")], highlight(selected))],
            highlight(after),
          ])
        Error(Nil) -> highlight(code)
      }
    Error(Nil) -> highlight(code)
  }
}

// The last » closes the selection, strings may contain the markers.
fn split_selection(rest) {
  case string.split(rest, "»") |> list.reverse {
    [after, ..selected] if selected != [] ->
      Ok(#(string.join(list.reverse(selected), "»"), after))
    _ -> Error(Nil)
  }
}

const keywords = ["let", "match", "perform", "handle", "import"]

pub fn highlight(code) -> List(Element(a)) {
  let assert Ok(re) =
    regexp.from_string(
      "\"(?:[^\"\\\\]|\\\\.)*\"|![a-z_][a-z0-9_]*|[a-z_][a-z0-9_]*|[A-Z][A-Za-z0-9]*|-?[0-9]+|\\?|\\s+|.",
    )
  regexp.scan(re, code)
  |> list.map(fn(match) {
    let token = match.content
    let class = case token {
      "\"" <> _ -> "string"
      "!" <> _ -> "builtin"
      "?" -> "hole"
      _ ->
        case list.contains(keywords, token) {
          True -> "keyword"
          False -> classify(token)
        }
    }
    case class {
      "" -> text(token)
      _ -> h.span([a.class(class)], [text(token)])
    }
  })
}

fn classify(token) {
  let assert Ok(tag) = regexp.from_string("^[A-Z]")
  let assert Ok(number) = regexp.from_string("^-?[0-9]")
  case regexp.check(tag, token), regexp.check(number, token) {
    True, _ -> "tag"
    _, True -> "number"
    _, _ -> ""
  }
}

const ranked_shown = 10

fn options_panel(model: Model) {
  let offered = model.offered
  let count = list.length(offered)
  let #(title, body) = case model.status, model.agent.history {
    app.Thinking(..), _ -> #("evaluating", thinking(offered))
    _, [step, ..] -> #(
      "chosen in " <> int.to_string(step.thinking_ms) <> "ms",
      ranked(step, offered),
    )
    _, [] -> #("", [
      h.p([a.class("hint")], [text("Jev has not been asked yet.")]),
    ])
  }
  h.section([a.class("panel options")], [
    h.h2([], [
      text("Options"),
      h.span([a.class("hint")], [
        text(int.to_string(count) <> " presented · " <> title),
      ]),
    ]),
    h.div([a.class("option-list")], body),
  ])
}

fn thinking(offered: List(options.Option)) {
  [
    h.div(
      [a.class("cloud scanning")],
      list.map(list.take(offered, 120), fn(option) {
        h.span([a.class("tag-option")], [text(options.key(option))])
      }),
    ),
  ]
}

fn ranked(step: agent.Step, offered) {
  let top = list.take(step.ranked, ranked_shown)
  let names = list.map(top, fn(entry) { entry.0 })
  let rest =
    list.filter(offered, fn(option) {
      !list.contains(names, options.key(option))
    })
  list.append(
    list.index_map(top, fn(entry, i) {
      let #(name, probability) = entry
      let percent = float.round(probability *. 100.0)
      h.div([a.classes([#("ranked", True), #("chosen", i == 0)])], [
        h.div(
          [a.class("bar"), a.style("width", int.to_string(percent) <> "%")],
          [],
        ),
        h.span([a.class("probability")], [text(int.to_string(percent) <> "%")]),
        h.span([a.class("name")], [text(name)]),
      ])
    }),
    [
      h.div(
        [a.class("cloud")],
        list.map(list.take(rest, 80), fn(option) {
          h.span([a.class("tag-option")], [text(options.key(option))])
        }),
      ),
    ],
  )
}

fn history(model: Model) {
  let items =
    list.index_map(model.selections, fn(selection, i) {
      #(int.to_string(selection.id), selection_item(selection, i))
    })
    |> list.reverse
  h.footer([a.class("history")], [
    h.h2([], [text("Recent selections")]),
    keyed.div([a.class("selections")], items),
  ])
}

fn selection_item(selection: Selection, age) {
  let step = selection.step
  let classes = [
    #("selection-item", True),
    #("new", age == 0),
    #("leaving", age >= app.shown),
  ]
  h.div([a.classes(classes)], [
    h.span([a.class("number")], [text("#" <> int.to_string(selection.id))]),
    h.span([a.class("name")], [text(selection.name)]),
    h.span([a.class("meta")], [
      text(
        int.to_string(float.round(step.confidence *. 100.0))
        <> "% conf · "
        <> int.to_string(step.thinking_ms)
        <> "ms",
      ),
    ]),
    case step.action {
      action.RunTests | action.Finish ->
        h.span([a.class("flag")], [text("check")])
      _ -> element.none()
    },
  ])
}

fn thousands(n) {
  let digits = int.to_string(n) |> string.to_graphemes |> list.reverse
  digits
  |> list.sized_chunk(3)
  |> list.map(fn(chunk) { chunk |> list.reverse |> string.concat })
  |> list.reverse
  |> string.join(",")
}

fn is_thinking(model: Model) {
  case model.status {
    app.Thinking(..) -> True
    _ -> False
  }
}
