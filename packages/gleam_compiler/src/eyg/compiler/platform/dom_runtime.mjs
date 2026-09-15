// Experimental DOM effects, several designs for the same capabilities.
// The effect types are in `platform/dom.gleam`, each design is a separate
// platform, a program uses one of them.
//
// Every EYG value can be serialised, so a DOM node can not be a value.
// The designs differ in how a program refers to a node:
// - handles: an integer that indexes a table kept by the page
// - selectors: a CSS selector resolved on every use
// - values: the program describes nodes, it never refers to live ones

import * as b from "../runtime/builtins.mjs";

const tag = (label, value = b.unit) => ({ $T: label, $V: value });
const message = (reason) => String(reason && reason.message ? reason.message : reason);
const attempt = (f) => {
  try {
    return b.ok(f());
  } catch (reason) {
    return b.error(message(reason));
  }
};

/// Integer handles for nodes, handed out once per node.
export class Handles {
  constructor() {
    this.nodes = new Map();
    this.ids = new WeakMap();
    this.next = 1;
  }
  id(node) {
    let id = this.ids.get(node);
    if (id === undefined) {
      id = this.next++;
      this.ids.set(node, id);
      this.nodes.set(id, node);
    }
    return id;
  }
  node(id) {
    const node = this.nodes.get(id);
    if (node === undefined) throw new Error("unknown node " + id);
    return node;
  }
  release(id) {
    const node = this.nodes.get(id);
    if (node !== undefined) {
      this.nodes.delete(id);
      this.ids.delete(node);
    }
  }
}

// A queue of events waiting for a program to ask for them.
class Events {
  constructor() {
    this.queue = [];
    this.waiting = [];
  }
  push(event) {
    const resolve = this.waiting.shift();
    if (resolve) resolve(event);
    else this.queue.push(event);
  }
  next() {
    if (this.queue.length) return Promise.resolve(this.queue.shift());
    return new Promise((resolve) => this.waiting.push(resolve));
  }
}

function attributes(element) {
  return b.list(Array.from(element.attributes, (a) => ({ key: a.name, value: a.value })));
}

// --- reading

/// Nodes are integer handles, every read is a separate effect.
export function handles(options = {}) {
  const doc = options.document ?? globalThis.document;
  const table = options.handles ?? new Handles();
  const events = new Events();
  return {
    Query: {
      sync: (selector) => attempt(() => b.list(Array.from(doc.querySelectorAll(selector), (n) => table.id(n)))),
    },
    ReadText: { sync: (id) => attempt(() => table.node(id).textContent) },
    ReadAttribute: {
      sync: ({ node, name }) =>
        attempt(() => {
          const value = table.node(node).getAttribute(name);
          return value === null ? tag("None") : tag("Some", value);
        }),
    },
    ReadValue: { sync: (id) => attempt(() => table.node(id).value ?? "") },
    Children: {
      sync: (id) => attempt(() => b.list(Array.from(table.node(id).childNodes, (n) => table.id(n)))),
    },
    Release: {
      sync: (id) => {
        table.release(id);
        return b.unit;
      },
    },
    Listen: {
      sync: ({ node, event }) =>
        attempt(() => {
          table.node(node).addEventListener(event, (e) =>
            events.push({ node, event, value: e.target && e.target.value !== undefined ? String(e.target.value) : "" }),
          );
          return b.unit;
        }),
    },
    NextEvent: { async: () => events.next() },
    // writing with handles, see elements
    ...imperativeWrites(doc, table),
  };
}

/// Nodes are CSS selectors, resolved again on every effect.
export function selectors(options = {}) {
  const doc = options.document ?? globalThis.document;
  const events = new Events();
  const one = (selector) => {
    const node = doc.querySelector(selector);
    if (node === null) throw new Error("no match for " + selector);
    return node;
  };
  return {
    ReadText: { sync: (selector) => attempt(() => one(selector).textContent) },
    ReadAll: {
      sync: (selector) => attempt(() => b.list(Array.from(doc.querySelectorAll(selector), (n) => n.textContent))),
    },
    ReadAttribute: {
      sync: ({ selector, name }) =>
        attempt(() => {
          const value = one(selector).getAttribute(name);
          return value === null ? tag("None") : tag("Some", value);
        }),
    },
    ReadValue: { sync: (selector) => attempt(() => one(selector).value ?? "") },
    WriteText: {
      sync: ({ selector, text }) =>
        attempt(() => {
          one(selector).textContent = text;
          return b.unit;
        }),
    },
    WriteAttribute: {
      sync: ({ selector, name, value }) =>
        attempt(() => {
          one(selector).setAttribute(name, value);
          return b.unit;
        }),
    },
    On: {
      sync: ({ selector, event }) =>
        attempt(() => {
          doc.addEventListener(event, (e) => {
            if (e.target instanceof doc.defaultView.Element && e.target.closest(selector)) {
              events.push({ selector, event, value: e.target.value !== undefined ? String(e.target.value) : "" });
            }
          });
          return b.unit;
        }),
    },
    NextEvent: { async: () => events.next() },
  };
}

/// A subtree is read as a value, a flat list of nodes with their depth.
/// The same shape as the tokens of DecodeJSON, EYG has no recursive types.
export function snapshot(options = {}) {
  const doc = options.document ?? globalThis.document;
  return {
    Snapshot: {
      sync: (selector) =>
        attempt(() => {
          const root = doc.querySelector(selector);
          if (root === null) throw new Error("no match for " + selector);
          const out = [];
          const walk = (node, depth) => {
            if (node.nodeType === 1) {
              out.push({ depth, node: tag("Element", { tag: node.localName, attributes: attributes(node) }) });
              for (const child of node.childNodes) walk(child, depth + 1);
            } else if (node.nodeType === 3) {
              out.push({ depth, node: tag("Text", node.data) });
            }
          };
          walk(root, 0);
          return b.list(out);
        }),
    },
  };
}

