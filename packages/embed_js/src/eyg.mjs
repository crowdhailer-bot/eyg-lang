// EYG for JavaScript hosts. Bundled to dist/eyg.mjs, typed by eyg.d.ts.
import * as session from "./embed_js.mjs";
import { Some } from "../gleam_stdlib/gleam/option.mjs";

const option = (value) => (value instanceof Some ? value[0] : undefined);

/** Start a shell whose programs may perform `effects`, with packages from `hub`. */
export async function createShell({ effects, hub = "", modules = {} }) {
  const created = session.create(effects, hub);
  if (!created.isOk()) throw new globalThis.Error(created[0]);
  let current = created[0];
  for (const [name, code] of Object.entries(modules)) {
    const loaded = await session.with_module(current, name, code);
    if (!loaded.isOk()) throw new globalThis.Error(`module ${name}: ${loaded[0]}`);
    current = loaded[0];
  }
  return new Shell(current);
}

class Shell {
  #session;

  constructor(current) {
    this.#session = current;
  }

  /** A string field of a module, such as its readme. */
  text(module, field = "readme") {
    return session.text(this.#session, module, field);
  }

  /** Check and run code, answering effects synchronously. */
  run(code, handlers) {
    const handle = (label, input) => JSON.stringify(reply(handlers, label, JSON.parse(input)));
    return this.#finish(session.run(this.#session, code, handle));
  }

  /** Load any packages the code refers to, then check and run it. Handlers may return promises. */
  async runAsync(code, handlers) {
    const handle = async (label, input) =>
      JSON.stringify(await reply(handlers, label, JSON.parse(input)));
    return this.#finish(await session.run_async(this.#session, code, handle));
  }

  #finish(run) {
    this.#session = run.session;
    const json = option(run.json);
    return {
      value: json === undefined ? undefined : JSON.parse(json),
      display: option(run.display),
      error: option(run.error),
    };
  }
}

function reply(handlers, label, input) {
  const handler = handlers[label];
  if (!handler) throw new globalThis.Error(`no handler for ${label}`);
  const output = handler(input);
  if (output instanceof Promise) return output.then((value) => (value === undefined ? {} : value));
  return output === undefined ? {} : output;
}
