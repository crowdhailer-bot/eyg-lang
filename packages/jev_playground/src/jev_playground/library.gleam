//// Libraries are EYG modules referenced by content id.
//// A bundle holds modules in dependency order and the names they are released under.
//// Bundles are built from files where a hash function is available and are
//// serialised to JSON for the browser, which cannot hash synchronously.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/interpreter/value as v
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import filepath
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result.{try}
import gleam/string
import jev_playground/environment.{type Environment, Environment, Library}
import jev_playground/run
import multiformats/cid/v1

pub type Module {
  Module(cid: v1.Cid, source: ir.Node(Nil))
}

pub type Release {
  Release(name: String, version: Int, module: v1.Cid)
}

pub type Bundle {
  Bundle(modules: List(Module), releases: List(Release))
}

pub const empty = Bundle([], [])

pub type Read =
  fn(String) -> Result(BitArray, String)

/// Load a module and the modules it imports, relative imports become content references.
pub fn load(
  bundle: Bundle,
  path: String,
  read: Read,
  hash: fn(BitArray) -> BitArray,
) -> Result(#(Bundle, v1.Cid), String) {
  use bits <- try(read(path))
  use source <- try(case string.ends_with(path, ".json") {
    True ->
      json.parse_bits(bits, dag_json.decoder(Nil))
      |> result.replace_error("could not decode " <> path)
    False -> {
      use text <- try(
        bit_array.to_string(bits)
        |> result.replace_error(path <> " is not text"),
      )
      parser.all_from_string(text)
      |> result.map(annotate(_, Nil))
      |> result.replace_error("could not parse " <> path)
    }
  })
  let directory = filepath.directory_name(path)
  use #(bundle, source) <- try(
    imports(source, bundle, fn(bundle, relative) {
      load(bundle, filepath.join(directory, relative), read, hash)
    }),
  )
  let id =
    cid.from_tree(source, fn(bytes) { fn(k) { k(hash(bytes)) } })(fn(c) { c })
  let known = list.any(bundle.modules, fn(module) { module.cid == id })
  let modules = case known {
    True -> bundle.modules
    False -> list.append(bundle.modules, [Module(id, source)])
  }
  Ok(#(Bundle(..bundle, modules:), id))
}

/// Load a module and release it under a name.
pub fn release(bundle, name, version, path, read, hash) {
  use #(bundle, id) <- try(load(bundle, path, read, hash))
  let releases = list.append(bundle.releases, [Release(name, version, id)])
  Ok(Bundle(..bundle, releases:))
}

