import { Result$Ok, Result$Error } from "./gleam.mjs";

export async function text(request) {
  try { return Result$Ok(await request.text()); }
  catch (error) { return Result$Error(String(error)); }
}
export function newResponse(body, options) {
  try { return Result$Ok(new globalThis.Response(body, { status: options.status, headers: [...options.headers] })); }
  catch (error) { return Result$Error(String(error)); }
}
