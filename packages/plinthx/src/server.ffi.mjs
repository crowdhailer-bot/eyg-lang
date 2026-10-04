import { Result$Ok, Result$Error } from "./gleam.mjs";

export function serve(bun, options) {
  try { return Result$Ok(bun.serve({ hostname: options.hostname, port: options.port, fetch: options.fetch })); }
  catch (error) { return Result$Error(String(error)); }
}
export const port = server => server.port;
export async function stop(server, closeActiveConnections) {
  try { await server.stop(closeActiveConnections); return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
}
