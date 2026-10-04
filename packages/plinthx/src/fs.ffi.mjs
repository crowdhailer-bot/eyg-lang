import { readdir as nativeReaddir } from "node:fs/promises";
import { Result$Ok, Result$Error, toList } from "./gleam.mjs";
export async function readdir(path) {
  try { return Result$Ok(toList(await nativeReaddir(path, { withFileTypes: true }))); }
  catch (error) { return Result$Error(String(error)); }
}
export const name = entry => entry.name;
export const isDirectory = entry => entry.isDirectory();
