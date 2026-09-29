import { BitArray } from "./gleam.mjs";

export async function digest(algorithm, bits) {
  const bytes = bits.rawBuffer.slice(bits.byteOffset ?? 0, (bits.byteOffset ?? 0) + bits.byteSize);
  const digest = await crypto.subtle.digest(algorithm, bytes);
  return new BitArray(new Uint8Array(digest));
}
