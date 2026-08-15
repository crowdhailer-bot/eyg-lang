//// Why an application should hand an agent a language rather than a list of
//// commands, argued from a puzzle nobody can click on.

import gleam/list
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/html
import website/components
import website/routes/common
import website/routes/home

pub fn page() {
  use content <- asset.do(layout(body()))
  asset.done(element.to_document_string(content))
}

fn layout(body) {
  use layout <- asset.do(asset.load(home.layout_path))
  use neo <- asset.do(asset.load("src/website/routes/neo.css"))
  html.doc(
    list.flatten([
      [
        html.stylesheet(html.tailwind_2_2_11),
        html.stylesheet(asset.src(layout)),
        html.stylesheet(asset.src(neo)),
      ],
      common.page_meta(
        "/embedded",
        "Give an agent a language, not a list of commands",
        "An application that embeds EYG decides what exists. Everything else "
          <> "— sequencing, branching, folding over a list — comes with the "
          <> "language.",
      ),
      common.diagnostics(),
    ]),
    body,
  )
  |> asset.done()
}

const measure = "mx-auto w-full max-w-3xl px-4"

fn p(content) {
  h.p([a.class(measure <> " my-4 text-lg")], content)
}

fn h2(text) {
  h.h2([a.class(measure <> " text-2xl font-bold mt-12 mb-2")], [
    element.text(text),
  ])
}

fn strong(text) {
  h.strong([a.class("font-bold")], [element.text(text)])
}

fn code(text) {
  h.code([a.class("bg-gray-100 rounded px-1 font-mono text-base")], [
    element.text(text),
  ])
}

fn link(href, text) {
  h.a([a.class("text-green-700 underline"), a.href(href)], [element.text(text)])
}

fn body() {
  [
    components.header(),
    hero(),
    the_demonstration(),
    the_argument(),
    the_boundary(),
    closing(),
  ]
}

fn hero() {
  h.div([a.class("bg-gradient-to-bl from-green-100 to-green-200 pt-14 pb-10")], [
    h.h1([a.class(measure <> " text-4xl font-bold my-4")], [
      element.text("Nothing on this board is clickable."),
    ]),
    p([
      element.text(
        "It is an ordinary hashiwokakero puzzle, drawn by an ordinary Lustre "
        <> "application. Every pointer event it produces is thrown away. The "
        <> "only way to build a bridge is to run a program — and there are two "
        <> "ways to do that.",
      ),
    ]),
    p([
      element.text(
        "On the left, a structural shell, where a person writes it. ",
      ),
      element.text("Behind the other icon, an agent, where a model writes it "),
      element.text("from a sentence of English. "),
      strong("The same programs, the same six effects, the same board."),
    ]),
  ])
}

fn video(source, poster, caption) {
  h.figure([a.class(measure <> " my-8")], [
    h.video(
      [
        a.class("w-full border border-black rounded shadow-lg"),
        a.attribute("controls", "true"),
        a.attribute("loop", "true"),
        a.attribute("muted", "true"),
        a.attribute("playsinline", "true"),
        a.attribute("preload", "none"),
        a.attribute("poster", poster),
        a.src(source),
      ],
      [],
    ),
    h.figcaption([a.class("text-center text-gray-600 mt-2")], [
      element.text(caption),
    ]),
  ])
}

fn the_demonstration() {
  h.div([], [
    h2("A whole game, written by hand"),
    p([
      element.text(
        "There is no text box. Every key builds a piece of tree: a variable, a "
        <> "record, a call. Because the shell is holding a tree rather than a "
        <> "line of characters, it type checks the program as it is written, "
        <> "against the six effects and against the library the game brings.",
      ),
    ]),
    video(
      "/hashi-shell.webm",
      "/hashi-shell.png",
      "Ten bridges, built in the shell, from nothing.",
    ),
    h2("A whole game, from one sentence"),
    p([
      element.text("The model is told where it is and what it can do, and it "),
      element.text("writes "),
      code("connect({x: 0, y: 5}, {x: 3, y: 5})"),
      element.text(
        " — the same program a person would write, run by the same runtime "
        <> "against the same board. Every program it wants to run is there to "
        <> "read before it runs.",
      ),
    ]),
    video(
      "/hashi-agent.webm",
      "/hashi-agent.png",
      "\"Solve this board.\" The rest is the model writing EYG.",
    ),
  ])
}

