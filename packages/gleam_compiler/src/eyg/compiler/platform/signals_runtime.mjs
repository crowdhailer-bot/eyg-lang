// Signals kept by the page, the types are in `platform/signals.gleam`.
//
// A signal is an integer handle to a string value. Derived signals take a
// function from the values of their inputs, the effect type requires the
// function to be pure so the page can call it at any time without a handler.
// Text bound to a signal is updated by the page without running the program.

import * as b from "../runtime/builtins.mjs";

const message = (reason) => String(reason && reason.message ? reason.message : reason);
const attempt = (f) => {
  try {
    return b.ok(f());
  } catch (reason) {
    return b.error(message(reason));
  }
};

/// Options:
/// - document
/// - pure(result) the value of a call to a compiled function, for the
///   generator runtime pass `rt.pure`.
export function host(options = {}) {
  const doc = options.document ?? globalThis.document;
  const pure = options.pure ?? ((x) => x);
  const cells = [];

  const cell = (id) => {
    const c = cells[id];
    if (c === undefined) throw new Error("unknown signal " + id);
    return c;
  };

  // Derived signals always have a larger id than their inputs, so recomputing
  // the reachable signals in order of id computes each one once.
  const propagate = (start) => {
    const reached = new Set();
    const stack = [start];
    while (stack.length) {
      const id = stack.pop();
      for (const d of cells[id].dependents) {
        if (!reached.has(d)) {
          reached.add(d);
          stack.push(d);
        }
      }
    }
    write(cells[start]);
    for (const id of Array.from(reached).sort((x, y) => x - y)) {
      const c = cells[id];
      const next = pure(c.compute(b.list(c.inputs.map((i) => cells[i].value))));
      if (next !== c.value) {
        c.value = next;
        write(c);
      }
    }
  };
  const write = (c) => {
    for (const node of c.bindings) node.textContent = c.value;
  };

  return {
    Signal: {
      sync: (initial) => {
        cells.push({ value: initial, dependents: [], inputs: null, compute: null, bindings: [] });
        return cells.length - 1;
      },
    },
    Get: { sync: (id) => attempt(() => cell(id).value) },
    Set: {
      sync: ({ signal, value }) =>
        attempt(() => {
          const c = cell(signal);
          if (c.compute !== null) throw new Error("can not set a derived signal");
          if (c.value !== value) {
            c.value = value;
            propagate(signal);
          }
          return b.unit;
        }),
    },
    Derive: {
      sync: ({ inputs, compute }) =>
        attempt(() => {
          const ids = b.array(inputs);
          ids.forEach(cell);
          const id = cells.length;
          const value = pure(compute(b.list(ids.map((i) => cells[i].value))));
          cells.push({ value, dependents: [], inputs: ids, compute, bindings: [] });
          for (const i of ids) cells[i].dependents.push(id);
          return id;
        }),
    },
    BindText: {
      sync: ({ selector, signal }) =>
        attempt(() => {
          const c = cell(signal);
          const nodes = doc.querySelectorAll(selector);
          if (nodes.length === 0) throw new Error("no match for " + selector);
          for (const node of nodes) {
            c.bindings.push(node);
            node.textContent = c.value;
          }
          return b.unit;
        }),
    },
  };
}
