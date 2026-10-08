import { Ok, Error, toList } from "./gleam.mjs";

export function object(entries) {
  return Object.fromEntries(entries.toArray());
}

export function array(items) {
  return items.toArray();
}

export function identity(x) {
  return x;
}

export function nil() {
  return null;
}

export function is_nullish(x) {
  return x === null || x === undefined;
}

export function is_safe_integer(x) {
  return Number.isSafeInteger(x);
}

// Host handlers are JavaScript functions, a thrown error or rejection becomes an Error.
export async function call_host(handler, input, raw) {
  try {
    return new Ok(await handler(input, raw));
  } catch (error) {
    return new Error(error instanceof globalThis.Error ? error.message : String(error));
  }
}

export function list_from_array(items) {
  return toList(items);
}
