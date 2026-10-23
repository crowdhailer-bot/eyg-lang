import eyg/ir/tree as ir
import gleam/int
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import gleam/string
import morph/editable as e
import morph/frame.{Class, Path, Span, Text, Title}
import morph/highlight
import morph/projection as t
import multiformats/cid/v1

// Prism tokens https://prismjs.com/tokens.html

pub const collapsed = "token comment"

pub const variable = "token punctuation"

pub const vacant = "token important"

// normally rendered the same as string
pub const binary = "token char"

pub const integer = "token number"

pub const string = "token string"

pub const tag = "token class-name"

// This is effect name
pub const effect = "token class-name"

pub const keyword = "token keyword"

pub const builtin = "token builtin"

pub const reference = "token symbol"

pub fn do_let(rev, pattern, value) {
  let assignment =
    list.flatten([
      [Span([exp_key(rev)], [Text("let ")])],
      pattern,
      [Span([exp_key(rev)], [Text(" = ")])],
    ])
  frame.prepend_spans(assignment, value)
}

pub fn assign(p, value, rev, errors) {
  do_let(rev, pattern(p, [0, ..rev]), expression(value, [1, ..rev], errors))
}

pub fn assigns(a, rev, errors) {
  list.index_map(a, fn(a, i) { assign_pair(a, [i, ..rev], errors) })
  |> frame.to_fat_lines()
}

// ignore tail vacant will need for spotless history
pub fn statements(code, errors) {
  let rev = []
  case code {
    e.Block(assigns, e.Vacant, _) ->
      list.index_map(assigns, fn(a, i) { assign_pair(a, [i, ..rev], errors) })
    e.Block(assigns, tail, _) -> block_content(assigns, tail, rev, errors)
    exp -> [expression(exp, rev, errors)]
  }
  |> frame.to_fat_lines()
}

// is for unwrapped block
pub fn top(code, errors) {
  let rev = []

  case code {
    e.Block(assigns, tail, _) -> block_content(assigns, tail, rev, errors)
    exp -> [expression(exp, rev, errors)]
  }
  |> frame.to_fat_lines()
}

fn block_content(assigns, tail, rev, errors) {
  list.index_map(assigns, fn(a, i) { assign_pair(a, [i, ..rev], errors) })
  |> list.append([expression(tail, [list.length(assigns), ..rev], errors)])
}

fn assign_pair(kv, rev, errors) {
  let #(label, value) = kv
  assign(label, value, rev, errors)
}

pub fn pattern(p, rev) {
  case p {
    e.Bind(x) -> [Span([exp_key(rev)], [Text(x)])]
    e.Destructure(fields) -> {
      list.index_map(fields, fn(f, i) { do_field(f, i, rev) })
      |> do_destructured(rev)
    }
  }
}

pub fn do_field(f, i, rev) {
  let i = i * 2
  let j = i + 1
  let #(field, var) = f
  [
    Span([exp_key([i, ..rev])], [Text(field)]),
    Span([], [Text(": ")]),
    Span([exp_key([j, ..rev])], [Text(var)]),
  ]
}

pub fn do_destructured(fields, rev) {
  fields
  |> list.intersperse([Span([], [Text(", ")])])
  |> list.flatten
  |> list.append([Span([exp_key(rev)], [Text("}")])])
  |> list.append([Span([exp_key(rev)], [Text("{")])], _)
}

pub fn patterns(ps, rev) {
  list.index_map(ps, fn(p, i) { pattern(p, [i, ..rev]) })
  |> join_patterns()
}

pub fn join_patterns(ps) {
  ps
  |> list.intersperse([Text(", ")])
  |> list.flatten
  |> list.append([Text(")")])
  |> list.append([Text("(")], _)
}

fn render_args(args, rev, errors) {
  // 0 is the call
  let args =
    list.index_map(args, fn(a, i) { expression(a, [i + 1, ..rev], errors) })
  let assert [last, ..rest] = list.reverse(args)
  render_args_rev(last, rest)
}

fn render_args_e(args) {
  let assert [last, ..rest] = list.reverse(args)
  render_args_rev(last, rest)
}

