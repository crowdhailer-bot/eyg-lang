import { createHostClipboard } from "@opentui/core";
import { Result$Ok, Result$Error, toBitArray } from "./gleam.mjs";

export function create(options) {
  try { return Result$Ok(createHostClipboard(JSON.parse(options))); }
  catch (error) { return Result$Error(String(error)); }
}
export async function read(service, options) {
  try { return Result$Ok(await service.read(JSON.parse(options))); }
  catch (error) { return Result$Error(String(error)); }
}
export async function writeText(service, text) {
  try { return Result$Ok(await service.writeText(text)); }
  catch (error) { return Result$Error(String(error)); }
}
export async function dispose(service) {
  try { await service.dispose(); return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
}
export const status = result => result.status;
export const representation = result => result.representation == null
  ? Result$Error(undefined) : Result$Ok(result.representation);
export const mimeType = representation => representation.mimeType;
export const bytes = representation => toBitArray([representation.bytes]);
