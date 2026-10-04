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
  if (process.stdin.isTTY && pending.length === 0) return editLine();
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

// Lines entered at a terminal, most recent last, browsed with the up and down keys.
const history = [];

// Read a line from a terminal with editing: left and right, home and end,
// backspace and delete, up and down through history.
// Ctrl-C or Ctrl-D on an empty line ends input.
function editLine() {
  let chars = [];
  let cursor = 0;
  let browsing = history.length;
  const redraw = () => {
    const back = chars.length - cursor;
    process.stdout.write(
      "\x1b8" + chars.join("") + "\x1b[0K" + (back > 0 ? `\x1b[${back}D` : ""),
    );
  };
  const finish = (result) => {
    process.stdin.setRawMode(false);
    process.stdout.write("\n");
    return result;
  };
  // Save the cursor so the line can be redrawn after the prompt.
  process.stdout.write("\x1b7");
  process.stdin.setRawMode(true);
  const buffer = Buffer.alloc(1024);
  while (true) {
    let bytesRead;
    try {
      bytesRead = fs.readSync(0, buffer, 0, buffer.length, null);
    } catch (error) {
      if (error.code === "EAGAIN") continue;
      return finish(Result$Error(undefined));
    }
    if (bytesRead === 0) return finish(Result$Error(undefined));
    const input = buffer.subarray(0, bytesRead).toString("utf8");
    let i = 0;
    while (i < input.length) {
      const rest = input.slice(i);
      const key = rest[0];
      if (key === "\r" || key === "\n") {
        const line = chars.join("");
        cursor = chars.length;
        redraw();
        if (line !== "") history.push(line);
        // Anything typed after the newline is kept for the next read.
        pending = Buffer.from(input.slice(i + 1).replace(/\r/g, "\n"), "utf8");
        return finish(Result$Ok(line));
      } else if (key === "\x03" || (key === "\x04" && chars.length === 0)) {
        return finish(Result$Error(undefined));
      } else if (key === "\x7f" || key === "\x08") {
        if (cursor > 0) {
          chars.splice(cursor - 1, 1);
          cursor -= 1;
        }
        i += 1;
      } else if (key === "\x01") {
        cursor = 0;
        i += 1;
      } else if (key === "\x05") {
        cursor = chars.length;
        i += 1;
      } else if (key === "\x15") {
        chars = [];
        cursor = 0;
        i += 1;
      } else if (key === "\x1b") {
        const match = rest.match(/^\x1b(?:\[(\d*)|O)([A-Za-z~])/);
        const sequence = match ? (match[1] ?? "") + match[2] : "";
        if (sequence === "D" && cursor > 0) cursor -= 1;
        if (sequence === "C" && cursor < chars.length) cursor += 1;
        if (sequence === "H" || sequence === "1~") cursor = 0;
        if (sequence === "F" || sequence === "4~") cursor = chars.length;
        if (sequence === "3~" && cursor < chars.length) chars.splice(cursor, 1);
        if ((sequence === "A" || sequence === "B") && history.length > 0) {
          browsing = sequence === "A"
            ? Math.max(0, browsing - 1)
            : Math.min(history.length, browsing + 1);
          chars = Array.from(history[browsing] ?? "");
          cursor = chars.length;
        }
        i += match ? match[0].length : 1;
      } else {
        const char = Array.from(rest)[0];
        if (char >= " ") {
          chars.splice(cursor, 0, char);
          cursor += 1;
        }
        i += char.length;
      }
    }
    redraw();
  }
}