fn render_args_rev(last, rest) {
  case frame.all_inline(rest) {
    Ok(spanss) ->
      list.fold(spanss, last, fn(tail, spans) {
        tail
        |> frame.prepend_spans([Text(", ")], _)
        |> frame.prepend_spans(spans, _)
      })
    Error(Nil) -> {
      list.reverse([last, ..rest])
      |> list.map(frame.append_spans(_, [Text(",")]))
      |> frame.to_fat_lines
      |> frame.Multiline([], _, [])
    }
  }
}

pub fn render_call(f, args) {
  let args =
    args
    |> frame.prepend_spans([Text("(")], _)
    |> frame.append_spans([Text(")")])

  case f {
    frame.Inline(fspans) -> frame.prepend_spans(fspans, args)
    frame.Statements(inner) -> {
      let f = frame.Multiline([Text("{")], inner, [Text("}")])
      frame.join(f, args)
    }
    frame.Multiline(_, _, _) -> frame.join(f, args)
  }
}

fn exp_key(rev) {
  Path(list.reverse(rev))
}

fn continue_space(rev) {
  frame.Inline([Span([Class(collapsed), exp_key(rev)], [Text("...")])])
}

/// errors are identified by their reverse path
pub fn expression(exp, rev, errors) {
  let frame = case exp {
    e.Block(_, _, False) -> frame.Inline([Text("{ ... }")])
    e.Block(assigns, tail, True) ->
      frame.Multiline(
        [Span([], [Text("{")])],
        frame.to_fat_lines(block_content(assigns, tail, rev, errors)),
        [Span([], [Text("}")])],
      )
    e.Call(f, args) -> {
      let args = render_args(args, rev, errors)
      let f = expression(f, [0, ..rev], errors)
      render_call(f, args)
    }
    // defninetly multiline don't wrap in double curlies
    // e.Function(args, e.Block(assigns, tail)) ->
    // render_function(patterns(args), block_content(assigns, tail))
    // frame.Multiline(
    //   [h.span([], [text("("), patterns(args), text(") -> {")])],
    //   frame.to_fat_lines(block_content(assigns, tail)),
    //   [h.span([], [text("}")])],
    // )
    e.Function(args, body) -> {
      render_function(
        patterns(args, rev),
        expression(body, [list.length(args), ..rev], errors),
        rev,
      )
    }
    e.Vacant ->
      frame.Inline([Span([Class(vacant), exp_key(rev)], [Text("Vacant")])])
    e.Variable(x) ->
      frame.Inline([Span([Class(variable), exp_key(rev)], [Text(x)])])
    e.Integer(v) ->
      frame.Inline([
        Span([Class(integer), exp_key(rev)], [Text(int.to_string(v))]),
      ])
    e.Binary(bytes) ->
      frame.Inline([
        Span([Class(binary), exp_key(rev)], [Text(string.inspect(bytes))]),
      ])

    e.String(v) ->
      frame.Inline([
        Span([Class(string), exp_key(rev)], [
          Text("\""),
          Text(v),
          Text("\""),
        ]),
      ])
    e.List(items, tail) -> {
      render_list(
        list.index_map(items, fn(item, i) {
          expression(item, [i, ..rev], errors)
        }),
        option.map(tail, expression(_, [list.length(items), ..rev], errors)),
        rev,
      )
    }
    e.Record(fields, original) -> {
      let len = list.length(fields) * 2
      render_record(
        list.index_map(fields, fn(field, i) {
          render_field(field, i * 2, rev, errors)
        }),
        option.map(original, expression(_, [len, ..rev], errors)),
        rev,
      )
    }
    e.Select(from, label) ->
      expression(from, [0, ..rev], errors)
      |> frame.append_spans([
        Text("."),
        Span([exp_key([1, ..rev])], [Text(label)]),
      ])
    e.Tag(label) ->
      frame.Inline([Span([Class(tag), exp_key(rev)], [Text(label)])])
    e.Case(top, matches, otherwise) -> {
      let top = expression(top, [0, ..rev], errors)
      let matches =
        list.index_map(matches, fn(match, i) {
          render_branch(match, [i + 1, ..rev], errors)
        })
      let otherwise =
        option.map(otherwise, expression(
          _,
          [list.length(matches) + 1, ..rev],
          errors,
        ))
      render_case(top, matches, otherwise, rev)
    }
    e.Perform(label) ->
      frame.Inline([
        Span([Class(keyword)], [Text("perform ")]),
        Span([Class(effect), exp_key(rev)], [Text(label)]),
      ])
    e.Deep(label) ->
      frame.Inline([
        Span([Class(keyword)], [Text("handle ")]),
        Span([Class(effect), exp_key(rev)], [Text(label)]),
      ])
    e.Builtin(identifier) ->
      frame.Inline([
        Span([Class(builtin), exp_key(rev)], [Text("!"), Text(identifier)]),
      ])
    e.Reference(ir.Content(cid)) ->
      frame.Inline([
        Span([Class(reference), exp_key(rev)], [
          Text(v1.to_string(cid)),
        ]),
      ])
    e.Reference(ir.Relative(location)) ->
      frame.Inline([
        Span(
          [
            Class(reference),
            exp_key(rev),
          ],
          [Text(location)],
        ),
      ])
    e.Reference(ir.Package(package:)) ->
      frame.Inline([
        Span(
          [
            Class(reference),
            exp_key(rev),
          ],
          [Text("@" <> package)],
        ),
      ])
    e.Reference(ir.Version(package:, version:)) ->
      frame.Inline([
        Span(
          [
            Class(reference),
            exp_key(rev),
            Title("release = " <> int.to_string(version)),
          ],
          [Text("@" <> package <> ":" <> int.to_string(version))],
        ),
      ])
    e.Reference(ir.Pinned(ir.Release(package:, version:, module:))) ->
      frame.Inline([
        Span(
          [
            Class(reference),
            exp_key(rev),
            Title("module = " <> v1.to_string(module)),
          ],
          [Text("@" <> package <> ":" <> int.to_string(version))],
        ),
      ])
  }
  case list.key_find(errors, rev), exp {
    _, e.Vacant -> frame
    Ok(_), _ -> highlight.frame(frame, highlight.error())
    Error(_), _ -> frame
  }
}

