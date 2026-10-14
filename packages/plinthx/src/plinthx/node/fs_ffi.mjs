import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Result$Ok, Result$Error } from "../../gleam.mjs";
export function temporaryDirectory(prefix) {
  try { return Result$Ok(mkdtempSync(join(tmpdir(), prefix))); }
  catch (error) { return Result$Error(String(error)); }
}
