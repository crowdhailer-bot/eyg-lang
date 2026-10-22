import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function getResponse() {
  const constructor = globalThis.Response;
  return typeof constructor === "function" ? Result$Ok(constructor) : Result$Error(undefined);
}
export function newResponse(constructor, body, status, headers) {
  try { return Result$Ok(new constructor(body, { status, headers: Array.from(headers) })); }
  catch (error) { return Result$Error(String(error)); }
}
