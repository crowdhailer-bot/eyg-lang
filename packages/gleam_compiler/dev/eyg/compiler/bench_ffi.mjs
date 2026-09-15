import { Result$Ok, Result$Error, toList } from "../../gleam.mjs";
import * as evidence from "./runtime/evidence.mjs";
import * as generator from "./runtime/generator.mjs";
import { canonical } from "./runtime/inspect.mjs";

/// Arguments after the module name, `gleam run -m eyg/compiler/bench -- a b`.
export function args() {
  const index = process.argv.findIndex((arg) => arg.includes("gleam.main") || arg.endsWith(".mjs"));
  return toList(process.argv.slice(index + 1));
}

export function now() {
  return performance.now();
}

// Random is replaced by a constant so every backend computes the same value.
const platform = { Random: { sync: (max) => max - 1 } };

function runtime(kind, evidenceOption, tail, shortcut) {
  return kind === "generator"
    ? generator.create({ tail })
    : evidence.create({ evidence: evidenceOption, tail, shortcut });
}

/// A benchmark is a program that evaluates to a function of the size.
/// Run it `iterations` times, returning the canonical result and each time in ms.
export function time(code, kind, evidenceOption, tail, shortcut, size, iterations) {
  try {
    const rt = runtime(kind, evidenceOption, tail, shortcut);
    const main = new Function("return " + code)()(rt);
    const f = rt.run(main, platform);
    let value;
    const times = [];
    for (let i = 0; i < iterations; i++) {
      const start = performance.now();
      value = rt.run(() => f(size), platform);
      times.push(performance.now() - start);
    }
    return Result$Ok([canonical(value), toList(times)]);
  } catch (error) {
    return Result$Error(String(error && error.message ? error.message : error));
  }
}