pub fn render_function(args, body, rev) {
  body
  // TODO handle spaces on wrapping
  |> frame.prepend_spans([Span([exp_key(rev)], [Text(" -> ")])], _)
  |> frame.prepend_spans(args, _)
  // |> frame.append_spans([text(" }")])
}

pub fn render_list(items, tail, rev) {
  let tail = case tail {
    Some(tail) -> [frame.prepend_spans([Text("..")], tail)]
    None -> []
  }
  let items = list.append(items, tail)
  let items = frame.delimit(items, ", ")
  case frame.all_inline(items) {
    Ok(spans) ->
      frame.Inline([
        Span(
          [exp_key(rev)],
          list.flatten([[Text("[")], list.flatten(spans), [Text("]")]]),
        ),
      ])
    Error(Nil) -> {
      let inner = frame.to_fat_lines(items)
      frame.Multiline([Span([exp_key(rev)], [Text("[")])], inner, [
        Span([exp_key(rev)], [Text("]")]),
      ])
    }
  }
}

pub fn render_record(fields, original, rev) {
  let original = case original {
    Some(original) -> [frame.prepend_spans([Text("..")], original)]
    None -> []
  }
  let fields = list.append(fields, original)
  let fields = frame.delimit(fields, ", ")

  case frame.all_inline(fields) {
    Ok(spans) ->
      frame.Inline([
        Span(
          [exp_key(rev)],
          list.flatten([[Text("{")], list.flatten(spans), [Text("}")]]),
        ),
      ])
    Error(Nil) -> {
      let inner = frame.to_fat_lines(fields)
      frame.Multiline([Span([exp_key(rev)], [Text("{")])], inner, [
        Span([exp_key(rev)], [Text("}")]),
      ])
    }
  }
}

