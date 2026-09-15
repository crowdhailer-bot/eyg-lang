import { Result$Ok, Result$Error } from "../../gleam.mjs";
import * as evidence from "./runtime/evidence.mjs";
import * as generator from "./runtime/generator.mjs";
import { canonical } from "./runtime/inspect.mjs";

/// Effects is a list of [label, canonical lift, js literal reply] that must
/// be performed in order.
function expecting(effects) {
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
  return { platform, expected };
}

function execute(code, rt, effects) {
  try {
    const main = new Function("return " + code)()(rt);
    const { platform, expected } = expecting(effects);
    const value = rt.run(main, platform);
    if (expected.length !== 0) return Result$Error("effects not performed");
    return Result$Ok(canonical(value));
  } catch (error) {
    return Result$Error(String(error && error.message ? error.message : error));
  }
}

export function run(code, evidenceOption, tail, shortcut, effects) {
  return execute(code, evidence.create({ evidence: evidenceOption, tail, shortcut }), effects);
}

export function run_generator(code, tail, effects) {
  return execute(code, generator.create({ tail }), effects);
}
