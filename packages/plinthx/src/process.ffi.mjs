import nativeProcess from "node:process";
import { Result$Ok, Result$Error, toList } from "./gleam.mjs";

export function get() {
  const process = globalThis.process;
  return process instanceof nativeProcess.constructor ? Result$Ok(process) : Result$Error(undefined);
}
export const argv = process => process.argv;
export const stdin = process => process.stdin;
export const stdout = process => process.stdout;
export const isTTY = stream => typeof stream.isTTY === "boolean" ? Result$Ok(stream.isTTY) : Result$Error(undefined);
export const execPath = process => process.execPath;
export const env = process => toList(Object.entries(process.env));
export const exit = (process, code) => process.exit(code);
export function cwd(process) {
  try { return Result$Ok(process.cwd()); }
  catch (error) { return Result$Error(String(error)); }
}
export function send(process, message) {
  try { process.send(message); return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
}
export function onMessage(process, callback) {
  try { return Result$Ok(process.on("message", callback)); }
  catch (error) { return Result$Error(String(error)); }
}
export function onDisconnect(process, callback) {
  try { return Result$Ok(process.on("disconnect", callback)); }
  catch (error) { return Result$Error(String(error)); }
}
export function onceExit(process, callback) {
  try { return Result$Ok(process.once("exit", callback)); }
  catch (error) { return Result$Error(String(error)); }
}
export function removeExitListener(process, callback) {
  try { return Result$Ok(process.removeListener("exit", callback)); }
  catch (error) { return Result$Error(String(error)); }
}
