import { fileURLToPath as nativeFileURLToPath } from "node:url";
import { Result$Ok, Result$Error } from "../../gleam.mjs";
export function fileURLToPath(url) {
  try { return Result$Ok(nativeFileURLToPath(url)); }
  catch (error) { return Result$Error(String(error)); }
}
