import * as system from "../build/dev/javascript/loam/loam/system.mjs";
import { Ok } from "../build/dev/javascript/loam/gleam.mjs";
import { to_uri } from "../build/dev/javascript/gleam_http/gleam/http/request.mjs";
import { to_string } from "../build/dev/javascript/gleam_stdlib/gleam/uri.mjs";
import { stripVTControlCharacters } from "node:util";

export interface DriverIO {
  output(text: string, error: boolean): void;
  prompt(text: string): Promise<string>;
  fetch(url: string): void;
}

/** Run one host effect at a time. The existing Loam driver remains the source
 * of truth for IO; only terminal ownership is replaced by the frontend.
 * Gleam effects use positional fields, with their continuation last.
 * Keeping this boundary here avoids teaching the UI about EYG effect semantics.
 */
export async function drive<T>(initial: system.Effect$<T>, io: DriverIO): Promise<T> {
  let effect: system.Effect$<T> = initial;
  while (!(effect instanceof system.Done)) {
    if (effect instanceof system.Exit) throw new Error(`Program exited with status ${effect[0]}`);
    const fields = Object.values(effect);
    const resume = fields.pop() as (value: unknown) => system.Effect$<T>;
    let value: unknown;
    if (effect instanceof system.Stdout || effect instanceof system.WriteStdout || effect instanceof system.WriteStderr) {
      io.output(stripVTControlCharacters(effect[0]) + (effect instanceof system.Stdout ? "\n" : ""), effect instanceof system.WriteStderr);
    } else if (effect instanceof system.Prompt || effect instanceof system.Stdin) {
      const prompt = effect instanceof system.Prompt ? stripVTControlCharacters(effect[0]).split("\r").at(-1)! : "Standard input";
      value = new Ok(await io.prompt(prompt));
    } else {
      if (effect instanceof system.Fetch || effect instanceof system.FetchStream) {
        const uri = to_uri(effect[0]);
        // Credentials and query strings must not enter terminal history.
        const url = new URL(to_string(uri));
        io.fetch(url.origin + url.pathname);
      }
      const Effect = effect.constructor as new (...fields: unknown[]) => system.Effect$<unknown>;
      value = await system.run(new Effect(...fields, (result: unknown) => new system.Done(result)));
    }
    effect = resume(value);
  }
  return effect[0];
}
