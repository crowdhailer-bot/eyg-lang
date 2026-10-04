import { readdir } from "node:fs/promises";
import path from "node:path";

export type Completion = { label: string; detail: string; insert: string; from: number; to: number };

/** Complete at the cursor, preserving text after it. Only the requested
 * directory is read; typing never walks the entire repository. */
export async function complete(source: string, cursor: number, packages: string[], cwd: string): Promise<Completion[]> {
  const before = source.slice(0, cursor);
  const imported = /\bimport\s+"([^"\n]*)$/.exec(before);
  if (imported) {
    const prefix = imported[1]!;
    const slash = prefix.lastIndexOf("/");
    const directory = prefix.slice(0, slash + 1);
    const partial = prefix.slice(slash + 1);
    try {
      const entries = await readdir(path.resolve(cwd, directory || "."), { withFileTypes: true });
      return entries.filter(entry => entry.name.startsWith(partial)
        && (!entry.name.startsWith(".") || partial.startsWith("."))
        && (partial !== "" || (entry.name !== "node_modules" && entry.name !== "build")))
        .sort((a, b) => Number(b.isDirectory()) - Number(a.isDirectory()) || a.name.localeCompare(b.name))
        .slice(0, 30).map(entry => {
          const label = directory + entry.name + (entry.isDirectory() ? "/" : "");
          return { label, detail: entry.isDirectory() ? "directory" : "file", insert: label, from: cursor - prefix.length, to: cursor };
        });
    } catch { return []; }
  }
  const named = /@([a-zA-Z0-9_-]*)$/.exec(before);
  if (named) return packages.filter(name => name.startsWith(named[1]!)).slice(0, 30)
    .map(name => ({ label: "@" + name, detail: "hub package", insert: "@" + name, from: cursor - named[0].length, to: cursor }));
  return [];
}
