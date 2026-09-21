import { createHash } from "node:crypto";
import { BitArray } from "../gleam.mjs";

export function sha256(bits) {
  const digest = createHash("sha256").update(bits.rawBuffer).digest();
  return new BitArray(new Uint8Array(digest));
}
