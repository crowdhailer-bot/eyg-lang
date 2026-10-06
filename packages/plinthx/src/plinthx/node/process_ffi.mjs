import nativeProcess from "node:process";
import { Result$Ok, Result$Error, toList } from "../../gleam.mjs";

export function get() {
  const process = globalThis.process;
  return process instanceof nativeProcess.constructor ? Result$Ok(process) : Result$Error(undefined);
}
export const stdin = process => process.stdin;
export const stdout = process => process.stdout;
export const isTTY = stream => typeof stream.isTTY === "boolean" ? Result$Ok(stream.isTTY) : Result$Error(undefined);
export const env = process => toList(Object.entries(process.env));
export function setRawMode(stream, mode) {
  try { stream.setRawMode(mode); return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
}
export function onSignal(process, signal, callback) {
  try { return Result$Ok(process.on(signal, callback)); }
  catch (error) { return Result$Error(String(error)); }
}
export function removeSignalListener(process, signal, callback) {
  try { return Result$Ok(process.removeListener(signal, callback)); }
  catch (error) { return Result$Error(String(error)); }
}
