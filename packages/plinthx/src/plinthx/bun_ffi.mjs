import { Result$Ok, Result$Error } from "../gleam.mjs";

export const stringWidth = (bun, text) => bun.stringWidth(text);

export function get() {
  const bun = globalThis.Bun;
  return bun && typeof bun.spawn === "function" && typeof bun.version === "string"
    ? Result$Ok(bun) : Result$Error(undefined);
}
