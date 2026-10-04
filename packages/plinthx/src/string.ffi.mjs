import { Result$Ok, Result$Error } from "./gleam.mjs";

export function convert(value) {
  try { return Result$Ok(String(value)); }
  catch (error) {
    try { return Result$Error(String(error)); }
    catch { return Result$Error("String conversion failed"); }
  }
}
