//// Pages for Glasshouse, reproducible runs for EYG programs and agents.

import gleam/list
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/route.{Route}
import simplifile
import website/components
import website/routes/glasshouse/debugger
import website/routes/glasshouse/debugger/state
import website/routes/glasshouse/documentation
import website/routes/glasshouse/home
import website/routes/glasshouse/layout

const demo_directory = "src/website/routes/glasshouse/demo/"

pub fn route() {
  let assert Ok(recording) =
    simplifile.read_bits("../tracing/recordings/trajectories.webm")
  Route(index: route.Page(home.page()), items: [
    #("trajectories.webm", Route(route.Static(recording), [])),
    #(
      "documentation",
      Route(index: route.Page(documentation.page()), items: []),
    ),
    #("debugger", Route(index: route.Page(debugger.page()), items: [])),
    #(
      "demo",
      Route(
        index: route.Page(demo_page()),
        items: list.map(
          ["cohort", ..list.map(state.demos, fn(d) { d.slug })],
          fn(slug) {
            let assert Ok(bytes) =
              simplifile.read_bits(demo_directory <> slug <> ".json")
            #(slug <> ".json", Route(route.Static(bytes), []))
          },
        ),
      ),
    ),
  ])
}

// The demo traces, to download or open in the debugger.
fn demo_page() {
  use content <- asset.do(
    layout.page(
      "/glasshouse/demo",
      "Glasshouse demo traces",
      "Archives of a recorded agent session and the variants evaluated from it.",
      [],
      [
        components.header(),
        layout.nav("/glasshouse/demo"),
        h.main([a.class("gh-section")], [
          h.h1([a.class("gh-section-title")], [element.text("Demo traces")]),
          h.p([a.class("text-lg")], [
            element.text(
              "A newsletter agent recorded against the development mock, and the variants evaluated from it. Each is a complete archive, open it in the debugger or with the eyg CLI.",
            ),
          ]),
          h.ul(
            [a.class("mt-6 grid gap-3")],
            list.map(state.demos, fn(demo) {
              h.li([a.class("flex flex-wrap items-center gap-3")], [
                h.span([a.class("font-bold w-48")], [element.text(demo.name)]),
                h.a(
                  [
                    a.class("gh-button"),
                    a.href("/glasshouse/debugger?trace=" <> demo.slug),
                  ],
                  [element.text("Open in the debugger")],
                ),
                h.a(
                  [
                    a.class("gh-button"),
                    a.href(state.demo_path(demo)),
                    a.attribute("download", demo.slug <> ".json"),
                  ],
                  [element.text("Download")],
                ),
              ])
            }),
          ),
        ]),
        components.footer(),
      ],
    ),
  )
  asset.done(element.to_document_string(content))
}
