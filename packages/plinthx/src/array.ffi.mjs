import { Result$Ok, Result$Error } from "./gleam.mjs";

export function set(array, index, value) {
  try {
    array[index] = value;
    return Result$Ok(undefined);
  } catch (error) { return Result$Error(String(error)); }
}
