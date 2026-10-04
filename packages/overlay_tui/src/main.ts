#!/usr/bin/env bun
import { parse, Shell, Overlay } from "../build/dev/javascript/eyg_cli/eyg/cli/args.mjs";
import { toList } from "../build/dev/javascript/eyg_cli/gleam.mjs";

const args = process.argv.slice(2);
const command = parse(toList(args));
if ((command instanceof Shell || command instanceof Overlay) && process.stdin.isTTY && process.stdout.isTTY) {
  await import("@opentui/solid/preload");
  const { start } = await import("./ui/app");
  await start(args);
} else {
  // Identical parsing, handlers, exit statuses and stream behavior for every
  // existing command, including non-interactive shell input.
  const [{ start }, { run }] = await Promise.all([
    import("../build/dev/javascript/eyg_cli/eyg_cli.mjs"),
    import("../build/dev/javascript/loam/loam/system.mjs"),
  ]);
  await run(start(toList(args)));
}