fn the_argument() {
  h.div([], [
    h2("Why not a list of tools?"),
    p([
      element.text(
        "The usual way to open an application to an agent is to publish its "
        <> "operations as tools, one call at a time, with the model in the loop "
        <> "for every one of them. That is fine for a question with one answer. "
        <> "It comes apart the moment the work has any shape to it.",
      ),
    ]),
    p([
      strong("Ten moves is ten round trips. "),
      element.text(
        "Every call goes out to the model and comes back. In the recording above "
        <> "the agent solves the board in four turns, because a turn can be a "
        <> "program with ten moves in it rather than one move.",
      ),
    ]),
    p([
      strong("There is nowhere to put a decision. "),
      element.text(
        "\"Join every two that has only one neighbour\" is a filter and a loop. "
        <> "As tools it is: list islands, think, list neighbours, think, call, "
        <> "call, call. As a program it is four lines, and the thinking happens "
        <> "once.",
      ),
    ]),
    p([
      strong("The application ends up writing the language anyway. "),
      element.text(
        "Sooner or later somebody adds a tool that takes a list, then one that "
        <> "takes a condition, then one that repeats. Those are sequencing, "
        <> "branching and iteration, arrived at one awkward argument at a time.",
      ),
    ]),
    p([
      strong("You cannot read a plan made of calls. "),
      element.text(
        "A program is one thing you can look at and approve before it runs. A "
        <> "sequence of tool calls is only visible one step at a time, by which "
        <> "point the earlier ones have already happened.",
      ),
    ]),
    p([
      element.text(
        "None of this is an argument against tools as a protocol. It is an "
        <> "argument about what to put in the tool: one call that runs a "
        <> "program beats twenty that each do one thing.",
      ),
    ]),
  ])
}

fn the_boundary() {
  h.div([], [
    h2("The part you actually control"),
    p([
      element.text(
        "The reason to hand over a language is that you decide what it can "
        <> "reach. The whole of this game's boundary is six effects:",
      ),
    ]),
    h.div([a.class(measure <> " my-6")], [
      h.pre(
        [a.class("bg-gray-900 text-green-100 rounded p-4 overflow-x-auto")],
        [
          h.code([a.class("font-mono text-sm")], [
            element.text(
              "ListIslands({})           -> List({position, target})\n"
              <> "ListBridges({})           -> List({start, end, count})\n"
              <> "AddBridge({start, end})   -> Ok({}) | Error(BadStart | BadEnd | Full)\n"
              <> "Undo({})                  -> Boolean\n"
              <> "Redo({})                  -> Boolean\n"
              <> "ShareOutcome(text)        -> Ok({}) | Error(String)",
            ),
          ]),
        ],
      ),
    ]),
    p([
      element.text("No "),
      code("Fetch"),
      element.text(", no "),
      code("Print"),
      element.text(", no clipboard, no file system. Not left out by accident: "),
      element.text(
        "a program running in this page has no business with any of them. The "
        <> "one effect that does reach the network says what it wants — this "
        <> "result, shared — and the platform decides where that goes.",
      ),
    ]),
    p([
      element.text(
        "A program that performs anything else does not get an error at the far "
        <> "end of a request. It does not run. There is no effect of that name, "
        <> "and the type checker says so before anything happens.",
      ),
    ]),
    p([
      strong("Managed effects are the feature. "),
      element.text(
        "Sandboxing a general purpose language means taking things away and "
        <> "hoping you found them all. An EYG program can only perform effects "
        <> "the runtime handles, so the list above is not a policy layered over "
        <> "a runtime — it is the runtime.",
      ),
    ]),
  ])
}

fn closing() {
  h.div([a.class("py-12")], [
    h2("Build one"),
    p([
      link("/guides/building-an-embedded-runtime", "The guide"),
      element.text(
        " walks through the whole of it: describing the effects, carrying them "
        <> "out, writing the workspace the model is given, and running a "
        <> "program. It is one afternoon of work, and most of it is deciding "
        <> "what your application should let a program do.",
      ),
    ]),
    p([
      link(
        "https://github.com/CrowdHailer/eyg-lang/tree/main/packages/hashi",
        "The source of this demonstration",
      ),
      element.text(" is in the repository, tests and all. The game itself is "),
      link(
        "https://github.com/giacomocavalieri/hashi",
        "giacomocavalieri/hashi",
      ),
      element.text(
        ", unchanged apart from one addition: a way to build a bridge that says "
        <> "why it could not, because a rule that quietly does nothing is right "
        <> "for a finger on a screen and no use to a program.",
      ),
    ]),
  ])
}
