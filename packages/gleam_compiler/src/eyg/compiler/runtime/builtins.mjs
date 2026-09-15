// Pure builtins shared by every compiled backend.
//
// The behaviour follows the Gleam interpreter, `eyg/interpreter/builtin`,
// which is compiled with gleam_stdlib on JavaScript.
// Integer overflow is not checked, the interpreter raises Unrepresentable.

export const unit = Object.freeze({});
export const nil = Object.freeze([]);
export const True = Object.freeze({ $T: "True", $V: unit });
export const False = Object.freeze({ $T: "False", $V: unit });
const Lt = Object.freeze({ $T: "Lt", $V: unit });
const Eq = Object.freeze({ $T: "Eq", $V: unit });
const Gt = Object.freeze({ $T: "Gt", $V: unit });
const Nothing = Object.freeze({ $T: "Error", $V: unit });

export class Crash extends Error {}

export function crash(reason) {
  throw new Crash(reason);
}

export function bool(b) {
  return b ? True : False;
}

export function ok(value) {
  return { $T: "Ok", $V: value };
}

export function error(reason) {
  return { $T: "Error", $V: reason };
}

export function list(array) {
  let out = nil;
  for (let i = array.length - 1; i >= 0; i--) out = [array[i], out];
  return out;
}

export function array(list) {
  const out = [];
  while (list.length !== 0) {
    out.push(list[0]);
    list = list[1];
  }
  return out;
}

function isEqual(a, b) {
  if (a === b) return true;
  if (typeof a !== "object" || typeof b !== "object" || a === null || b === null)
    return false;
  if (a instanceof Uint8Array) {
    if (!(b instanceof Uint8Array) || a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
    return true;
  }
  if (Array.isArray(a)) {
    // lists are nested pairs, compare iteratively to avoid deep recursion
    while (true) {
      if (!Array.isArray(b) || a.length !== b.length) return false;
      if (a.length === 0) return true;
      if (!isEqual(a[0], b[0])) return false;
      a = a[1];
      b = b[1];
    }
  }
  const keys = Object.keys(a);
  if (keys.length !== Object.keys(b).length) return false;
  for (const key of keys) {
    if (!(key in b) || !isEqual(a[key], b[key])) return false;
  }
  return true;
}

export function equal(a, b) {
  return isEqual(a, b) ? True : False;
}

export function never(value) {
  throw new Crash("never");
}

function order(a, b) {
  return a < b ? Lt : a > b ? Gt : Eq;
}

export function int_compare(a, b) {
  return order(a, b);
}

export function int_add(a, b) {
  return a + b;
}

export function int_subtract(a, b) {
  return a - b;
}

export function int_multiply(a, b) {
  return a * b;
}

export function int_divide(a, b) {
  return b === 0 ? Nothing : ok(Math.trunc(a / b));
}

export function int_absolute(a) {
  return Math.abs(a);
}

export function int_parse(raw) {
  return /^[-+]?(\d+)$/.test(raw) ? ok(parseInt(raw)) : Nothing;
}

export function int_to_string(a) {
  return a.toString();
}

let segmenter;

function graphemes(s) {
  segmenter ||= new Intl.Segmenter();
  return Array.from(segmenter.segment(s), (item) => item.segment);
}

export function string_append(a, b) {
  return a + b;
}

export function string_split(s, pattern) {
  const parts = pattern === "" ? graphemes(s) : s.split(pattern);
  if (parts.length === 0) crash("string_split");
  return { head: parts[0], tail: list(parts.slice(1)) };
}

export function string_split_once(s, pattern) {
  const index = s.indexOf(pattern);
  if (index < 0) return Nothing;
  return ok({ pre: s.slice(0, index), post: s.slice(index + pattern.length) });
}

export function string_replace(s, from, to) {
  if (from === "") {
    if (s === "") return to;
    return to + graphemes(s).join(to) + to;
  }
  return s.replaceAll(from, to);
}

export function string_uppercase(s) {
  return s.toUpperCase();
}

export function string_lowercase(s) {
  return s.toLowerCase();
}

export function string_starts_with(s, prefix) {
  return s.startsWith(prefix) ? True : False;
}

export function string_ends_with(s, suffix) {
  return s.endsWith(suffix) ? True : False;
}

export function string_length(s) {
  if (s === "") return 0;
  segmenter ||= new Intl.Segmenter();
  let n = 0;
  for (const _ of segmenter.segment(s)) n++;
  return n;
}

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });

export function string_to_binary(s) {
  return encoder.encode(s);
}

export function string_from_binary(bytes) {
  try {
    return ok(decoder.decode(bytes));
  } catch {
    return Nothing;
  }
}

export function list_pop(items) {
  return items.length === 0 ? Nothing : ok({ head: items[0], tail: items[1] });
}

export function binary_from_integers(items) {
  const bytes = [];
  while (items.length !== 0) {
    bytes.push(items[0] & 255);
    items = items[1];
  }
  return new Uint8Array(bytes);
}

export function binary_size(bytes) {
  return bytes.length;
}

export function binary_concat(a, b) {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

export function binary_compare(a, b) {
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) {
    if (a[i] !== b[i]) return a[i] < b[i] ? Lt : Gt;
  }
  return order(a.length, b.length);
}
