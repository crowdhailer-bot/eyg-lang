import { Result$Ok, Result$Error } from "./gleam.mjs";
export function get() {
  const queue = globalThis.queueMicrotask;
  return queue instanceof Function ? Result$Ok(queue) : Result$Error(undefined);
}
export function call(queue, callback) {
  try { queue(callback); return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
}
