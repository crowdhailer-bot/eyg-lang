// Runtime for EYG programs compiled to JavaScript generators.
//
// An effectful function is a generator function. Performing an effect yields
// a request `{l, v}` and the value sent back by `next` is the reply.
// Calling an effectful function delegates with `yield*` so a request passes
// up through every generator between the perform and the handler.
//
// A pure call may still reach a generator function, the analysis generalises
// effect rows so the same function can be used at a pure type, so the result
// of every call is checked.

import * as builtins from "./builtins.mjs";

export class Unhandled extends Error {
  constructor(label, value) {
    super("unhandled effect " + label);
    this.label = label;
    this.value = value;
  }
}

const GeneratorPrototype = Object.getPrototypeOf(function* () {}).prototype;
const Generator = Object.getPrototypeOf(GeneratorPrototype);

export function isGen(x) {
  return typeof x === "object" && x !== null && Generator.isPrototypeOf(x);
}

/// tail: evaluate tail resumptive clauses inside the handler loop.
/// Without it every handled effect starts a handler loop nested inside the
/// clause of the previous effect, and deep chains of delegation overflow the stack.
export function create(options = {}) {
  const tail = options.tail ?? true;
  const unit = builtins.unit;

  /// The value of a call made at a pure type.
  function pure(r) {
    if (!isGen(r)) return r;
    const step = r.next();
    if (!step.done) throw new Unhandled(step.value.l, step.value.v);
    return step.value;
  }

  function tailResumptive(f, t) {
    f.t = t;
    return f;
  }

  // Generators can only be resumed once. A second use of a resumption runs
  // the handled computation again from the start, replaying every reply it
  // received. This is sound because EYG programs are pure apart from effects.
  function* handle(label, h, exec) {
    const gen = exec(unit);
    if (!isGen(gen)) return gen;
    return yield* loop(label, h, exec, gen, undefined, null);
  }

  // history is a linked list of every reply sent to gen, most recent first.
  function* loop(label, h, exec, gen, input, history) {
    const inPlace = tail && h.t !== undefined ? h.t : null;
    while (true) {
      const step = gen.next(input);
      if (step.done) return step.value;
      const request = step.value;
      if (request.l !== label) {
        input = yield request;
        history = { x: input, n: history };
        continue;
      }
      if (inPlace !== null) {
        // Effects of the clause are yielded from this loop, so they reach
        // the handlers outside this one.
        let r = inPlace(request.v);
        if (isGen(r)) r = yield* r;
        input = r;
        history = { x: input, n: history };
        continue;
      }
      const snapshot = history;
      let used = false;
      const resume = (x) => {
        const history = { x, n: snapshot };
        if (!used) {
          used = true;
          return loop(label, h, exec, gen, x, history);
        }
        return loop(label, h, exec, replay(exec, snapshot), x, history);
      };
      let c = h(request.v);
      if (isGen(c)) c = yield* c;
      const r = c(resume);
      return isGen(r) ? yield* r : r;
    }
  }

  function replay(exec, history) {
    const replies = [];
    for (let e = history; e !== null; e = e.n) replies.push(e.x);
    const gen = exec(unit);
    gen.next();
    for (let i = replies.length - 1; i >= 0; i--) gen.next(replies[i]);
    return gen;
  }

  function* list_fold(items, acc, f) {
    while (items.length !== 0) {
      let g = f(items[0]);
      if (isGen(g)) g = yield* g;
      let a = g(acc);
      if (isGen(a)) a = yield* a;
      acc = a;
      items = items[1];
    }
    return acc;
  }

  function list_fold_pure(items, acc, f) {
    while (items.length !== 0) {
      acc = pure(pure(f(items[0]))(acc));
      items = items[1];
    }
    return acc;
  }

  function* binary_fold(bytes, acc, f) {
    for (let i = 0; i < bytes.length; i++) {
      let g = f(bytes[i]);
      if (isGen(g)) g = yield* g;
      let a = g(acc);
      if (isGen(a)) a = yield* a;
      acc = a;
    }
    return acc;
  }

  function binary_fold_pure(bytes, acc, f) {
    for (let i = 0; i < bytes.length; i++) acc = pure(pure(f(bytes[i]))(acc));
    return acc;
  }

  function* fix(builder) {
    function* self(x) {
      let g = builder(self);
      if (isGen(g)) g = yield* g;
      const r = g(x);
      return isGen(r) ? yield* r : r;
    }
    let g = builder(self);
    if (isGen(g)) g = yield* g;
    return g;
  }

  function fix_pure(builder) {
    let g = null;
    const self = (x) => g(x);
    g = builder(self);
    return g;
  }

  function run(main, platform = {}) {
    const r = main();
    if (!isGen(r)) return r;
    return drive(r, platform, undefined);
  }

  function drive(gen, platform, input) {
    while (true) {
      const step = gen.next(input);
      if (step.done) return step.value;
      const request = step.value;
      const impl = platform[request.l];
      if (impl === undefined) throw new Unhandled(request.l, request.v);
      if (impl.sync) {
        input = impl.sync(request.v);
      } else {
        return impl.async(request.v).then((x) => drive(gen, platform, x));
      }
    }
  }

  return {
    isGen,
    pure,
    handle,
    tailResumptive,
    list_fold,
    list_fold_pure,
    binary_fold,
    binary_fold_pure,
    fix,
    fix_pure,
    run,
    builtins,
    options: { tail },
  };
}
