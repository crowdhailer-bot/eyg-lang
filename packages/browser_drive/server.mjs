import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const types = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css',
  '.mjs': 'text/javascript',
  '.js': 'text/javascript',
  '.md': 'text/plain; charset=utf-8',
  '.json': 'application/json',
  '.png': 'image/png',
  '.webm': 'video/webm',
  '.mp4': 'video/mp4',
  '.svg': 'image/svg+xml',
};
export function serve(port = 4173) {
  const server = createServer(async (request, response) => {
    try {
      let path = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      if (path === '/') path = '/demo/index.html';
      if (!/^\/(demo|dist|artifacts)\//.test(path)) {
        response.writeHead(404).end('Not found');
        return;
      }
      const file = resolve(root, '.' + path);
      const allowed = ['demo', 'dist', 'artifacts'].some((directory) =>
        file.startsWith(resolve(root, directory) + sep),
      );
      if (!allowed) throw new Error('Invalid path');
      const data = await readFile(file);
      response.writeHead(200, {
        'Content-Type': types[extname(file)] ?? 'application/octet-stream',
        'Cache-Control': 'no-store',
        'Access-Control-Allow-Origin': '*',
        'X-Content-Type-Options': 'nosniff',
      });
      response.end(data);
    } catch {
      response.writeHead(404).end('Not found');
    }
  });
  return new Promise((resolve) => server.listen(port, '127.0.0.1', () => resolve(server)));
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const server = await serve(Number(process.env.PORT ?? 4173));
  console.log('Phantom demos: http://127.0.0.1:' + server.address().port);
}
