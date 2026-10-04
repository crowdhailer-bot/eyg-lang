import { readSync as readSyncNative } from "node:fs";
import { readdir as nativeReaddir } from "node:fs/promises";
import { Result$Ok, Result$Error, toList, toBitArray } from "../../gleam.mjs";
export async function readdir(path) {
  try { return Result$Ok(toList(await nativeReaddir(path, { withFileTypes: true }))); }
  catch (error) { return Result$Error(String(error)); }
}
export const name = entry => entry.name;
export const isDirectory = entry => entry.isDirectory();
export function readSync(fd, length) {
  const buffer = Buffer.alloc(length);
  try {
    const read = readSyncNative(fd, buffer, 0, length, null);
    return Result$Ok(toBitArray([buffer.subarray(0, read)]));
  } catch (error) {
    return Result$Error(String(error.code ?? error));
  }
}
