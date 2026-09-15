import { Result$Ok, Result$Error } from "../../gleam.mjs";
import { create } from "./runtime/evidence.mjs";

/// A canonical string for a compiled value, the same format as `support.canonical`.
export function canonical(value) {
  if (typeof value === "number") return "I" + value;
  if (typeof value === "string") return "S" + JSON.stringify(value);
  if (typeof value === "function") return "F";
  if (value instanceof Uint8Array) return "B" + Array.from(value).join(",");
  if (Array.isArray(value)) {
    const parts = [];
    while (value.length !== 0) {
      parts.push(canonical(value[0]));
      value = value[1];
    }
    return "L[" + parts.join(",") + "]";
  }
  if (value !== null && typeof value === "object") {
    if ("$T" in value) return "T" + value.$T + "(" + canonical(value.$V) + ")";
    const keys = Object.keys(value).sort();
    return "R{" + keys.map((k) => JSON.stringify(k) + ":" + canonical(value[k])).join(",") + "}";
  }
  return "?" + String(value);
}

/// Run compiled code, effects is a list of [label, canonical lift, js literal reply]
/// that must be performed in order.
export function run(code, evidence, tail, shortcut, effects) {
  try {
    const rt = create({ evidence, tail, shortcut });
    const main = new Function("return " + code)()(rt);
    const expected = effects.toArray().map((e) => [e[0], e[1], e[2]]);
    const platform = {};
    for (const [label] of expected) {
      platform[label] = {
        sync: (lift) => {
          const next = expected.shift();
          if (next === undefined || next[0] !== label) throw new Error("unexpected effect " + label);
          const got = canonical(lift);
          if (got !== next[1]) throw new Error("unexpected lift " + got + " expected " + next[1]);
          return new Function("return " + next[2])();
        },
      };
    }
    const value = rt.run(main, platform);
    if (expected.length !== 0) return Result$Error("effects not performed");
    return Result$Ok(canonical(value));
  } catch (error) {
    return Result$Error(String(error && error.message ? error.message : error));
  }
}
