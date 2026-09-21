import { build } from 'esbuild';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

await mkdir('dist', { recursive: true });
const worker = await build({
  entryPoints: ['src/worker.mjs'],
  bundle: true,
  write: false,
  format: 'iife',
  platform: 'browser',
  minify: true,
});
const syntax = await readFile('../../guides/syntax.md', 'utf8');
const define = {
  __WORKER_SOURCE__: JSON.stringify(worker.outputFiles[0].text),
  __SYNTAX_GUIDE__: JSON.stringify(syntax),
};
await build({
  entryPoints: ['src/phantom.mjs'],
  outfile: 'dist/phantom.js',
  bundle: true,
  format: 'iife',
  platform: 'browser',
  define,
  loader: { '.css': 'text' },
  minify: true,
  legalComments: 'eof',
});
await build({
  entryPoints: ['src/api.mjs'],
  outfile: 'dist/eyg.js',
  bundle: true,
  format: 'esm',
  platform: 'browser',
  define,
  minify: true,
  legalComments: 'eof',
});
await writeFile('dist/syntax.md', syntax);
await writeFile('dist/browser-drive.md', await readFile('../../guides/browser_drive.md', 'utf8'));
const { systemPrompt } = await import('./dist/eyg.js');
await writeFile('dist/system-prompt.txt', systemPrompt());
console.log('Built dist/phantom.js (single injectable script) and dist/eyg.js (embedding API).');
