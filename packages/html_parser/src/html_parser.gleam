import gleam/list
import gleam/string

/// Element is a part of an HTML document
pub type Element {
  EmptyElement

  /// StartElement is an opening tag like <div> and can have Attributes and child Elements
  StartElement(
    name: String,
    attributes: List(Attribute),
    children: List(Element),
  )

  /// EndElement just has a name and signals the end of a block
  EndElement(name: String)

  /// Content is non-HTML parts of the document in-between StartElement and
  /// EndElement (the "hello" in `<div>hello</div>`)
  Content(String)
}

/// Attribute is an HTML attribute key-value pair
pub type Attribute {
  Attribute(key: String, value: String)
}

/// get the first Element and remaining String
pub fn get_first_element(in: String) -> #(Element, String) {
  in
  |> trim_space_to_elem_begin
  |> do_get_first_element("", None)
}

fn trim_space_to_elem_begin(in: String) -> String {
  case in {
    " " <> remain | "\n" <> remain | "\t" <> remain ->
      trim_space_to_elem_begin(remain)
    "<" <> remain -> "<" <> remain
    _ -> in
  }
}

/// CurrentElementType is used to track the current parsing state in do_get_first_element
type CurrentElementType {
  Start
  End
  None
}

fn do_get_first_element(
  in: String,
  out: String,
  currently_parsing: CurrentElementType,
) -> #(Element, String) {
  case in {
    "</" <> remain ->
      case out {
        "" -> do_get_first_element(remain, out, End)
        _ -> #(Content(out), "</" <> remain)
      }
    "<" <> remain ->
      case out {
        "" -> do_get_first_element(remain, out, Start)
        _ -> #(Content(out), "<" <> remain)
      }
    ">" <> remain ->
      case currently_parsing {
        Start -> #(StartElement(out, [], []), remain)
        End -> #(EndElement(out), remain)
        None -> #(Content(out), remain)
      }
    " " <> remain | "\n" <> remain | "\t" <> remain
      if currently_parsing == Start
    -> {
      let #(attrs, remain_after_attr) = get_attrs(remain)
      #(StartElement(out, attrs, []), remain_after_attr)
    }
    "" -> #(EmptyElement, "")
    _ -> {
      let assert Ok(#(head, remain)) = string.pop_grapheme(in)
      do_get_first_element(remain, out <> head, currently_parsing)
    }
  }
}

/// get the attributes for a StartElement and remaining String
pub fn get_attrs(in: String) -> #(List(Attribute), String) {
  do_get_attrs(in, [])
}

// Attribute values may be double quoted, single quoted or unquoted,
// an attribute without a value has an empty value.
fn do_get_attrs(
  in: String,
  attrs: List(Attribute),
) -> #(List(Attribute), String) {
  case skip_space(in) {
    "" -> #(list.reverse(attrs), "")
    ">" <> remain -> #(list.reverse(attrs), remain)
    rest -> {
      let #(key, remain) = get_key(rest, "")
      case skip_space(remain) {
        "=" <> remain -> {
          let #(value, remain) = get_value(skip_space(remain))
          do_get_attrs(remain, [Attribute(key, value), ..attrs])
        }
        _ -> do_get_attrs(remain, [Attribute(key, ""), ..attrs])
      }
    }
  }
}

fn get_key(in: String, key: String) -> #(String, String) {
  case in {
    "" | " " <> _ | "\n" <> _ | "\t" <> _ | "\r" <> _ | "=" <> _ | ">" <> _ -> #(
      key,
      in,
    )
    _ -> {
      let assert Ok(#(head, remain)) = string.pop_grapheme(in)
      get_key(remain, key <> head)
    }
  }
}

fn get_value(in: String) -> #(String, String) {
  case in {
    "\"" <> remain -> until_quote(remain, "\"")
    "'" <> remain -> until_quote(remain, "'")
    _ -> unquoted_value(in, "")
  }
}

fn until_quote(in: String, quote: String) -> #(String, String) {
  case string.split_once(in, quote) {
    Ok(#(value, remain)) -> #(value, remain)
    Error(Nil) -> #(in, "")
  }
}

fn unquoted_value(in: String, value: String) -> #(String, String) {
  case in {
    "" | " " <> _ | "\n" <> _ | "\t" <> _ | "\r" <> _ | ">" <> _ -> #(value, in)
    _ -> {
      let assert Ok(#(head, remain)) = string.pop_grapheme(in)
      unquoted_value(remain, value <> head)
    }
  }
}

fn skip_space(in: String) -> String {
  case in {
    " " <> remain | "\n" <> remain | "\t" <> remain | "\r" <> remain ->
      skip_space(remain)
    _ -> in
  }
}

// create a list of Elements
pub fn as_list(in: String) -> List(Element) {
  case in {
    "" -> []
    _ -> {
      let #(first, remain) = get_first_element(in)
      [first, ..as_list(remain)]
    }
  }
}

// create a tree of Elements where each StartElement can have children
pub fn as_tree(in: String) -> Element {
  let #(first, remain) = get_first_element(in)
  let #(result, _) = do_as_tree(remain, first)
  result
}

fn do_as_tree(in: String, current: Element) -> #(Element, String) {
  case current {
    Content(_) -> #(current, in)
    StartElement(cur_name, cur_attrs, cur_children) -> {
      case in {
        // If there's no more input and we're processing a StartElement,
        // we should treat it as self-closing
        "" -> #(
          StartElement(cur_name, cur_attrs, cur_children |> list.reverse),
          "",
        )
        _ -> {
          let #(next, remain) = get_first_element(in)
          case next {
            EndElement(name) if name == cur_name -> #(
              StartElement(cur_name, cur_attrs, cur_children |> list.reverse),
              remain,
            )
            EndElement(_) -> do_as_tree(remain, current)
            EmptyElement ->
              case remain {
                // Don't process empty elements with no remaining input
                "" -> #(
                  StartElement(
                    cur_name,
                    cur_attrs,
                    cur_children |> list.reverse,
                  ),
                  "",
                )
                _ ->
                  do_as_tree(
                    remain,
                    StartElement(cur_name, cur_attrs, [next, ..cur_children]),
                  )
              }
            _ -> {
              let #(child_tree, remain_after_child) = do_as_tree(remain, next)
              do_as_tree(
                remain_after_child,
                StartElement(cur_name, cur_attrs, [child_tree, ..cur_children]),
              )
            }
          }
        }
      }
    }
    _ -> #(current, in)
  }
}
