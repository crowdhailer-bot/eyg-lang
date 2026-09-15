/// A canonical string for a compiled value.
/// Records are printed with sorted keys and every function is `F`,
/// so two values are equal EYG values when their strings are equal.
export function canonical(value) {
  if (typeof value === "number") return "I" + value;
  if (typeof value === "string") return "S" + JSON.stringify(value);
  if (typeof value === "function") return "F";
  if (value instanceof Uint8Array) return "B" + Array.from(value).join(",");
  if (Array.isArray(value)) {
    const parts = [];
    while (value.length !== 0) {
      parts.push(canonical(value[0]));
      value = value[1];
    }
    return "L[" + parts.join(",") + "]";
  }
  if (value !== null && typeof value === "object") {
    if ("$T" in value) return "T" + value.$T + "(" + canonical(value.$V) + ")";
    const keys = Object.keys(value).sort();
    return "R{" + keys.map((k) => JSON.stringify(k) + ":" + canonical(value[k])).join(",") + "}";
  }
  return "?" + String(value);
}
