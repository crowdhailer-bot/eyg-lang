import gleam/result
import plinthx/browser/node as n

const key = "phx:theme"

pub fn start() {
  let screen = n.media_query("(prefers-color-scheme: dark)")
  let stored = n.read_storage("localStorage", key) |> result.unwrap("")
  set(screen, stored)
  n.listen_global("storage", fn(event) {
    case n.event_text(event, "key") == key {
      True -> set(screen, n.event_text(event, "newValue"))
      False -> Nil
    }
  })
  n.listen_global("phx:set-theme", fn(event) {
    set(
      screen,
      n.attribute(n.target(event), "data-phx-theme") |> result.unwrap("system"),
    )
  })
  n.listen_media(screen, fn(_) {
    case n.attribute(n.root(), "data-theme-source") {
      Ok("system") -> set(screen, "system")
      _ -> Nil
    }
  })
}

fn set(screen, theme) {
  let #(theme, source) = case theme {
    "dark" | "light" -> {
      let _ = n.write_storage("localStorage", key, theme)
      #(theme, "user")
    }
    _ -> {
      let _ = n.remove_storage("localStorage", key)
      #(
        case n.media_matches(screen) {
          True -> "dark"
          False -> "light"
        },
        "system",
      )
    }
  }
  n.set_attribute(n.root(), "data-theme", theme)
  n.set_attribute(n.root(), "data-theme-source", source)
}
