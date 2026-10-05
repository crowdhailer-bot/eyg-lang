import fs from "node:fs";
import { Result$Ok, Result$Error, toBitArray } from "../../gleam.mjs";

export function readSync(fd, length) {
  const buffer = Buffer.alloc(length);
  try {
    const read = fs.readSync(fd, buffer, 0, length, null);
    return Result$Ok(toBitArray([buffer.subarray(0, read)]));
  } catch (error) {
    return Result$Error(String(error.code ?? error));
  }
}