// --- writing

function imperativeWrites(doc, table) {
  return {
    CreateElement: { sync: (name) => attempt(() => table.id(doc.createElement(name))) },
    CreateText: { sync: (text) => table.id(doc.createTextNode(text)) },
    SetAttribute: {
      sync: ({ node, name, value }) =>
        attempt(() => {
          table.node(node).setAttribute(name, value);
          return b.unit;
        }),
    },
    SetText: {
      sync: ({ node, text }) =>
        attempt(() => {
          table.node(node).textContent = text;
          return b.unit;
        }),
    },
    Append: {
      sync: ({ parent, child }) =>
        attempt(() => {
          table.node(parent).appendChild(table.node(child));
          return b.unit;
        }),
    },
    Remove: {
      sync: (id) =>
        attempt(() => {
          table.node(id).remove();
          table.release(id);
          return b.unit;
        }),
    },
  };
}

/// One effect per DOM operation on integer handles.
export function imperative(options = {}) {
  return handles(options);
}

/// A list of operations applied in one effect.
/// Nodes created in the batch are referred to by `New(i)`, the index of the
/// create operation, and existing nodes by `Existing(handle)`.
/// Returns the handles of the created nodes in order.
export function patch(options = {}) {
  const doc = options.document ?? globalThis.document;
  const table = options.handles ?? new Handles();
  const base = handles({ document: doc, handles: table });
  return {
    Query: base.Query,
    Patch: {
      sync: (operations) =>
        attempt(() => {
          const created = [];
          const ref = (r) => (r.$T === "New" ? created[r.$V] : table.node(r.$V));
          while (operations.length !== 0) {
            const op = operations[0];
            operations = operations[1];
            const v = op.$V;
            switch (op.$T) {
              case "Create":
                created.push(doc.createElement(v));
                break;
              case "CreateText":
                created.push(doc.createTextNode(v));
                break;
              case "SetAttribute":
                ref(v.node).setAttribute(v.name, v.value);
                break;
              case "SetText":
                ref(v.node).textContent = v.text;
                break;
              case "Append":
                ref(v.parent).appendChild(ref(v.child));
                break;
              case "Remove":
                ref(v).remove();
                break;
              default:
                throw new Error("unknown operation " + op.$T);
            }
          }
          return b.list(created.map((node) => table.id(node)));
        }),
    },
  };
}

/// The program renders a description of the children of a node.
/// Existing nodes are updated in place when the tag, or `key` attribute,
/// matches at the same position.
export function render(options = {}) {
  const doc = options.document ?? globalThis.document;
  const events = new Events();
  const handlers = new WeakMap();
  const listen = (element, event, value) => {
    let map = handlers.get(element);
    if (!map) handlers.set(element, (map = {}));
    if (!(event in map)) {
      element.addEventListener(event, (e) => {
        const current = handlers.get(element)[event];
        if (current !== undefined) {
          events.push({ message: current, value: e.target && e.target.value !== undefined ? String(e.target.value) : "" });
        }
      });
    }
    map[event] = value;
  };
  const build = (entry) =>
    entry.node.$T === "Text" ? doc.createTextNode(entry.node.$V) : doc.createElement(entry.node.$V.tag);
  const sameKind = (dom, entry) => {
    if (entry.node.$T === "Text") return dom.nodeType === 3;
    if (dom.nodeType !== 1 || dom.localName !== entry.node.$V.tag) return false;
    return true;
  };
  const update = (dom, entry) => {
    if (entry.node.$T === "Text") {
      if (dom.data !== entry.node.$V) dom.data = entry.node.$V;
      return;
    }
    const seen = new Set();
    let attrs = entry.node.$V.attributes;
    while (attrs.length !== 0) {
      const { key, value } = attrs[0];
      attrs = attrs[1];
      if (key.startsWith("on:")) {
        listen(dom, key.slice(3), value);
        continue;
      }
      seen.add(key);
      if (dom.getAttribute(key) !== value) dom.setAttribute(key, value);
    }
    for (const name of Array.from(dom.attributes, (a) => a.name)) {
      if (!seen.has(name)) dom.removeAttribute(name);
    }
  };
  // entries is an array of {depth, node} for the children of parent, depth relative
  const reconcile = (parent, entries, start, depth) => {
    let i = start;
    let index = 0;
    while (i < entries.length && entries[i].depth === depth) {
      const entry = entries[i];
      let dom = parent.childNodes[index];
      if (dom === undefined || !sameKind(dom, entry)) {
        const fresh = build(entry);
        if (dom === undefined) parent.appendChild(fresh);
        else parent.replaceChild(fresh, dom);
        dom = fresh;
      }
      update(dom, entry);
      i = reconcile(dom, entries, i + 1, depth + 1);
      index++;
    }
    while (parent.childNodes.length > index) parent.lastChild.remove();
    return i;
  };
  return {
    Render: {
      sync: ({ selector, nodes }) =>
        attempt(() => {
          const root = doc.querySelector(selector);
          if (root === null) throw new Error("no match for " + selector);
          const entries = b.array(nodes);
          reconcile(root, entries, 0, 0);
          return b.unit;
        }),
    },
    NextEvent: { async: () => events.next() },
  };
}