pub fn render_field(field, i, rev, errors) {
  let #(label, value) = field
  let value = expression(value, [i + 1, ..rev], errors)
  frame.prepend_spans(
    [Span([exp_key([i, ..rev])], [Text(label), Text(": ")])],
    value,
  )
}

pub fn do_render_field(field, rev) {
  let #(label, value) = field
  frame.prepend_spans(
    [Span([], [Span([exp_key(rev)], [Text(label)]), Text(": ")])],
    value,
  )
}

pub fn render_case(top, branches, otherwise, rev) {
  let spans = case top {
    frame.Inline(spans) -> spans
    _ -> {
      [Text("some big case")]
    }
  }
  list.append(branches, case otherwise {
    Some(otherwise) -> [otherwise]
    None -> []
  })
  |> frame.to_fat_lines
  |> frame.Multiline([Text(" {")], _, [Text("}")])
  |> frame.prepend_spans(spans, _)
  |> frame.prepend_spans([Span([exp_key(rev)], [Text("match ")])], _)
}

pub fn render_branch(field, rev, errors) {
  let #(label, value) = field
  let value = expression(value, [0, ..rev], errors)
  frame.prepend_spans(
    [Span([Class(tag), exp_key(rev)], [Text(label), Text(" ")])],
    value,
  )
}

pub type RenderKind {
  Statements
  Expression
  ReadonlyStatements
}

