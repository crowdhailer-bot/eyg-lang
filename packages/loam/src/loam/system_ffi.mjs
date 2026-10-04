import fs from "node:fs";
import { Result$Ok, Result$Error } from "../gleam.mjs";

// Bytes read from stdin but not yet returned by readLine.
// Shared with readStdin so that no input is lost when both are used.
let pending = Buffer.alloc(0);

export function readStdin() {
  try {
    const rest = fs.readFileSync(0);
    const all = Buffer.concat([pending, rest]);
    pending = Buffer.alloc(0);
    return Result$Ok(all.toString("utf8"));
  } catch (error) {
    return Result$Error(`failed to read stdin: ${error.message}`);
  }
}

// Write the prompt then read a single line from stdin, without the line ending.
// Several lines piped at once are returned one per call.
// Returns an error at the end of input.
export function readLine(prompt) {
  process.stdout.write(prompt);
  const chunk = Buffer.alloc(4096);
  while (true) {
    const newline = pending.indexOf(10);
    if (newline !== -1) {
      const line = pending.subarray(0, newline).toString("utf8");
      pending = pending.subarray(newline + 1);
      return Result$Ok(line.replace(/\r$/, ""));
    }
    let bytesRead;
    try {
      bytesRead = fs.readSync(0, chunk, 0, chunk.length, null);
    } catch (error) {
      if (error.code === "EAGAIN") continue;
      if (error.code === "EOF") bytesRead = 0;
      else return Result$Error(undefined);
    }
    if (bytesRead === 0) {
      if (pending.length === 0) return Result$Error(undefined);
      const line = pending.toString("utf8");
      pending = Buffer.alloc(0);
      return Result$Ok(line);
    }
    pending = Buffer.concat([pending, chunk.subarray(0, bytesRead)]);
  }
}
