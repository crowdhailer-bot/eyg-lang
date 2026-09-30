// The njs entry point. The compiled EYG program is in program.js, this answers
// the two effects it may perform.
import eyg from "program.js";

async function handle(r) {
  const request = {
    method: { $T: r.method, $V: {} },
    path: r.uri,
    headers: Object.keys(r.headersIn).reduceRight((tail, name) => [name, tail], []),
  };
  const response = await eyg.runAsync(eyg.program(request), {
    Log: (message) => {
      r.log(message);
      return {};
    },
    Subrequest: async (path) => {
      const reply = await r.subrequest(path);
      return { status: reply.status, body: reply.responseText };
    },
  });
  r.return(response.status, response.body);
}

export default { handle };
