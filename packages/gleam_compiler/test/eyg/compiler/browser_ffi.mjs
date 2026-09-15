import { decodeJson } from "./platform/browser_runtime.mjs";
import { canonical } from "./runtime/inspect.mjs";

export function decode_json(bits) {
  return canonical(decodeJson(bits.rawBuffer));
}
