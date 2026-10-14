import { readdir as nativeReaddir } from "node:fs/promises";
import { readSync as nativeReadSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Result$Ok, Result$Error, toList, toBitArray } from "../../gleam.mjs";
export function temporaryDirectory(prefix) {
  try { return Result$Ok(mkdtempSync(join(tmpdir(), prefix))); }
  catch (error) { return Result$Error(String(error)); }
}

export async function readdir(path) {
  try { return Result$Ok(toList(await nativeReaddir(path, { withFileTypes: true }))); }
  catch (error) { return Result$Error(String(error)); }
}

export const name = entry => entry.name;

export const isDirectory = entry => entry.isDirectory();

export function readSync(fd, length) {
  const buffer = Buffer.alloc(length);
  try {
    const read = nativeReadSync(fd, buffer, 0, length, null);
    return Result$Ok(toBitArray([buffer.subarray(0, read)]));
  } catch (error) {
    return Result$Error(String(error.code ?? error));
  }
}
