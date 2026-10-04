import { getTreeSitterClient } from "@opentui/core";
import { Result$Ok, Result$Error } from "./gleam.mjs";
export function get() {
  try { return Result$Ok(getTreeSitterClient()); }
  catch (error) { return Result$Error(String(error)); }
}
export async function initialize(client) {
  try { await client.initialize(); return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
}
export async function preloadParser(client, filetype) {
  try { return Result$Ok(await client.preloadParser(filetype)); }
  catch (error) { return Result$Error(String(error)); }
}
export async function getPerformance(client) {
  try { return Result$Ok(await client.getPerformance()); }
  catch (error) { return Result$Error(String(error)); }
}