// rev passed in here is rest of rev
fn render_break(break, inner, rev, kind, errors) {
  let frame = case break {
    t.CallFn(args) -> render_call(inner, render_args(args, rev, errors))
    t.CallArg(f, pre, post) -> {
      let self = list.length(pre) + 1
      let pre =
        list.index_map(pre, fn(arg, i) {
          expression(arg, [self - i - 1, ..rev], errors)
        })
      let post =
        list.index_map(post, fn(arg, i) {
          expression(arg, [self + i + 1, ..rev], errors)
        })
      let args = listx.gather_around(pre, inner, post)
      render_call(expression(f, [0, ..rev], errors), render_args_e(args))
    }
    t.Body(args) -> render_function(patterns(args, rev), inner, rev)
    t.ListItem(pre, post, tail) -> {
      let self = list.length(pre)
      let pre =
        list.index_map(pre, fn(item, i) {
          expression(item, [self - i - 1, ..rev], errors)
        })
      let post =
        list.index_map(post, fn(item, i) {
          expression(item, [self + i + 1, ..rev], errors)
        })
      let len = self + 1 + list.length(post)
      render_list(
        listx.gather_around(pre, inner, post),
        option.map(tail, expression(_, [len, ..rev], errors)),
        rev,
      )
    }
    t.ListTail(items) ->
      render_list(
        list.index_map(items, fn(item, i) {
          expression(item, [i, ..rev], errors)
        }),
        Some(inner),
        rev,
      )
    t.RecordValue(l, pre, post, for) -> {
      let self = list.length(pre) * 2
      let pre =
        list.index_map(pre, fn(field, i) {
          render_field(field, self - i * 2 - 2, rev, errors)
        })
      let post =
        list.index_map(post, fn(field, i) {
          render_field(field, self + i * 2 + 2, rev, errors)
        })
      let inner = do_render_field(#(l, inner), [self, ..rev])
      let len = self + { 1 + list.length(post) } * 2
      let original = case for {
        t.Record -> None
        t.Overwrite(original) ->
          Some(expression(original, [len, ..rev], errors))
      }
      render_record(listx.gather_around(pre, inner, post), original, rev)
    }
    t.SelectValue(label) ->
      inner
      |> frame.append_spans([
        Text("."),
        Span([exp_key([1, ..rev])], [Text(label)]),
      ])
    t.OverwriteTail(fields) -> {
      let fields =
        list.index_map(list.reverse(fields), fn(field, i) {
          render_field(field, i * 2, rev, errors)
        })
      render_record(fields, Some(inner), rev)
    }
    t.BlockValue(p, pre, post, then) -> {
      let self = list.length(pre)
      let pre =
        list.index_map(pre, fn(a, i) {
          assign_pair(a, [self - i - 1, ..rev], errors)
        })
      let post =
        list.index_map(post, fn(a, i) {
          assign_pair(a, [self + 1 + i, ..rev], errors)
        })
      let assign = do_let([self, ..rev], pattern(p, [0, self, ..rev]), inner)
      let assignments = listx.gather_around(pre, assign, post)
      let len = self + 1 + list.length(post)
      case kind, rev, then {
        Statements, [], e.Vacant ->
          list.append(assignments, [continue_space([len, ..rev])])
        ReadonlyStatements, [], e.Vacant -> assignments
        _, _, _ ->
          list.append(assignments, [expression(then, [len, ..rev], errors)])
      }
      |> frame.to_fat_lines()
      |> frame.Statements
    }
    t.BlockTail(assigns) -> {
      let lines =
        list.index_map(assigns, fn(a, i) { assign_pair(a, [i, ..rev], errors) })
        |> list.append([inner])
      frame.Statements(frame.to_fat_lines(lines))
    }
    t.CaseTop(matches, otherwise) -> {
      let matches =
        list.index_map(matches, fn(m, i) {
          render_branch(m, [i + 1, ..rev], errors)
        })
      let otherwise =
        option.map(otherwise, expression(
          _,
          [list.length(matches) + 1, ..rev],
          errors,
        ))
      render_case(inner, matches, otherwise, rev)
    }
    t.CaseMatch(top, label, pre, post, otherwise) -> {
      let top = expression(top, [0, ..rev], errors)
      let self = list.length(pre) + 1
      let pre =
        list.index_map(pre, fn(branch, i) {
          render_branch(branch, [self - i - 1, ..rev], errors)
        })
      let post =
        list.index_map(post, fn(branch, i) {
          render_branch(branch, [self + 1 + i, ..rev], errors)
        })
      let branch =
        frame.prepend_spans(
          [
            Span([Class(tag), exp_key([self, ..rev])], [
              Text(label),
              Text(" "),
            ]),
          ],
          inner,
        )
      let len = self + 1 + list.length(post)
      let otherwise = option.map(otherwise, expression(_, [len, ..rev], errors))

      render_case(top, listx.gather_around(pre, branch, post), otherwise, rev)
    }
    t.CaseTail(top, matches) -> {
      let top = expression(top, [0, ..rev], errors)
      let matches =
        list.index_map(matches, fn(m, i) {
          render_branch(m, [i + 1, ..rev], errors)
        })
      render_case(top, matches, Some(inner), rev)
    }
  }
  case list.key_find(errors, list.reverse(rev)) {
    Ok(_) -> highlight.frame(frame, highlight.error())
    Error(_) -> frame
  }
}

pub fn push_render(frame, zoom, is_expression, errors) {
  case zoom {
    [] -> frame
    [break, ..rest] -> {
      let frame =
        render_break(
          break,
          frame,
          list.reverse(t.path_to_zoom(rest, [])),
          is_expression,
          errors,
        )
      push_render(frame, rest, is_expression, errors)
    }
  }
}

// Not used any more
// pub fn projection(zip, kind) -> element.Element(a) {
//   let #(_focus, zoom) = zip
//   // This is NOT reversed because zoom works from inside out
//   let frame = projection_frame(zip, kind)
//   push_render(frame, zoom, kind)
//   |> frame.to_fat_line
//   // TO fat line is very similar to top function
// }

pub fn projection_frame(zip, kind, errors) {
  let #(focus, zoom) = zip
  let path = t.path_to_zoom(zoom, [])
  let rev = list.reverse(path)

  case focus {
    // Doesnt work for copy paste
    // t.Exp(e.Vacant) ->
    //   highlight.frame(
    //     frame.Inline([
    //       // made as an input for copy paste
    //       h.input([
    //         exp_key(rev),
    //         a.placeholder("Vacant"),
    //         a.class("placeholder-red-700 w-14 outline-none bg-transparent"),
    //         a.id("highlighted"),
    //         a.style([#("caret-color", "transparent")]),
    //         // TODO does the paste event bubble
    //         // if works we need a paste with path location
    //         event.on("keydown", fn(event) {
    //           event.prevent_default(event)
    //           Error([])
    //         }),
    //       ]),
    //     ]),
    //   )
    t.Exp(exp) ->
      highlight.frame(expression(exp, rev, errors), highlight.focus())
    t.Assign(detail, value, pre, post, then) -> {
      let self = list.length(pre)
      let pre =
        list.index_map(pre, fn(a, i) {
          do_assign(a, [self - i - 1, ..rev], errors)
        })
      let post =
        list.index_map(post, fn(a, i) {
          do_assign(a, [self + 1 + i, ..rev], errors)
        })

      let assign = case detail {
        // get rid of assign statement then do_let goes on the outside
        t.AssignStatement(p) ->
          highlight.frame(
            assign(p, value, [self, ..rev], errors),
            highlight.focus(),
          )
        t.AssignPattern(p) -> {
          let p = [
            highlight.spans(pattern(p, [0, self, ..rev]), highlight.focus()),
          ]
          do_let([self, ..rev], p, expression(value, [1, self, ..rev], errors))
        }
        t.AssignField(label, var, pre, post) -> {
          // to the pattern
          let rev = [0, self, ..rev]
          let self = list.length(pre) * 2
          let spans = [
            highlight.spans(
              [Span([exp_key([self, ..rev])], [Text(label)])],
              highlight.focus(),
            ),
            Span([], [Text(": ")]),
            Span([exp_key([self + 1, ..rev])], [Text(var)]),
          ]
          let pre =
            list.index_map(pre, fn(f, i) { do_field(f, self - 2 - 2 * i, rev) })
          let post =
            list.index_map(post, fn(f, i) { do_field(f, self + 2 + 2 * i, rev) })
          let pattern =
            do_destructured(listx.gather_around(pre, spans, post), rev)
          do_let(
            [self, ..rev],
            pattern,
            expression(value, [1, self, ..rev], errors),
          )
        }
        t.AssignBind(label, var, pre, post) -> {
          let rev = [0, self, ..rev]
          let self = list.length(pre) * 2
          let spans = [
            Span([exp_key([self, ..rev])], [Text(label)]),
            Span([], [Text(": ")]),
            highlight.spans(
              [Span([exp_key(rev)], [Text(var)])],
              highlight.focus(),
            ),
          ]
          let pre =
            list.index_map(pre, fn(f, i) { do_field(f, self - 2 - 2 * i, rev) })
          let post =
            list.index_map(post, fn(f, i) { do_field(f, self + 2 + 2 * i, rev) })
          let pattern =
            do_destructured(listx.gather_around(pre, spans, post), rev)
          do_let([self, ..rev], pattern, expression(value, [1, ..rev], errors))
        }
      }
      let len = list.length(pre) + list.length(post) + 1

      let assignments = listx.gather_around(pre, assign, post)
      let frame =
        case kind, rev, then {
          Statements, [], e.Vacant ->
            list.append(assignments, [continue_space([len, ..rev])])
          ReadonlyStatements, [], e.Vacant -> assignments
          _, _, _ ->
            list.append(assignments, [expression(then, [len, ..rev], errors)])
        }
        |> frame.to_fat_lines
        |> frame.Statements
      case list.key_find(errors, list.reverse(rev)) {
        Ok(_) -> highlight.frame(frame, highlight.error())
        Error(_) -> frame
      }
    }
    t.FnParam(detail, pre, post, body) -> {
      let self = list.length(pre)
      let len = self + list.length(post) + 1
      let pre =
        list.index_map(pre, fn(p, i) { pattern(p, [self - 1 - i, ..rev]) })
      let post =
        list.index_map(post, fn(p, i) { pattern(p, [self + 1 + i, ..rev]) })
      let pattern = case detail {
        t.AssignStatement(p) -> [
          highlight.spans(pattern(p, [self, ..rev]), highlight.focus()),
        ]
        t.AssignPattern(p) -> [
          highlight.spans(pattern(p, [self, ..rev]), highlight.focus()),
        ]

        t.AssignField(label, var, pre, post) -> {
          let rev = [self, ..rev]
          let self = list.length(pre) * 2
          let spans = [
            highlight.spans(
              [Span([exp_key([self, ..rev])], [Text(label)])],
              highlight.focus(),
            ),
            Span([], [Text(": ")]),
            Span([exp_key([self + 1, ..rev])], [Text(var)]),
          ]
          let pre =
            list.index_map(pre, fn(f, i) { do_field(f, self - 2 - 2 * i, rev) })
          let post =
            list.index_map(post, fn(f, i) { do_field(f, self + 2 + 2 * i, rev) })
          do_destructured(listx.gather_around(pre, spans, post), rev)
        }
        t.AssignBind(label, var, pre, post) -> {
          let rev = [self, ..rev]
          let self = list.length(pre) * 2
          let spans = [
            Span([exp_key([self, ..rev])], [Text(label)]),
            Span([], [Text(": ")]),
            highlight.spans(
              [Span([exp_key(rev)], [Text(var)])],
              highlight.focus(),
            ),
          ]
          let pre =
            list.index_map(pre, fn(f, i) { do_field(f, self - 2 - 2 * i, rev) })
          let post =
            list.index_map(post, fn(f, i) { do_field(f, self + 2 + 2 * i, rev) })
          do_destructured(listx.gather_around(pre, spans, post), rev)
        }
      }
      let patterns = listx.gather_around(pre, pattern, post)
      let patterns = join_patterns(patterns)
      render_function(patterns, expression(body, [len, ..rev], errors), rev)
    }
    t.Label(label, value, pre, post, for) -> {
      let self = list.length(pre) * 2
      let len = self + { list.length(post) + 1 } * 2
      let value = expression(value, [self + 1, ..rev], errors)
      let label = highlight.spans([Text(label)], highlight.focus())
      let field = frame.prepend_spans([label, Text(": ")], value)

      let pre =
        list.index_map(pre, fn(field, i) {
          render_field(field, self - i * 2 - 2, rev, errors)
        })
      let post =
        list.index_map(post, fn(field, i) {
          render_field(field, self + i * 2 + 2, rev, errors)
        })
      let original = case for {
        t.Record -> None
        t.Overwrite(original) ->
          Some(expression(original, [len, ..rev], errors))
      }

      let frame =
        render_record(listx.gather_around(pre, field, post), original, rev)
      case list.key_find(errors, list.reverse(rev)) {
        Ok(_) -> highlight.frame(frame, highlight.error())
        Error(_) -> frame
      }
    }
    t.Select(label, from) -> {
      let from = expression(from, rev, errors)
      let frame =
        from
        |> frame.append_spans([
          highlight.spans(
            [Text("."), Span([exp_key(rev)], [Text(label)])],
            highlight.focus(),
          ),
        ])
      case list.key_find(errors, list.reverse(rev)) {
        Ok(_) -> highlight.frame(frame, highlight.error())
        Error(_) -> frame
      }
    }
    t.Match(top, label, value, pre, post, otherwise) -> {
      let self = list.length(pre) + 1
      let len = self + list.length(post) + 1
      let value = expression(value, [0, self, ..rev], errors)
      let branch =
        frame.prepend_spans(
          [
            highlight.spans(
              [Span([Class(tag)], [Text(label)])],
              highlight.focus(),
            ),
            Text(" "),
          ],
          value,
        )
      let pre =
        list.index_map(pre, fn(branch, i) {
          render_branch(branch, [self - i - 1, ..rev], errors)
        })
      let post =
        list.index_map(post, fn(branch, i) {
          render_branch(branch, [self + i + 1, ..rev], errors)
        })
      let frame =
        render_case(
          expression(top, [0, ..rev], errors),
          listx.gather_around(pre, branch, post),
          option.map(otherwise, expression(_, [len, ..rev], errors)),
          rev,
        )
      case list.key_find(errors, list.reverse(rev)) {
        Ok(_) -> highlight.frame(frame, highlight.error())
        Error(_) -> frame
      }
    }
  }
}

fn do_assign(kv, rev, errors) {
  let #(label, value) = kv
  assign(label, value, rev, errors)
}
