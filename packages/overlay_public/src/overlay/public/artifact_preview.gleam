//// Prepare an artifact bundle for display in a sandboxed iframe.
////
//// Untrusted markup is never parsed into the application document.
//// DOMParser creates an inert document, its scripts do not run and nothing loads.

import gleam/javascript/array
import gleam/list
import gleam/result.{try}
import gleam/string
import overlay/public/puppet
import overlay/web/artifact.{type Bundle}
import overlay/web/artifact/inline
import plinth/browser/document
import plinth/browser/dom_parser
import plinth/browser/element.{type Element}

/// Every artifact runs under this policy, set by the wrapper before any artifact content.
/// It can only be restricted further by the artifact.
pub const policy = "default-src 'none'; script-src 'unsafe-inline' data:; style-src 'unsafe-inline' data:; img-src data:; font-src data:; media-src data:; connect-src 'none'; frame-src 'none'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"

/// The source of a wrapper frame showing the bundle.
/// A bundle that cannot be prepared shows the reason instead.
pub fn srcdoc(bundle: Bundle) -> String {
  case document(bundle) {
    Ok(html) -> wrapper(html)
    // The puppet is included so an agent can read the reason.
    Error(reason) ->
      wrapper(
        "<!doctype html><html><head><script>"
        <> puppet.script
        <> "</script></head><body><h2>Unable to prepare artifact</h2><pre>"
        <> escape(reason)
        <> "</pre></body></html>",
      )
  }
}

/// A trusted document that fixes the content security policy,
/// then shows `html` in a nested frame with its own opaque origin.
pub fn wrapper(html: String) -> String {
  "<!doctype html><html><head><meta charset=\"utf-8\"><meta http-equiv=\"Content-Security-Policy\" content=\""
  <> policy
  <> "\"><meta name=\"referrer\" content=\"no-referrer\"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden}iframe{border:0;width:100%;height:100%;display:block}</style></head><body><iframe title=\"Artifact content\" sandbox=\"allow-scripts\" referrerpolicy=\"no-referrer\" srcdoc=\""
  <> escape(html)
  <> "\"></iframe></body></html>"
}

/// A single HTML document with every file it uses from the bundle inline,
/// and the puppet script that performs requests from the application.
pub fn document(bundle: Bundle) -> Result(String, String) {
  use entry <- try(
    artifact.file(bundle, "index.html")
    |> result.replace_error("Missing index.html"),
  )
  use source <- try(inline.text(entry))
  use parsed <- try(dom_parser.parse_from_string(source, "text/html"))
  let root = document.document_element(parsed)
  use Nil <- try(
    element.query_selector_all(root, "*")
    |> array.to_list
    |> list.try_each(inline_element(bundle, _)),
  )
  // The parser always creates a head, the puppet runs before any artifact script.
  let assert Ok(head) = element.query_selector(root, "head")
  let script = document.create_element("script")
  element.set_text_content(script, puppet.script)
  let assert Ok(_) =
    element.insert_adjacent_element(head, element.AfterBegin, script)
  Ok("<!doctype html>" <> element.outer_html(root))
}

const entry = "index.html"

fn inline_element(bundle: Bundle, el: Element) -> Result(Nil, String) {
  use Nil <- try(case element.local_name(el) {
    "base" -> Ok(element.remove(el))
    "link" -> link(bundle, el)
    "style" -> {
      use css <- try(inline.stylesheet(bundle, element.text_content(el), entry))
      Ok(element.set_text_content(el, css))
    }
    _ -> Ok(Nil)
  })
  use Nil <- try(case element.get_attribute(el, "style") {
    Ok(declarations) -> {
      use css <- try(inline.stylesheet(bundle, declarations, entry))
      Ok(element.set_attribute(el, "style", css))
    }
    Error(Nil) -> Ok(Nil)
  })
  use Nil <- try(case element.has_attribute(el, "srcset") {
    True -> Error("Use a bundled src instead of srcset")
    False -> Ok(Nil)
  })
  let sources = case element.local_name(el) {
    "img" | "script" | "audio" | "video" | "source" | "track" | "input" -> [
      "src",
    ]
    "image" | "use" -> ["href", "xlink:href"]
    _ -> []
  }
  use Nil <- try(
    list.try_each(["poster", ..sources], inline_attribute(bundle, el, _)),
  )
  // Integrity and CORS settings do not apply to inline data.
  case sources, element.has_attribute(el, "src") {
    ["src"], True -> {
      element.remove_attribute(el, "integrity")
      element.remove_attribute(el, "crossorigin")
      Ok(Nil)
    }
    _, _ -> Ok(Nil)
  }
}

fn inline_attribute(bundle, el, name) {
  case element.get_attribute(el, name) {
    Ok(reference) -> {
      use location <- try(inline.asset(bundle, reference, entry))
      Ok(element.set_attribute(el, name, location))
    }
    Error(Nil) -> Ok(Nil)
  }
}

fn link(bundle, el) {
  let rel = element.get_attribute(el, "rel") |> result.unwrap("")
  case string.lowercase(string.trim(rel)) {
    "stylesheet" -> {
      let href = element.get_attribute(el, "href") |> result.unwrap("")
      use #(file, _fragment) <- try(inline.resolve(bundle, href, entry))
      use source <- try(inline.text(file))
      use css <- try(inline.stylesheet(bundle, source, file.path))
      Ok(element.set_attribute(
        el,
        "href",
        inline.text_data_url("text/css", css),
      ))
    }
    _ -> Ok(element.remove(el))
  }
}

fn escape(text) {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("\"", "&quot;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}
