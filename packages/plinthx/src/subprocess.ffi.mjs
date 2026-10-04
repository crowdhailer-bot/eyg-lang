import { Result$Ok, Result$Error } from "./gleam.mjs";

export function spawn(bun, command, options) {
  try {
    return Result$Ok(bun.spawn([...command], {
      cwd: options.cwd, env: Object.fromEntries(options.env),
      stdin: options.stdin, stdout: options.stdout, stderr: options.stderr,
      serialization: options.serialization, ipc: options.ipc,
    }));
  } catch (error) { return Result$Error(String(error)); }
}
export function send(process, message) {
  try { process.send(message); return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
}
export function kill(process, signal) {
  try { process.kill(signal); return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
}
export function exited(process) {
  return process.exited.then(Result$Ok, error => Result$Error(String(error)));
}
export function stderr(process) {
  const stream = process.stderr;
  return stream instanceof globalThis.ReadableStream ? Result$Ok(stream) : Result$Error(undefined);
}
export async function readableStreamToText(bun, stream) {
  try { return Result$Ok(await bun.readableStreamToText(stream)); }
  catch (error) { return Result$Error(String(error)); }
}
