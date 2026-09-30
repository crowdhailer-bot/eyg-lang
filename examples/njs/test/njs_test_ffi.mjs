// Run a compiled handler the way handler.js does, with the effects answered here.
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export async function handle(source, method, path) {
  const file = join(mkdtempSync(join(tmpdir(), "eyg-njs-")), "program.js");
  writeFileSync(file, source);
  const eyg = (await import(file)).default;
  const request = { method: { $T: method, $V: {} }, path, headers: ["host", ["accept", []]] };
  let logged = "";
  const response = await eyg.runAsync(eyg.program(request), {
    Log: (message) => ((logged = message), {}),
    Subrequest: async (path) => ({ status: 200, body: "from " + path }),
  });
  return [response.status, response.body, logged];
}