// Replace every relative import with a content reference.
fn imports(node: ir.Node(Nil), bundle, resolve) {
  let #(exp, meta) = node
  case exp {
    ir.Reference(ir.Relative(path)) -> {
      use #(bundle, id) <- try(resolve(bundle, path))
      Ok(#(bundle, #(ir.Reference(ir.Content(id)), meta)))
    }
    ir.Lambda(label, body) -> {
      use #(bundle, body) <- try(imports(body, bundle, resolve))
      Ok(#(bundle, #(ir.Lambda(label, body), meta)))
    }
    ir.Apply(func, arg) -> {
      use #(bundle, func) <- try(imports(func, bundle, resolve))
      use #(bundle, arg) <- try(imports(arg, bundle, resolve))
      Ok(#(bundle, #(ir.Apply(func, arg), meta)))
    }
    ir.Let(label, value, then) -> {
      use #(bundle, value) <- try(imports(value, bundle, resolve))
      use #(bundle, then) <- try(imports(then, bundle, resolve))
      Ok(#(bundle, #(ir.Let(label, value, then), meta)))
    }
    _ -> Ok(#(bundle, node))
  }
}

/// Add every module of the bundle to the environment, with its type and value.
/// Modules that are not released are named by their content id.
pub fn environment(
  bundle: Bundle,
  base: Environment,
) -> Result(Environment, String) {
  list.try_fold(bundle.modules, base, fn(environment, module) {
    let Module(cid: id, source:) = module
    let found = list.find(bundle.releases, fn(release) { release.module == id })
    let #(name, version) = case found {
      Ok(Release(name:, version:, ..)) -> #(name, version)
      Error(Nil) -> #("#" <> v1.to_string(id), 0)
    }
    let analysis =
      infer.check_with_references(
        infer.pure(),
        environment.references(environment),
        source,
      )
    let type_ = infer.poly_type(analysis)
    let annotated = annotate(source, [])
    use value <- try(
      run.evaluate(annotated, environment)
      |> result.map_error(fn(reason) {
        name <> " failed to evaluate: " <> reason
      }),
    )
    let readme = case value {
      v.Record(fields) ->
        case dict.get(fields, "readme") {
          Ok(v.String(readme)) -> readme
          _ -> ""
        }
      _ -> ""
    }
    let library =
      Library(
        name:,
        release: ir.Release(name, version, id),
        type_:,
        value:,
        readme:,
        source:,
      )
    Ok(
      Environment(
        ..environment,
        libraries: list.append(environment.libraries, [library]),
      ),
    )
  })
}

// `ir.map_annotation` is built on continuations and overflows the stack in
// browsers for modules as large as the standard library, this recursion only
// goes as deep as the tree.
fn annotate(node: ir.Node(a), meta: b) -> ir.Node(b) {
  let #(exp, _) = node
  let exp = case exp {
    ir.Lambda(label, body) -> ir.Lambda(label, annotate(body, meta))
    ir.Apply(func, arg) -> ir.Apply(annotate(func, meta), annotate(arg, meta))
    ir.Let(label, value, then) ->
      ir.Let(label, annotate(value, meta), annotate(then, meta))
    ir.Variable(x) -> ir.Variable(x)
    ir.Binary(x) -> ir.Binary(x)
    ir.Integer(x) -> ir.Integer(x)
    ir.String(x) -> ir.String(x)
    ir.Tail -> ir.Tail
    ir.Cons -> ir.Cons
    ir.Vacant -> ir.Vacant
    ir.Empty -> ir.Empty
    ir.Extend(x) -> ir.Extend(x)
    ir.Select(x) -> ir.Select(x)
    ir.Overwrite(x) -> ir.Overwrite(x)
    ir.Tag(x) -> ir.Tag(x)
    ir.Case(x) -> ir.Case(x)
    ir.NoCases -> ir.NoCases
    ir.Perform(x) -> ir.Perform(x)
    ir.Handle(x) -> ir.Handle(x)
    ir.Builtin(x) -> ir.Builtin(x)
    ir.Reference(x) -> ir.Reference(x)
  }
  #(exp, meta)
}

/// Whether a library is released under a name, rather than imported by another.
pub fn is_released(library: environment.Library) {
  !string.starts_with(library.name, "#")
}

pub fn to_json(bundle: Bundle) -> json.Json {
  json.object([
    #(
      "modules",
      json.array(bundle.modules, fn(module) {
        json.object([
          #("cid", json.string(v1.to_string(module.cid))),
          #("source", dag_json.to_data_model(module.source)),
        ])
      }),
    ),
    #(
      "releases",
      json.array(bundle.releases, fn(release) {
        json.object([
          #("name", json.string(release.name)),
          #("version", json.int(release.version)),
          #("module", json.string(v1.to_string(release.module))),
        ])
      }),
    ),
  ])
}

pub fn decoder() -> decode.Decoder(Bundle) {
  let cid_decoder = {
    use text <- decode.then(decode.string)
    case v1.from_string(text) {
      Ok(#(id, _)) -> decode.success(id)
      Error(_) -> decode.failure(placeholder(), "cid")
    }
  }
  use modules <- decode.field(
    "modules",
    decode.list({
      use id <- decode.field("cid", cid_decoder)
      use source <- decode.field("source", dag_json.decoder(Nil))
      decode.success(Module(id, source))
    }),
  )
  use releases <- decode.field(
    "releases",
    decode.list({
      use name <- decode.field("name", decode.string)
      use version <- decode.field("version", decode.int)
      use module <- decode.field("module", cid_decoder)
      decode.success(Release(name, version, module))
    }),
  )
  decode.success(Bundle(modules:, releases:))
}

fn placeholder() {
  let assert Ok(#(id, _)) =
    v1.from_string(
      "baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja",
    )
  id
}
