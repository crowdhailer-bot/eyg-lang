// Runtime for EYG programs compiled with generalized evidence passing.
//
// Xie and Leijen, Generalized Evidence Passing for Effect Handlers, ICFP 2021.
//
// The monad of the paper is not reified. As in the C backend of Koka a
// function returns normally when it is pure and sets the `y` field of the
// shared state when it is yielding, in which case the returned value is
// ignored. The current evidence vector is kept in the `w` field.

import * as builtins from "./builtins.mjs";

export class Unhandled extends Error {
  constructor(label, value) {
    super("unhandled effect " + label);
    this.label = label;
    this.value = value;
  }
}

/// Options must match the options the program was compiled with.
///
/// evidence: "map" constant time lookup, copies the vector when a handler is installed.
///           "linked" insertion ordered linked list, linear lookup.
///           "none" no evidence, every perform yields and bubbles to its handler.
/// tail:     evaluate tail resumptive clauses in place.
/// shortcut: build resumptions as an array of frames rather than composed closures.
export function create(options = {}) {
  const evidence = options.evidence ?? "map";
  const tail = options.tail ?? true;
  const shortcut = options.shortcut ?? true;
  const bubble = evidence === "none";
  const linked = evidence === "linked";

  // w is the current evidence vector, y is the current yield or null.
  // A yield is {l: label, m: marker, v: value, k: resumption}.
  const s = { w: linked ? null : {}, y: null };

  function lookup(label) {
    if (linked) {
      for (let e = s.w; e !== null; e = e.w) if (e.l === label) return e;
      return undefined;
    }
    return s.w[label];
  }

  function install(w, ev) {
    if (linked) return ev;
    const next = { ...w };
    next[ev.l] = ev;
    return next;
  }

  // --- resumptions
  // Either an array of frames, innermost first, that is folded over when
  // resuming (short-cut resumptions, section 2.8) or a composed function.

  function identity(x) {
    return x;
  }

  function compose(frame, k) {
    return (x) => {
      const r = k(x);
      if (s.y !== null) {
        s.y.k = compose(frame, s.y.k);
        return;
      }
      return frame(r);
    };
  }

  function resume(k, x) {
    if (!shortcut) return k(x);
    const n = k.length;
    for (let i = 0; i < n; i++) {
      x = k[i](x);
      if (s.y !== null) {
        const rest = s.y.k;
        for (let j = i + 1; j < n; j++) rest.push(k[j]);
        return;
      }
    }
    return x;
  }

  /// Add a frame to the resumption of the current yield.
  function extend(frame) {
    const y = s.y;
    if (shortcut) y.k.push(frame);
    else y.k = compose(frame, y.k);
  }

  /// Replace the resumption built so far with a single frame.
  function wrap(frame) {
    s.y.k = shortcut ? [frame] : frame;
  }

  function start() {
    return shortcut ? [] : identity;
  }

  /// Bind without inlining, the continuation is always allocated.
  function bind(r, k) {
    if (s.y !== null) {
      extend(k);
      return;
    }
    return k(r);
  }

  // --- perform

  function perform(label, value) {
    if (bubble) {
      s.y = { l: label, m: null, v: value, k: start() };
      return;
    }
    const ev = lookup(label);
    if (ev === undefined) throw new Unhandled(label, value);
    return performWith(ev, value);
  }

  // With map evidence the lookup is compiled at the perform site, so the
  // property access is specialised by the engine for that site.
  function performWith(ev, value) {
    if (ev === undefined) throw new Unhandled("effect", value);
    const t = ev.t;
    if (t !== null) {
      const w = s.w;
      s.w = ev.w;
      const r = t(value);
      s.w = w;
      if (s.y !== null) {
        under(ev.l);
        return;
      }
      return r;
    }
    s.y = { l: ev.l, m: ev, v: value, k: start() };
  }

  // A yield leaving a clause that was evaluated in place.
  // On resumption the evidence for the label is found again in the evidence
  // vector current at that time, underk in section 4.2.
  function under(label) {
    const inner = s.y.k;
    wrap((x) => underResume(label, inner, x));
  }

  function underResume(label, inner, x) {
    const ev = lookup(label);
    const w = s.w;
    s.w = ev.w;
    const r = resume(inner, x);
    s.w = w;
    if (s.y !== null) {
      under(label);
      return;
    }
    return r;
  }

  // --- handle

  function tailClause(h) {
    if (!tail || bubble) return null;
    const t = h.t;
    return t === undefined ? null : t;
  }

  function handle(label, h, exec) {
    if (bubble) return promptLabel(label, h, exec(builtins.unit));
    const w = s.w;
    const ev = { l: label, h, t: tailClause(h), w, host: null };
    s.w = install(w, ev);
    return prompt(ev, exec(builtins.unit));
  }

  function prompt(ev, r) {
    s.w = ev.w;
    const y = s.y;
    if (y === null) return r;
    const inner = y.k;
    if (y.m !== ev) {
      wrap((x) => promptResume(ev.l, ev.h, ev.t, inner, x));
      return;
    }
    s.y = null;
    return clause(ev.h, y.v, (x) => promptResume(ev.l, ev.h, ev.t, inner, x));
  }

  // Resumptions are deep, the handler is installed again with a fresh marker.
  function promptResume(label, h, t, inner, x) {
    const w = s.w;
    const ev = { l: label, h, t, w, host: null };
    s.w = install(w, ev);
    return prompt(ev, resume(inner, x));
  }

  function promptLabel(label, h, r) {
    const y = s.y;
    if (y === null) return r;
    const inner = y.k;
    if (y.l !== label) {
      wrap((x) => promptLabel(label, h, resume(inner, x)));
      return;
    }
    s.y = null;
    return clause(h, y.v, (x) => promptLabel(label, h, resume(inner, x)));
  }

  function clause(h, value, k) {
    const c = h(value);
    if (s.y !== null) {
      extend((c) => c(k));
      return;
    }
    return c(k);
  }

  // A handler `(lift, resume) -> { resume(e) }`, where resume is used only
  // in that tail call, is tail resumptive. The compiler attaches `(lift) -> e`.
  function tailResumptive(f, t) {
    f.t = t;
    return f;
  }

  // --- effect aware builtins

  function list_fold(items, acc, f) {
    while (items.length !== 0) {
      const item = items[0];
      const rest = items[1];
      const g = f(item);
      if (s.y !== null) {
        extend((g) => list_fold_step(g, acc, rest, f));
        return;
      }
      acc = g(acc);
      if (s.y !== null) {
        extend((acc) => list_fold(rest, acc, f));
        return;
      }
      items = rest;
    }
    return acc;
  }

  function list_fold_step(g, acc, rest, f) {
    acc = g(acc);
    if (s.y !== null) {
      extend((acc) => list_fold(rest, acc, f));
      return;
    }
    return list_fold(rest, acc, f);
  }

  function binary_fold(bytes, acc, f) {
    return binary_fold_from(bytes, 0, acc, f);
  }

  function binary_fold_from(bytes, i, acc, f) {
    const n = bytes.length;
    for (; i < n; i++) {
      const next = i + 1;
      const g = f(bytes[i]);
      if (s.y !== null) {
        extend((g) => binary_fold_step(g, bytes, next, acc, f));
        return;
      }
      acc = g(acc);
      if (s.y !== null) {
        extend((acc) => binary_fold_from(bytes, next, acc, f));
        return;
      }
    }
    return acc;
  }

  function binary_fold_step(g, bytes, next, acc, f) {
    acc = g(acc);
    if (s.y !== null) {
      extend((acc) => binary_fold_from(bytes, next, acc, f));
      return;
    }
    return binary_fold_from(bytes, next, acc, f);
  }

  // As in the interpreter the builder is applied when fix is called and
  // again on every recursive call, which is observable if it has effects.
  function fix(builder) {
    const self = (x) => {
      const g = builder(self);
      if (s.y !== null) {
        extend((g) => g(x));
        return;
      }
      return g(x);
    };
    return builder(self);
  }

  // A pure builder is applied once.
  function fix_pure(builder) {
    let g = null;
    const self = (x) => g(x);
    g = builder(self);
    return g;
  }

  // --- running

  /// Run a compiled program with the effects of a platform.
  ///
  /// A platform maps effect labels to `{sync}` or `{async}` implementations.
  /// Sync implementations are tail resumptive clauses at the root of the
  /// evidence vector and never capture a continuation.
  /// Returns the value, or a promise of the value if an async effect is used.
  function run(main, platform = {}) {
    s.y = null;
    let root = linked ? null : {};
    for (const label of Object.keys(platform)) {
      const impl = platform[label];
      const t = tail && impl.sync ? impl.sync : null;
      root = install(root, { l: label, h: null, t, w: root, host: impl });
    }
    s.w = root;
    return drive(root, platform, main());
  }

  function drive(root, platform, r) {
    while (s.y !== null) {
      const y = s.y;
      s.y = null;
      s.w = root;
      const impl = bubble ? platform[y.l] : y.m.host;
      if (impl === undefined || impl === null) throw new Unhandled(y.l, y.v);
      if (impl.sync) {
        r = resume(y.k, impl.sync(y.v));
      } else {
        return impl.async(y.v).then((x) => {
          s.w = root;
          return drive(root, platform, resume(y.k, x));
        });
      }
    }
    return r;
  }

  return {
    s,
    perform,
    performWith,
    handle,
    extend,
    bind,
    tailResumptive,
    list_fold,
    binary_fold,
    fix,
    fix_pure,
    run,
    builtins,
    options: { evidence, tail, shortcut },
  };
}
