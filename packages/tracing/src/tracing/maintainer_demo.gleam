//// Execute the maintainer guide with pinned source and an isolated note.

import filepath
import gleam/dict
import gleam/io
import gleam/javascript/promise
import gleam/result
import gleam/string
import plinthx/bun/runtime
import plinthx/node/process
import plinthx/node/timers
import simplifile
import tracing/terminal_demo as terminal

const recording = "packages/tracing/recordings/overlay-maintainer.mp4"

const workspace = "/tmp/eyg-roadmap-context-workspace"

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let root = filepath.join(cwd, "../..")
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let env = process.env(host)
  let binary =
    dict.from_list(env)
    |> dict.get("EYG_BIN")
    |> result.unwrap(filepath.join(root, "packages/gleam_cli/dist/eyg"))
  let assert Ok(_) = simplifile.create_directory_all(workspace)
  let import_ =
    "let context = import \""
    <> filepath.join(root, "eyg_packages/overlay_maintainer/index.eyg")
    <> "\" let workspace = context.workspace.at(match perform CWD({}) { Ok(path) -> { path } Error(_) -> { !never(perform Abort(\"no working directory\")) } }) "
  let checked =
    terminal.in_desktop(bun, root, env, fn() {
      use _ <- promise.await(timers.sleep(700))
      terminal.in_terminal(bun, root, env, fn() {
        use _ <- promise.await(terminal.submit(root, "cd " <> quote(workspace)))
        let video = terminal.video(bun, root, env, recording)
        let checked =
          {
            use _ <- promise.await(run(
              root,
              binary,
              import_
                <> "let source = context.source.at({owner: \"crowdhailer-bot\", name: \"eyg-lang\", branch: \"b9fd9ec5758a39e7943e1223ad572a1b2dd89750\", url: \"https://github.com/crowdhailer-bot/eyg-lang\"}) match source.read(\"eyg_packages/overlay_librarian/index.eyg\") { Ok(text) -> { perform StandardOut(!string_append(!string_split(text, \"\\n\").head, \"\\n\")) } Error(reason) -> { !never(perform Abort(reason)) } }",
              "// An Overlay context for finding libraries",
            ))
            use _ <- promise.await(timers.sleep(1500))
            use _ <- promise.await(run(
              root,
              binary,
              import_
                <> "match workspace.write_note({name: \"Parsing JSON\", description: \"Use the JSON package\", date: \"2026-10-14\", body: \"Decode fields.\"}) { Ok(path) -> { perform StandardOut(!string_append(path, \"\\n\")) } Error(reason) -> { !never(perform Abort(reason)) } }",
              "notes/parsing-json.md",
            ))
            use _ <- promise.await(timers.sleep(1500))
            use _ <- promise.await(run(
              root,
              binary,
              import_
                <> "!list_fold(workspace.notes({}), {}, (note, _) -> { perform StandardOut(!string_append(note.path, !string_append(\": \", !string_append(note.date, \"\\n\")))) })",
              "notes/parsing-json.md: 2026-10-14",
            ))
            use _ <- promise.await(timers.sleep(2000))
            use pane <- promise.map(terminal.capture(root))
            assert !string.contains(pane, "error:") as pane
            let assert Ok(_) =
              simplifile.write("recordings/overlay-maintainer.txt", pane)
            let assert Ok(note) =
              simplifile.read(workspace <> "/notes/parsing-json.md")
            assert string.contains(note, "name: Parsing JSON")
            assert string.contains(note, "date: 2026-10-14")
            Nil
          }
          |> promise.map(Ok)
          |> promise.rescue(Error)
        use checked <- promise.await(checked)
        use _ <- promise.map(terminal.finish_video(video, root, recording))
        let assert Ok(_) = checked
        Nil
      })
    })
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.map(checked)
  let _ = simplifile.delete_file(workspace <> "/notes/parsing-json.md")
  let assert Ok(_) = checked
  io.println("PASS pinned source, note write/index and checked recording")
}

fn run(root, binary, code, expected) {
  use _ <- promise.await(terminal.submit(
    root,
    quote(binary) <> " run -c " <> quote(code),
  ))
  use _ <- promise.await(terminal.wait_for(root, expected, 200))
  terminal.wait_shell(root, 100)
}

fn quote(text) {
  "'" <> string.replace(text, "'", "'\\''") <> "'"
}
