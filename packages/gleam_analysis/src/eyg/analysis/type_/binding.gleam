import eyg/analysis/type_/isomorphic as t
import gleam/dict

pub type Binding {
  Bound(Mono)
  Unbound(level: Int)
}

pub type Mono =
  t.Type(Int)

pub type Poly =
  t.Type(#(Bool, Int))

fn new(level, bindings) {
  let i = dict.size(bindings)
  let bindings = dict.insert(bindings, i, Unbound(level))
  #(i, bindings)
}

pub fn mono(level, bindings) {
  let #(i, bindings) = new(level, bindings)
  #(t.Var(i), bindings)
}

pub fn resolve(type_, bindings) {
  case type_ {
    t.Var(i) -> {
      // TODO minus numbers might get
      let assert Ok(binding) = dict.get(bindings, i)
      case binding {
        Bound(type_) -> resolve(type_, bindings)
        _ -> type_
      }
    }
    t.Fun(arg, eff, ret) ->
      t.Fun(
        resolve(arg, bindings),
        resolve(eff, bindings),
        resolve(ret, bindings),
      )
    t.Integer -> t.Integer
    t.Binary -> t.Binary
    t.String -> t.String
    t.Empty -> t.Empty
    t.List(el) -> t.List(resolve(el, bindings))
    t.Record(rows) -> t.Record(resolve(rows, bindings))
    t.Union(rows) -> t.Union(resolve(rows, bindings))
    t.RowExtend(label, field, rest) ->
      t.RowExtend(label, resolve(field, bindings), resolve(rest, bindings))
    t.EffectExtend(label, #(lift, reply), rest) ->
      t.EffectExtend(
        label,
        #(resolve(lift, bindings), resolve(reply, bindings)),
        resolve(rest, bindings),
      )
    t.Never -> t.Never
    t.Promise(inner) -> t.Promise(resolve(inner, bindings))
  }
}

/// Resolve the variables of a scheme that were bound after it was made,
/// as when the scope of a node is read once inference has finished.
pub fn resolve_poly(poly: Poly, bindings) -> Poly {
  case poly {
    t.Var(#(False, i)) ->
      case dict.get(bindings, i) {
        Ok(Bound(mono)) -> unquantified(resolve(mono, bindings))
        _ -> poly
      }
    t.Var(#(True, _)) -> poly
    t.Fun(arg, eff, ret) ->
      t.Fun(
        resolve_poly(arg, bindings),
        resolve_poly(eff, bindings),
        resolve_poly(ret, bindings),
      )
    t.Integer -> t.Integer
    t.Binary -> t.Binary
    t.String -> t.String
    t.Empty -> t.Empty
    t.List(el) -> t.List(resolve_poly(el, bindings))
    t.Record(rows) -> t.Record(resolve_poly(rows, bindings))
    t.Union(rows) -> t.Union(resolve_poly(rows, bindings))
    t.RowExtend(label, field, rest) ->
      t.RowExtend(
        label,
        resolve_poly(field, bindings),
        resolve_poly(rest, bindings),
      )
    t.EffectExtend(label, #(lift, reply), rest) ->
      t.EffectExtend(
        label,
        #(resolve_poly(lift, bindings), resolve_poly(reply, bindings)),
        resolve_poly(rest, bindings),
      )
    t.Never -> t.Never
    t.Promise(inner) -> t.Promise(resolve_poly(inner, bindings))
  }
}

// A resolved type as a scheme that quantifies none of its variables.
fn unquantified(mono: Mono) -> Poly {
  case mono {
    t.Var(i) -> t.Var(#(False, i))
    t.Fun(arg, eff, ret) ->
      t.Fun(unquantified(arg), unquantified(eff), unquantified(ret))
    t.Integer -> t.Integer
    t.Binary -> t.Binary
    t.String -> t.String
    t.Empty -> t.Empty
    t.List(el) -> t.List(unquantified(el))
    t.Record(rows) -> t.Record(unquantified(rows))
    t.Union(rows) -> t.Union(unquantified(rows))
    t.RowExtend(label, field, rest) ->
      t.RowExtend(label, unquantified(field), unquantified(rest))
    t.EffectExtend(label, #(lift, reply), rest) ->
      t.EffectExtend(
        label,
        #(unquantified(lift), unquantified(reply)),
        unquantified(rest),
      )
    t.Never -> t.Never
    t.Promise(inner) -> t.Promise(unquantified(inner))
  }
}

pub fn poly(level, bindings) {
  let #(i, bindings) = new(level, bindings)
  #(t.Var(#(False, i)), bindings)
}

pub fn gen(type_, level, bindings) {
  case type_ {
    t.Var(i) -> {
      let assert Ok(binding) = dict.get(bindings, i)
      case binding {
        Unbound(l) -> {
          case l > level {
            True -> t.Var(#(True, i))
            False -> t.Var(#(False, i))
          }
        }
        Bound(t) -> gen(t, level, bindings)
      }
    }
    t.Fun(arg, eff, ret) -> {
      let arg = gen(arg, level, bindings)
      let eff = gen(eff, level, bindings)
      let ret = gen(ret, level, bindings)
      t.Fun(arg, eff, ret)
    }
    t.Integer -> t.Integer
    t.Binary -> t.Binary
    t.String -> t.String
    t.Empty -> t.Empty
    t.List(el) -> t.List(gen(el, level, bindings))
    t.Record(rows) -> t.Record(gen(rows, level, bindings))
    t.Union(rows) -> t.Union(gen(rows, level, bindings))
    t.RowExtend(label, field, rest) -> {
      let field = gen(field, level, bindings)
      let rest = gen(rest, level, bindings)
      t.RowExtend(label, field, rest)
    }
    t.EffectExtend(label, #(lift, reply), rest) -> {
      let lift = gen(lift, level, bindings)
      let reply = gen(reply, level, bindings)
      let rest = gen(rest, level, bindings)
      t.EffectExtend(label, #(lift, reply), rest)
    }
    t.Never -> t.Never
    t.Promise(inner) -> t.Promise(gen(inner, level, bindings))
  }
}

pub fn instantiate(poly, level, bindings) {
  let #(mono, bindings, _) = do_inst(poly, level, bindings, dict.new())
  #(mono, bindings)
}

fn do_inst(poly, level, bindings, subs) {
  case poly {
    t.Var(#(True, i)) ->
      case dict.get(subs, i) {
        Ok(tv) -> #(tv, bindings, subs)
        Error(Nil) -> {
          let #(tv, bindings) = mono(level, bindings)
          let subs = dict.insert(subs, i, tv)
          #(tv, bindings, subs)
        }
      }
    t.Var(#(False, i)) -> #(t.Var(i), bindings, subs)
    t.Fun(arg, eff, ret) -> {
      let #(arg, bindings, subs) = do_inst(arg, level, bindings, subs)
      let #(eff, bindings, subs) = do_inst(eff, level, bindings, subs)
      let #(ret, bindings, subs) = do_inst(ret, level, bindings, subs)
      #(t.Fun(arg, eff, ret), bindings, subs)
    }
    t.Integer -> #(t.Integer, bindings, subs)
    t.Binary -> #(t.Binary, bindings, subs)
    t.String -> #(t.String, bindings, subs)
    t.Empty -> #(t.Empty, bindings, subs)
    t.List(el) -> {
      let #(el, bindings, subs) = do_inst(el, level, bindings, subs)
      #(t.List(el), bindings, subs)
    }
    t.Record(rows) -> {
      let #(rows, bindings, subs) = do_inst(rows, level, bindings, subs)
      #(t.Record(rows), bindings, subs)
    }
    t.Union(rows) -> {
      let #(rows, bindings, subs) = do_inst(rows, level, bindings, subs)
      #(t.Union(rows), bindings, subs)
    }
    t.RowExtend(label, field, rest) -> {
      let #(field, bindings, subs) = do_inst(field, level, bindings, subs)
      let #(rest, bindings, subs) = do_inst(rest, level, bindings, subs)
      #(t.RowExtend(label, field, rest), bindings, subs)
    }
    t.EffectExtend(label, #(lift, reply), rest) -> {
      let #(lift, bindings, subs) = do_inst(lift, level, bindings, subs)
      let #(reply, bindings, subs) = do_inst(reply, level, bindings, subs)
      let #(rest, bindings, subs) = do_inst(rest, level, bindings, subs)
      #(t.EffectExtend(label, #(lift, reply), rest), bindings, subs)
    }
    t.Never -> #(t.Never, bindings, subs)
    t.Promise(inner) -> {
      let #(inner, bindings, subs) = do_inst(inner, level, bindings, subs)
      #(t.Promise(inner), bindings, subs)
    }
  }
}
