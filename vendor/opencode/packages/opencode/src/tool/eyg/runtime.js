// @bun
// build/dev/javascript/prelude.mjs
class CustomType {
  withFields(fields) {
    let properties = Object.keys(this).map((label) => (label in fields) ? fields[label] : this[label]);
    return new this.constructor(...properties);
  }
}

class List {
  static fromArray(array, tail) {
    return toList(array, tail);
  }
  [Symbol.iterator]() {
    return new ListIterator(this);
  }
  toArray() {
    return [...this];
  }
  atLeastLength(desired) {
    let current = this;
    while (desired-- > 0 && current)
      current = current.tail;
    return current !== undefined;
  }
  hasLength(desired) {
    let current = this;
    while (desired-- > 0 && current)
      current = current.tail;
    return desired === -1 && current instanceof Empty;
  }
  countLength() {
    let current = this;
    let length = 0;
    while (current) {
      current = current.tail;
      length++;
    }
    return length - 1;
  }
}
function prepend(element, tail) {
  return new NonEmpty(element, tail);
}
function toList(elements, tail) {
  let t = tail || List$Empty$const;
  for (let i = elements.length - 1;i >= 0; --i) {
    t = new NonEmpty(elements[i], t);
  }
  return t;
}

class ListIterator {
  #current;
  constructor(current) {
    this.#current = current;
  }
  next() {
    if (this.#current instanceof Empty) {
      return { done: true };
    } else {
      let { head, tail } = this.#current;
      this.#current = tail;
      return { value: head, done: false };
    }
  }
}

class Empty extends List {
}
var List$Empty$const = new Empty;
var List$Empty = () => List$Empty$const;
var List$isEmpty = (value) => value instanceof Empty;

class NonEmpty extends List {
  constructor(head, tail) {
    super();
    this.head = head;
    this.tail = tail;
  }
}
var List$NonEmpty = (head, tail) => new NonEmpty(head, tail);
var List$isNonEmpty = (value) => value instanceof NonEmpty;
class BitArray {
  bitSize;
  byteSize;
  bitOffset;
  rawBuffer;
  constructor(buffer, bitSize, bitOffset) {
    if (!(buffer instanceof Uint8Array)) {
      throw globalThis.Error("BitArray can only be constructed from a Uint8Array");
    }
    this.bitSize = bitSize ?? buffer.length * 8;
    this.byteSize = Math.trunc((this.bitSize + 7) / 8);
    this.bitOffset = bitOffset ?? 0;
    if (this.bitSize < 0) {
      throw globalThis.Error(`BitArray bit size is invalid: ${this.bitSize}`);
    }
    if (this.bitOffset < 0 || this.bitOffset > 7) {
      throw globalThis.Error(`BitArray bit offset is invalid: ${this.bitOffset}`);
    }
    if (buffer.length !== Math.trunc((this.bitOffset + this.bitSize + 7) / 8)) {
      throw globalThis.Error("BitArray buffer length is invalid");
    }
    this.rawBuffer = buffer;
  }
  byteAt(index) {
    if (index < 0 || index >= this.byteSize) {
      return;
    }
    return bitArrayByteAt(this.rawBuffer, this.bitOffset, index);
  }
  equals(other) {
    if (this.bitSize !== other.bitSize) {
      return false;
    }
    const wholeByteCount = Math.trunc(this.bitSize / 8);
    if (this.bitOffset === 0 && other.bitOffset === 0) {
      for (let i = 0;i < wholeByteCount; i++) {
        if (this.rawBuffer[i] !== other.rawBuffer[i]) {
          return false;
        }
      }
      const trailingBitsCount = this.bitSize % 8;
      if (trailingBitsCount) {
        const unusedLowBitCount = 8 - trailingBitsCount;
        if (this.rawBuffer[wholeByteCount] >> unusedLowBitCount !== other.rawBuffer[wholeByteCount] >> unusedLowBitCount) {
          return false;
        }
      }
    } else {
      for (let i = 0;i < wholeByteCount; i++) {
        const a = bitArrayByteAt(this.rawBuffer, this.bitOffset, i);
        const b = bitArrayByteAt(other.rawBuffer, other.bitOffset, i);
        if (a !== b) {
          return false;
        }
      }
      const trailingBitsCount = this.bitSize % 8;
      if (trailingBitsCount) {
        const a = bitArrayByteAt(this.rawBuffer, this.bitOffset, wholeByteCount);
        const b = bitArrayByteAt(other.rawBuffer, other.bitOffset, wholeByteCount);
        const unusedLowBitCount = 8 - trailingBitsCount;
        if (a >> unusedLowBitCount !== b >> unusedLowBitCount) {
          return false;
        }
      }
    }
    return true;
  }
  get buffer() {
    if (this.bitOffset !== 0 || this.bitSize % 8 !== 0) {
      throw new globalThis.Error("BitArray.buffer does not support unaligned bit arrays");
    }
    return this.rawBuffer;
  }
  get length() {
    if (this.bitOffset !== 0 || this.bitSize % 8 !== 0) {
      throw new globalThis.Error("BitArray.length does not support unaligned bit arrays");
    }
    return this.rawBuffer.length;
  }
}
var BitArray$BitArray = (buffer, bitSize, bitOffset) => new BitArray(buffer, bitSize, bitOffset);
var BitArray$BitArray$data = (bitArray) => {
  if (bitArray.bitSize % 8 !== 0)
    throw new globalThis.Error("BitArray$BitArray$data called on un-aligned bit array");
  const array = bitArray.rawBuffer;
  return new DataView(array.buffer, array.byteOffset, bitArray.byteSize);
};
function bitArrayByteAt(buffer, bitOffset, index) {
  if (bitOffset === 0) {
    return buffer[index] ?? 0;
  } else {
    const a = buffer[index] << bitOffset & 255;
    const b = buffer[index + 1] >> 8 - bitOffset;
    return a | b;
  }
}

class UtfCodepoint {
  constructor(value) {
    this.value = value;
  }
}
function bitArraySlice(bitArray, start, end) {
  end ??= bitArray.bitSize;
  bitArrayValidateRange(bitArray, start, end);
  if (start === end) {
    return new BitArray(new Uint8Array);
  }
  if (start === 0 && end === bitArray.bitSize) {
    return bitArray;
  }
  start += bitArray.bitOffset;
  end += bitArray.bitOffset;
  const startByteIndex = Math.trunc(start / 8);
  const endByteIndex = Math.trunc((end + 7) / 8);
  const byteLength = endByteIndex - startByteIndex;
  let buffer;
  if (startByteIndex === 0 && byteLength === bitArray.rawBuffer.byteLength) {
    buffer = bitArray.rawBuffer;
  } else {
    buffer = new Uint8Array(bitArray.rawBuffer.buffer, bitArray.rawBuffer.byteOffset + startByteIndex, byteLength);
  }
  return new BitArray(buffer, end - start, start % 8);
}
function bitArraySliceToInt(bitArray, start, end, isBigEndian, isSigned) {
  bitArrayValidateRange(bitArray, start, end);
  if (start === end) {
    return 0;
  }
  start += bitArray.bitOffset;
  end += bitArray.bitOffset;
  const isStartByteAligned = start % 8 === 0;
  const isEndByteAligned = end % 8 === 0;
  if (isStartByteAligned && isEndByteAligned) {
    return intFromAlignedSlice(bitArray, start / 8, end / 8, isBigEndian, isSigned);
  }
  const size = end - start;
  const startByteIndex = Math.trunc(start / 8);
  const endByteIndex = Math.trunc((end - 1) / 8);
  if (startByteIndex == endByteIndex) {
    const mask = 255 >> start % 8;
    const unusedLowBitCount = (8 - end % 8) % 8;
    let value = (bitArray.rawBuffer[startByteIndex] & mask) >> unusedLowBitCount;
    if (isSigned) {
      const highBit = 2 ** (size - 1);
      if (value >= highBit) {
        value -= highBit * 2;
      }
    }
    return value;
  }
  if (size <= 53) {
    return intFromUnalignedSliceUsingNumber(bitArray.rawBuffer, start, end, isBigEndian, isSigned);
  } else {
    return intFromUnalignedSliceUsingBigInt(bitArray.rawBuffer, start, end, isBigEndian, isSigned);
  }
}
function toBitArray(segments) {
  if (segments.length === 0) {
    return new BitArray(new Uint8Array);
  }
  if (segments.length === 1) {
    const segment = segments[0];
    if (segment instanceof BitArray) {
      return segment;
    }
    if (segment instanceof Uint8Array) {
      return new BitArray(segment);
    }
    return new BitArray(new Uint8Array(segments));
  }
  let bitSize = 0;
  let areAllSegmentsNumbers = true;
  for (const segment of segments) {
    if (segment instanceof BitArray) {
      bitSize += segment.bitSize;
      areAllSegmentsNumbers = false;
    } else if (segment instanceof Uint8Array) {
      bitSize += segment.byteLength * 8;
      areAllSegmentsNumbers = false;
    } else {
      bitSize += 8;
    }
  }
  if (areAllSegmentsNumbers) {
    return new BitArray(new Uint8Array(segments));
  }
  const buffer = new Uint8Array(Math.trunc((bitSize + 7) / 8));
  let cursor = 0;
  for (let segment of segments) {
    const isCursorByteAligned = cursor % 8 === 0;
    if (segment instanceof BitArray) {
      if (isCursorByteAligned && segment.bitOffset === 0) {
        buffer.set(segment.rawBuffer, cursor / 8);
        cursor += segment.bitSize;
        const trailingBitsCount = segment.bitSize % 8;
        if (trailingBitsCount !== 0) {
          const lastByteIndex = Math.trunc(cursor / 8);
          buffer[lastByteIndex] >>= 8 - trailingBitsCount;
          buffer[lastByteIndex] <<= 8 - trailingBitsCount;
        }
      } else {
        appendUnalignedBits(segment.rawBuffer, segment.bitSize, segment.bitOffset);
      }
    } else if (segment instanceof Uint8Array) {
      if (isCursorByteAligned) {
        buffer.set(segment, cursor / 8);
        cursor += segment.byteLength * 8;
      } else {
        appendUnalignedBits(segment, segment.byteLength * 8, 0);
      }
    } else {
      if (isCursorByteAligned) {
        buffer[cursor / 8] = segment;
        cursor += 8;
      } else {
        appendUnalignedBits(new Uint8Array([segment]), 8, 0);
      }
    }
  }
  function appendUnalignedBits(unalignedBits, size, offset) {
    if (size === 0) {
      return;
    }
    const byteSize = Math.trunc(size + 7 / 8);
    const highBitsCount = cursor % 8;
    const lowBitsCount = 8 - highBitsCount;
    let byteIndex = Math.trunc(cursor / 8);
    for (let i = 0;i < byteSize; i++) {
      let byte = bitArrayByteAt(unalignedBits, offset, i);
      if (size < 8) {
        byte >>= 8 - size;
        byte <<= 8 - size;
      }
      buffer[byteIndex] |= byte >> highBitsCount;
      let appendedBitsCount = size - Math.max(0, size - lowBitsCount);
      size -= appendedBitsCount;
      cursor += appendedBitsCount;
      if (size === 0) {
        break;
      }
      buffer[++byteIndex] = byte << lowBitsCount;
      appendedBitsCount = size - Math.max(0, size - highBitsCount);
      size -= appendedBitsCount;
      cursor += appendedBitsCount;
    }
  }
  return new BitArray(buffer, bitSize);
}
function sizedInt(value, size, isBigEndian) {
  if (size <= 0) {
    return new Uint8Array;
  }
  if (size === 8) {
    return new Uint8Array([value]);
  }
  if (size < 8) {
    value <<= 8 - size;
    return new BitArray(new Uint8Array([value]), size);
  }
  const buffer = new Uint8Array(Math.trunc((size + 7) / 8));
  const trailingBitsCount = size % 8;
  const unusedBitsCount = 8 - trailingBitsCount;
  if (size <= 32) {
    if (isBigEndian) {
      let i = buffer.length - 1;
      if (trailingBitsCount) {
        buffer[i--] = value << unusedBitsCount & 255;
        value >>= trailingBitsCount;
      }
      for (;i >= 0; i--) {
        buffer[i] = value;
        value >>= 8;
      }
    } else {
      let i = 0;
      const wholeByteCount = Math.trunc(size / 8);
      for (;i < wholeByteCount; i++) {
        buffer[i] = value;
        value >>= 8;
      }
      if (trailingBitsCount) {
        buffer[i] = value << unusedBitsCount;
      }
    }
  } else {
    const bigTrailingBitsCount = BigInt(trailingBitsCount);
    const bigUnusedBitsCount = BigInt(unusedBitsCount);
    let bigValue = BigInt(value);
    if (isBigEndian) {
      let i = buffer.length - 1;
      if (trailingBitsCount) {
        buffer[i--] = Number(bigValue << bigUnusedBitsCount);
        bigValue >>= bigTrailingBitsCount;
      }
      for (;i >= 0; i--) {
        buffer[i] = Number(bigValue);
        bigValue >>= 8n;
      }
    } else {
      let i = 0;
      const wholeByteCount = Math.trunc(size / 8);
      for (;i < wholeByteCount; i++) {
        buffer[i] = Number(bigValue);
        bigValue >>= 8n;
      }
      if (trailingBitsCount) {
        buffer[i] = Number(bigValue << bigUnusedBitsCount);
      }
    }
  }
  if (trailingBitsCount) {
    return new BitArray(buffer, size);
  }
  return buffer;
}
function intFromAlignedSlice(bitArray, start, end, isBigEndian, isSigned) {
  const byteSize = end - start;
  if (byteSize <= 6) {
    return intFromAlignedSliceUsingNumber(bitArray.rawBuffer, start, end, isBigEndian, isSigned);
  } else {
    return intFromAlignedSliceUsingBigInt(bitArray.rawBuffer, start, end, isBigEndian, isSigned);
  }
}
function intFromAlignedSliceUsingNumber(buffer, start, end, isBigEndian, isSigned) {
  const byteSize = end - start;
  let value = 0;
  if (isBigEndian) {
    for (let i = start;i < end; i++) {
      value *= 256;
      value += buffer[i];
    }
  } else {
    for (let i = end - 1;i >= start; i--) {
      value *= 256;
      value += buffer[i];
    }
  }
  if (isSigned) {
    const highBit = 2 ** (byteSize * 8 - 1);
    if (value >= highBit) {
      value -= highBit * 2;
    }
  }
  return value;
}
function intFromAlignedSliceUsingBigInt(buffer, start, end, isBigEndian, isSigned) {
  const byteSize = end - start;
  let value = 0n;
  if (isBigEndian) {
    for (let i = start;i < end; i++) {
      value *= 256n;
      value += BigInt(buffer[i]);
    }
  } else {
    for (let i = end - 1;i >= start; i--) {
      value *= 256n;
      value += BigInt(buffer[i]);
    }
  }
  if (isSigned) {
    const highBit = 1n << BigInt(byteSize * 8 - 1);
    if (value >= highBit) {
      value -= highBit * 2n;
    }
  }
  return Number(value);
}
function intFromUnalignedSliceUsingNumber(buffer, start, end, isBigEndian, isSigned) {
  const isStartByteAligned = start % 8 === 0;
  let size = end - start;
  let byteIndex = Math.trunc(start / 8);
  let value = 0;
  if (isBigEndian) {
    if (!isStartByteAligned) {
      const leadingBitsCount = 8 - start % 8;
      value = buffer[byteIndex++] & (1 << leadingBitsCount) - 1;
      size -= leadingBitsCount;
    }
    while (size >= 8) {
      value *= 256;
      value += buffer[byteIndex++];
      size -= 8;
    }
    if (size > 0) {
      value *= 2 ** size;
      value += buffer[byteIndex] >> 8 - size;
    }
  } else {
    if (isStartByteAligned) {
      let size2 = end - start;
      let scale = 1;
      while (size2 >= 8) {
        value += buffer[byteIndex++] * scale;
        scale *= 256;
        size2 -= 8;
      }
      value += (buffer[byteIndex] >> 8 - size2) * scale;
    } else {
      const highBitsCount = start % 8;
      const lowBitsCount = 8 - highBitsCount;
      let size2 = end - start;
      let scale = 1;
      while (size2 >= 8) {
        const byte = buffer[byteIndex] << highBitsCount | buffer[byteIndex + 1] >> lowBitsCount;
        value += (byte & 255) * scale;
        scale *= 256;
        size2 -= 8;
        byteIndex++;
      }
      if (size2 > 0) {
        const lowBitsUsed = size2 - Math.max(0, size2 - lowBitsCount);
        let trailingByte = (buffer[byteIndex] & (1 << lowBitsCount) - 1) >> lowBitsCount - lowBitsUsed;
        size2 -= lowBitsUsed;
        if (size2 > 0) {
          trailingByte *= 2 ** size2;
          trailingByte += buffer[byteIndex + 1] >> 8 - size2;
        }
        value += trailingByte * scale;
      }
    }
  }
  if (isSigned) {
    const highBit = 2 ** (end - start - 1);
    if (value >= highBit) {
      value -= highBit * 2;
    }
  }
  return value;
}
function intFromUnalignedSliceUsingBigInt(buffer, start, end, isBigEndian, isSigned) {
  const isStartByteAligned = start % 8 === 0;
  let size = end - start;
  let byteIndex = Math.trunc(start / 8);
  let value = 0n;
  if (isBigEndian) {
    if (!isStartByteAligned) {
      const leadingBitsCount = 8 - start % 8;
      value = BigInt(buffer[byteIndex++] & (1 << leadingBitsCount) - 1);
      size -= leadingBitsCount;
    }
    while (size >= 8) {
      value *= 256n;
      value += BigInt(buffer[byteIndex++]);
      size -= 8;
    }
    if (size > 0) {
      value <<= BigInt(size);
      value += BigInt(buffer[byteIndex] >> 8 - size);
    }
  } else {
    if (isStartByteAligned) {
      let size2 = end - start;
      let shift = 0n;
      while (size2 >= 8) {
        value += BigInt(buffer[byteIndex++]) << shift;
        shift += 8n;
        size2 -= 8;
      }
      value += BigInt(buffer[byteIndex] >> 8 - size2) << shift;
    } else {
      const highBitsCount = start % 8;
      const lowBitsCount = 8 - highBitsCount;
      let size2 = end - start;
      let shift = 0n;
      while (size2 >= 8) {
        const byte = buffer[byteIndex] << highBitsCount | buffer[byteIndex + 1] >> lowBitsCount;
        value += BigInt(byte & 255) << shift;
        shift += 8n;
        size2 -= 8;
        byteIndex++;
      }
      if (size2 > 0) {
        const lowBitsUsed = size2 - Math.max(0, size2 - lowBitsCount);
        let trailingByte = (buffer[byteIndex] & (1 << lowBitsCount) - 1) >> lowBitsCount - lowBitsUsed;
        size2 -= lowBitsUsed;
        if (size2 > 0) {
          trailingByte <<= size2;
          trailingByte += buffer[byteIndex + 1] >> 8 - size2;
        }
        value += BigInt(trailingByte) << shift;
      }
    }
  }
  if (isSigned) {
    const highBit = 2n ** BigInt(end - start - 1);
    if (value >= highBit) {
      value -= highBit * 2n;
    }
  }
  return Number(value);
}
function bitArrayValidateRange(bitArray, start, end) {
  if (start < 0 || start > bitArray.bitSize || end < start || end > bitArray.bitSize) {
    const msg = `Invalid bit array slice: start = ${start}, end = ${end}, ` + `bit size = ${bitArray.bitSize}`;
    throw new globalThis.Error(msg);
  }
}
var utf8Encoder;
function stringBits(string) {
  utf8Encoder ??= new TextEncoder;
  return utf8Encoder.encode(string);
}
function codepointBits(codepoint) {
  return stringBits(String.fromCodePoint(codepoint.value));
}
class Result extends CustomType {
  static isResult(data) {
    return data instanceof Result;
  }
}

class Ok extends Result {
  constructor(value) {
    super();
    this[0] = value;
  }
  isOk() {
    return true;
  }
}
var Result$Ok = (value) => new Ok(value);
var Result$isOk = (value) => value instanceof Ok;
class Error2 extends Result {
  constructor(detail) {
    super();
    this[0] = detail;
  }
  isOk() {
    return false;
  }
}
var Result$Error = (detail) => new Error2(detail);
var Result$isError = (value) => value instanceof Error2;
function isEqual(x, y) {
  let values = [x, y];
  while (values.length) {
    let a = values.pop();
    let b = values.pop();
    if (a === b)
      continue;
    if (!isObject(a) || !isObject(b))
      return false;
    let unequal = !structurallyCompatibleObjects(a, b) || unequalDates(a, b) || unequalBuffers(a, b) || unequalArrays(a, b) || unequalMaps(a, b) || unequalSets(a, b) || unequalRegExps(a, b);
    if (unequal)
      return false;
    const proto = Object.getPrototypeOf(a);
    if (proto !== null && typeof proto.equals === "function") {
      try {
        if (a.equals(b))
          continue;
        else
          return false;
      } catch {}
    }
    let [keys, get] = getters(a);
    const ka = keys(a);
    const kb = keys(b);
    if (ka.length !== kb.length)
      return false;
    for (let k of ka) {
      values.push(get(a, k), get(b, k));
    }
  }
  return true;
}
function getters(object) {
  if (object instanceof Map) {
    return [(x) => x.keys(), (x, y) => x.get(y)];
  } else {
    let extra = object instanceof globalThis.Error ? ["message"] : [];
    return [(x) => [...extra, ...Object.keys(x)], (x, y) => x[y]];
  }
}
function unequalDates(a, b) {
  return a instanceof Date && (a > b || a < b);
}
function unequalBuffers(a, b) {
  return !(a instanceof BitArray) && a.buffer instanceof ArrayBuffer && a.BYTES_PER_ELEMENT && !(a.byteLength === b.byteLength && a.every((n, i) => n === b[i]));
}
function unequalArrays(a, b) {
  return Array.isArray(a) && a.length !== b.length;
}
function unequalMaps(a, b) {
  return a instanceof Map && a.size !== b.size;
}
function unequalSets(a, b) {
  return a instanceof Set && (a.size != b.size || [...a].some((e) => !b.has(e)));
}
function unequalRegExps(a, b) {
  return a instanceof RegExp && (a.source !== b.source || a.flags !== b.flags);
}
function isObject(a) {
  return typeof a === "object" && a !== null;
}
function structurallyCompatibleObjects(a, b) {
  if (typeof a !== "object" && typeof b !== "object" && (!a || !b))
    return false;
  let nonstructural = [Promise, WeakSet, WeakMap, Function];
  if (nonstructural.some((c) => a instanceof c))
    return false;
  return a.constructor === b.constructor;
}
function remainderInt(a, b) {
  if (b === 0) {
    return 0;
  } else {
    return a % b;
  }
}
function divideInt(a, b) {
  return Math.trunc(divideFloat(a, b));
}
function divideFloat(a, b) {
  if (b === 0) {
    return 0;
  } else {
    return a / b;
  }
}
function makeError(variant, file, module, line, fn, message, extra) {
  let error = new globalThis.Error(message);
  error.gleam_error = variant;
  error.file = file;
  error.module = module;
  error.line = line;
  error.function = fn;
  error.fn = fn;
  for (let k in extra)
    error[k] = extra[k];
  return error;
}
// build/dev/javascript/gleam_stdlib/dict.mjs
var referenceMap = /* @__PURE__ */ new WeakMap;
var tempDataView = /* @__PURE__ */ new DataView(/* @__PURE__ */ new ArrayBuffer(8));
var referenceUID = 0;
function hashByReference(o) {
  const known = referenceMap.get(o);
  if (known !== undefined) {
    return known;
  }
  const hash = referenceUID++;
  if (referenceUID === 2147483647) {
    referenceUID = 0;
  }
  referenceMap.set(o, hash);
  return hash;
}
function hashMerge(a, b) {
  return a ^ b + 2654435769 + (a << 6) + (a >> 2) | 0;
}
function hashString(s) {
  let hash = 0;
  const len = s.length;
  for (let i = 0;i < len; i++) {
    hash = Math.imul(31, hash) + s.charCodeAt(i) | 0;
  }
  return hash;
}
function hashNumber(n) {
  tempDataView.setFloat64(0, n);
  const i = tempDataView.getInt32(0);
  const j = tempDataView.getInt32(4);
  return Math.imul(73244475, i >> 16 ^ i) ^ j;
}
function hashBigInt(n) {
  return hashString(n.toString());
}
function hashObject(o) {
  const proto = Object.getPrototypeOf(o);
  if (proto !== null && typeof proto.hashCode === "function") {
    try {
      const code = o.hashCode(o);
      if (typeof code === "number") {
        return code;
      }
    } catch {}
  }
  if (o instanceof Promise || o instanceof WeakSet || o instanceof WeakMap) {
    return hashByReference(o);
  }
  if (o instanceof Date) {
    return hashNumber(o.getTime());
  }
  let h = 0;
  if (o instanceof ArrayBuffer) {
    o = new Uint8Array(o);
  }
  if (Array.isArray(o) || o instanceof Uint8Array) {
    for (let i = 0;i < o.length; i++) {
      h = Math.imul(31, h) + getHash(o[i]) | 0;
    }
  } else if (o instanceof Set) {
    o.forEach((v) => {
      h = h + getHash(v) | 0;
    });
  } else if (o instanceof Map) {
    o.forEach((v, k) => {
      h = h + hashMerge(getHash(v), getHash(k)) | 0;
    });
  } else {
    const keys = Object.keys(o);
    for (let i = 0;i < keys.length; i++) {
      const k = keys[i];
      const v = o[k];
      h = h + hashMerge(getHash(v), hashString(k)) | 0;
    }
  }
  return h;
}
function getHash(u) {
  if (u === null)
    return 1108378658;
  if (u === undefined)
    return 1108378659;
  if (u === true)
    return 1108378657;
  if (u === false)
    return 1108378656;
  switch (typeof u) {
    case "number":
      return hashNumber(u);
    case "string":
      return hashString(u);
    case "bigint":
      return hashBigInt(u);
    case "object":
      return hashObject(u);
    case "symbol":
      return hashByReference(u);
    case "function":
      return hashByReference(u);
    default:
      return 0;
  }
}

class Dict {
  constructor(size, root) {
    this.size = size;
    this.root = root;
  }
}
var bits = 5;
var mask = (1 << bits) - 1;
var noElementMarker = Symbol();

class Node {
  constructor(generation, datamap, nodemap, data) {
    this.datamap = datamap;
    this.nodemap = nodemap;
    this.data = data;
    this.generation = generation;
  }
  equals(other) {
    if (this === other)
      return true;
    if (!(other instanceof Node))
      return false;
    if (this.datamap !== other.datamap || this.nodemap !== other.nodemap) {
      return false;
    }
    const leftData = this.data;
    const rightData = other.data;
    if (leftData.length !== rightData.length)
      return false;
    if (this.datamap === 0 && this.nodemap === 0) {
      return this.#equalsOverflowEntries(rightData);
    }
    const edgesStart = leftData.length - popcount(this.nodemap);
    for (let i = 0;i < edgesStart; i += 2) {
      if (!isEqual(leftData[i], rightData[i]) || !isEqual(leftData[i + 1], rightData[i + 1])) {
        return false;
      }
    }
    for (let i = edgesStart;i < leftData.length; ++i) {
      if (!leftData[i].equals(rightData[i]))
        return false;
    }
    return true;
  }
  #equalsOverflowEntries(otherData) {
    const data = this.data;
    entries:
      for (let i = 0;i < data.length; i += 2) {
        for (let j = 0;j < otherData.length; j += 2) {
          if (isEqual(data[i], otherData[j])) {
            if (!isEqual(data[i + 1], otherData[j + 1]))
              return false;
            continue entries;
          }
        }
        return false;
      }
    return true;
  }
  hashCode() {
    const data = this.data;
    const edgesStart = data.length - popcount(this.nodemap);
    let hash = 0;
    for (let i = 0;i < edgesStart; i += 2) {
      hash = hash + hashMerge(getHash(data[i + 1]), getHash(data[i])) | 0;
    }
    for (let i = edgesStart;i < data.length; ++i) {
      hash = hash + data[i].hashCode() | 0;
    }
    return hash;
  }
}
var emptyNode = /* @__PURE__ */ newNode(0);
var emptyDict = /* @__PURE__ */ new Dict(0, emptyNode);
var errorNil = /* @__PURE__ */ Result$Error(undefined);
function newNode(generation) {
  return new Node(generation, 0, 0, []);
}
function copyNode(node, generation) {
  if (node.generation === generation) {
    return node;
  }
  const newData = node.data.slice(0);
  return new Node(generation, node.datamap, node.nodemap, newData);
}
function copyAndSet(node, generation, idx, val) {
  if (node.data[idx] === val) {
    return node;
  }
  node = copyNode(node, generation);
  node.data[idx] = val;
  return node;
}
function copyAndInsertPair(node, generation, bit, idx, key, val) {
  const data = node.data;
  const length = data.length;
  const newData = new Array(length + 2);
  let readIndex = 0;
  let writeIndex = 0;
  while (readIndex < idx)
    newData[writeIndex++] = data[readIndex++];
  newData[writeIndex++] = key;
  newData[writeIndex++] = val;
  while (readIndex < length)
    newData[writeIndex++] = data[readIndex++];
  return new Node(generation, node.datamap | bit, node.nodemap, newData);
}
function copyAndRemovePair(node, generation, bit, idx) {
  node = copyNode(node, generation);
  const data = node.data;
  const length = data.length;
  for (let w = idx, r = idx + 2;r < length; ++r, ++w) {
    data[w] = data[r];
  }
  data.pop();
  data.pop();
  node.datamap ^= bit;
  return node;
}
function make() {
  return emptyDict;
}
function from(iterable) {
  let transient = toTransient(emptyDict);
  for (const [key, value] of iterable) {
    transient = destructiveTransientInsert(key, value, transient);
  }
  return fromTransient(transient);
}
function size(dict) {
  return dict.size;
}
function get(dict, key) {
  const result = lookup(dict.root, key, getHash(key));
  return result !== noElementMarker ? Result$Ok(result) : errorNil;
}
function lookup(node, key, hash) {
  for (let shift = 0;shift < 32; shift += bits) {
    const data = node.data;
    const bit = hashbit(hash, shift);
    if (node.nodemap & bit) {
      node = data[data.length - 1 - index(node.nodemap, bit)];
    } else if (node.datamap & bit) {
      const dataidx = Math.imul(index(node.datamap, bit), 2);
      return isEqual(key, data[dataidx]) ? data[dataidx + 1] : noElementMarker;
    } else {
      return noElementMarker;
    }
  }
  const overflow = node.data;
  for (let i = 0;i < overflow.length; i += 2) {
    if (isEqual(key, overflow[i])) {
      return overflow[i + 1];
    }
  }
  return noElementMarker;
}
function toTransient(dict) {
  return {
    generation: nextGeneration(dict),
    root: dict.root,
    size: dict.size,
    dict
  };
}
function fromTransient(transient) {
  if (transient.root === transient.dict.root) {
    return transient.dict;
  }
  return new Dict(transient.size, transient.root);
}
function nextGeneration(dict) {
  const root = dict.root;
  if (root.generation < Number.MAX_SAFE_INTEGER) {
    return root.generation + 1;
  }
  const queue = [root];
  while (queue.length) {
    const node = queue.pop();
    node.generation = 0;
    const nodeStart = node.data.length - popcount(node.nodemap);
    for (let i = nodeStart;i < node.data.length; ++i) {
      queue.push(node.data[i]);
    }
  }
  return 1;
}
var globalTransient = /* @__PURE__ */ toTransient(emptyDict);
function insert(dict, key, value) {
  globalTransient.generation = nextGeneration(dict);
  globalTransient.size = dict.size;
  const hash = getHash(key);
  const root = insertIntoNode(globalTransient, dict.root, key, value, hash, 0);
  if (root === dict.root) {
    return dict;
  }
  return new Dict(globalTransient.size, root);
}
function destructiveTransientInsert(key, value, transient) {
  const hash = getHash(key);
  transient.root = insertIntoNode(transient, transient.root, key, value, hash, 0);
  return transient;
}
function insertIntoNode(transient, node, key, value, hash, shift) {
  const data = node.data;
  const generation = transient.generation;
  if (shift > 32) {
    for (let i = 0;i < data.length; i += 2) {
      if (isEqual(key, data[i])) {
        return copyAndSet(node, generation, i + 1, value);
      }
    }
    transient.size += 1;
    return copyAndInsertPair(node, generation, 0, data.length, key, value);
  }
  const bit = hashbit(hash, shift);
  if (node.nodemap & bit) {
    const nodeidx2 = data.length - 1 - index(node.nodemap, bit);
    let child2 = data[nodeidx2];
    child2 = insertIntoNode(transient, child2, key, value, hash, shift + bits);
    return copyAndSet(node, generation, nodeidx2, child2);
  }
  const dataidx = Math.imul(index(node.datamap, bit), 2);
  if ((node.datamap & bit) === 0) {
    transient.size += 1;
    return copyAndInsertPair(node, generation, bit, dataidx, key, value);
  }
  if (isEqual(key, data[dataidx])) {
    return copyAndSet(node, generation, dataidx + 1, value);
  }
  const childShift = shift + bits;
  let child = emptyNode;
  child = insertIntoNode(transient, child, key, value, hash, childShift);
  const key2 = data[dataidx];
  const value2 = data[dataidx + 1];
  const hash2 = getHash(key2);
  child = insertIntoNode(transient, child, key2, value2, hash2, childShift);
  transient.size -= 1;
  const length = data.length;
  const nodeidx = length - 1 - index(node.nodemap, bit);
  const newData = new Array(length - 1);
  let readIndex = 0;
  let writeIndex = 0;
  while (readIndex < dataidx)
    newData[writeIndex++] = data[readIndex++];
  readIndex += 2;
  while (readIndex <= nodeidx)
    newData[writeIndex++] = data[readIndex++];
  newData[writeIndex++] = child;
  while (readIndex < length)
    newData[writeIndex++] = data[readIndex++];
  return new Node(generation, node.datamap ^ bit, node.nodemap | bit, newData);
}
function destructiveTransientDelete(key, transient) {
  const hash = getHash(key);
  transient.root = deleteFromNode(transient, transient.root, key, hash, 0);
  return transient;
}
function deleteFromNode(transient, node, key, hash, shift) {
  const data = node.data;
  const generation = transient.generation;
  if (shift > 32) {
    for (let i = 0;i < data.length; i += 2) {
      if (isEqual(key, data[i])) {
        transient.size -= 1;
        return copyAndRemovePair(node, generation, 0, i);
      }
    }
    return node;
  }
  const bit = hashbit(hash, shift);
  const dataidx = Math.imul(index(node.datamap, bit), 2);
  if ((node.nodemap & bit) !== 0) {
    const nodeidx = data.length - 1 - index(node.nodemap, bit);
    let child = data[nodeidx];
    child = deleteFromNode(transient, child, key, hash, shift + bits);
    if (child.nodemap !== 0 || child.data.length > 2) {
      return copyAndSet(node, generation, nodeidx, child);
    }
    const length = data.length;
    const newData = new Array(length + 1);
    let readIndex = 0;
    let writeIndex = 0;
    while (readIndex < dataidx)
      newData[writeIndex++] = data[readIndex++];
    newData[writeIndex++] = child.data[0];
    newData[writeIndex++] = child.data[1];
    while (readIndex < nodeidx)
      newData[writeIndex++] = data[readIndex++];
    readIndex++;
    while (readIndex < length)
      newData[writeIndex++] = data[readIndex++];
    return new Node(generation, node.datamap | bit, node.nodemap ^ bit, newData);
  }
  if ((node.datamap & bit) === 0 || !isEqual(key, data[dataidx])) {
    return node;
  }
  transient.size -= 1;
  return copyAndRemovePair(node, generation, bit, dataidx);
}
function map(dict, fun) {
  const generation = nextGeneration(dict);
  const root = copyNode(dict.root, generation);
  const queue = [root];
  while (queue.length) {
    const node = queue.pop();
    const data = node.data;
    const edgesStart = data.length - popcount(node.nodemap);
    for (let i = 0;i < edgesStart; i += 2) {
      data[i + 1] = fun(data[i], data[i + 1]);
    }
    for (let i = edgesStart;i < data.length; ++i) {
      data[i] = copyNode(data[i], generation);
      queue.push(data[i]);
    }
  }
  return new Dict(dict.size, root);
}
function fold(dict, state, fun) {
  const queue = [dict.root];
  while (queue.length) {
    const node = queue.pop();
    const data = node.data;
    const edgesStart = data.length - popcount(node.nodemap);
    for (let i = 0;i < edgesStart; i += 2) {
      state = fun(state, data[i], data[i + 1]);
    }
    for (let i = edgesStart;i < data.length; ++i) {
      queue.push(data[i]);
    }
  }
  return state;
}
function popcount(n) {
  n -= n >>> 1 & 1431655765;
  n = (n & 858993459) + (n >>> 2 & 858993459);
  return Math.imul(n + (n >>> 4) & 252645135, 16843009) >>> 24;
}
function index(bitmap, bit) {
  return popcount(bitmap & bit - 1);
}
function hashbit(hash, shift) {
  return 1 << (hash >>> shift & mask);
}

// build/dev/javascript/gleam_stdlib/gleam/option.mjs
class Some extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class None extends CustomType {
}
var Option$None$const = new None;
function from_result(result) {
  if (result instanceof Ok) {
    let a = result[0];
    return new Some(a);
  } else {
    return Option$None$const;
  }
}

// build/dev/javascript/gleam_stdlib/gleam/dict.mjs
function is_empty(dict) {
  return size(dict) === 0;
}
function to_list(dict) {
  return fold(dict, List$Empty$const, (acc, key, value) => {
    return prepend([key, value], acc);
  });
}
function from_list_loop(loop$transient, loop$list) {
  while (true) {
    let transient = loop$transient;
    let list = loop$list;
    if (list instanceof Empty) {
      return fromTransient(transient);
    } else {
      let rest = list.tail;
      let key = list.head[0];
      let value = list.head[1];
      loop$transient = destructiveTransientInsert(key, value, transient);
      loop$list = rest;
    }
  }
}
function from_list(list) {
  return from_list_loop(toTransient(make()), list);
}
function keys(dict) {
  return fold(dict, List$Empty$const, (acc, key, _) => {
    return prepend(key, acc);
  });
}
function delete$(dict, key) {
  let _pipe = toTransient(dict);
  let _pipe$1 = ((_capture) => {
    return destructiveTransientDelete(key, _capture);
  })(_pipe);
  return fromTransient(_pipe$1);
}

// build/dev/javascript/gleam_stdlib/gleam/order.mjs
class Lt extends CustomType {
}
var Order$Lt$const = new Lt;
class Eq extends CustomType {
}
var Order$Eq$const = new Eq;
class Gt extends CustomType {
}
var Order$Gt$const = new Gt;

// build/dev/javascript/gleam_stdlib/gleam/int.mjs
function absolute_value(x) {
  let $ = x >= 0;
  if ($) {
    return x;
  } else {
    return x * -1;
  }
}
function max(a, b) {
  let $ = a > b;
  if ($) {
    return a;
  } else {
    return b;
  }
}
function min(a, b) {
  let $ = a < b;
  if ($) {
    return a;
  } else {
    return b;
  }
}
function compare(a, b) {
  let $ = a === b;
  if ($) {
    return Order$Eq$const;
  } else {
    let $1 = a < b;
    if ($1) {
      return Order$Lt$const;
    } else {
      return Order$Gt$const;
    }
  }
}
function is_even(x) {
  return x % 2 === 0;
}
function random(max2) {
  let _pipe = random_uniform() * identity(max2);
  let _pipe$1 = floor(_pipe);
  return round(_pipe$1);
}

// build/dev/javascript/gleam_stdlib/gleam/string_tree.mjs
class All extends CustomType {
}
var Direction$All$const = new All;

// build/dev/javascript/gleam_stdlib/gleam/string.mjs
class Leading extends CustomType {
}
var Direction$Leading$const = new Leading;

class Trailing extends CustomType {
}
var Direction$Trailing$const = new Trailing;
function replace(string, pattern, substitute) {
  let _pipe = string;
  let _pipe$1 = identity(_pipe);
  let _pipe$2 = string_replace(_pipe$1, pattern, substitute);
  return identity(_pipe$2);
}
function compare2(a, b) {
  let $ = a === b;
  if ($) {
    return Order$Eq$const;
  } else {
    let $1 = less_than(a, b);
    if ($1) {
      return Order$Lt$const;
    } else {
      return Order$Gt$const;
    }
  }
}
function slice(string, idx, len) {
  let $ = len <= 0;
  if ($) {
    return "";
  } else {
    let $1 = idx < 0;
    if ($1) {
      let translated_idx = string_length(string) + idx;
      let $2 = translated_idx < 0;
      if ($2) {
        return "";
      } else {
        return string_grapheme_slice(string, translated_idx, len);
      }
    } else {
      return string_grapheme_slice(string, idx, len);
    }
  }
}
function drop_start(string, num_graphemes) {
  let $ = num_graphemes <= 0;
  if ($) {
    return string;
  } else {
    let prefix = string_grapheme_slice(string, 0, num_graphemes);
    let prefix_size = byte_size(prefix);
    return string_byte_slice(string, prefix_size, byte_size(string) - prefix_size);
  }
}
function drop_end(string, num_graphemes) {
  let $ = num_graphemes <= 0;
  if ($) {
    return string;
  } else {
    return slice(string, 0, string_length(string) - num_graphemes);
  }
}
function split2(x, substring) {
  if (substring === "") {
    return graphemes(x);
  } else {
    let _pipe = x;
    let _pipe$1 = identity(_pipe);
    let _pipe$2 = split(_pipe$1, substring);
    return map2(_pipe$2, identity);
  }
}
function append(first, second) {
  return first + second;
}
function concat_loop(loop$strings, loop$accumulator) {
  while (true) {
    let strings = loop$strings;
    let accumulator = loop$accumulator;
    if (strings instanceof Empty) {
      return accumulator;
    } else {
      let string = strings.head;
      let strings$1 = strings.tail;
      loop$strings = strings$1;
      loop$accumulator = accumulator + string;
    }
  }
}
function concat2(strings) {
  return concat_loop(strings, "");
}
function repeat_loop(loop$times, loop$doubling_acc, loop$acc) {
  while (true) {
    let times = loop$times;
    let doubling_acc = loop$doubling_acc;
    let acc = loop$acc;
    let _block;
    let $ = times % 2;
    if ($ === 0) {
      _block = acc;
    } else {
      _block = acc + doubling_acc;
    }
    let acc$1 = _block;
    let times$1 = globalThis.Math.trunc(times / 2);
    let $1 = times$1 <= 0;
    if ($1) {
      return acc$1;
    } else {
      loop$times = times$1;
      loop$doubling_acc = doubling_acc + doubling_acc;
      loop$acc = acc$1;
    }
  }
}
function repeat(string, times) {
  let $ = times <= 0;
  if ($) {
    return "";
  } else {
    return repeat_loop(times, string, "");
  }
}
function join_loop(loop$strings, loop$separator, loop$accumulator) {
  while (true) {
    let strings = loop$strings;
    let separator = loop$separator;
    let accumulator = loop$accumulator;
    if (strings instanceof Empty) {
      return accumulator;
    } else {
      let string = strings.head;
      let strings$1 = strings.tail;
      loop$strings = strings$1;
      loop$separator = separator;
      loop$accumulator = accumulator + separator + string;
    }
  }
}
function join(strings, separator) {
  if (strings instanceof Empty) {
    return "";
  } else {
    let first$1 = strings.head;
    let rest = strings.tail;
    return join_loop(rest, separator, first$1);
  }
}
function do_to_utf_codepoints(string) {
  let _pipe = string;
  let _pipe$1 = string_to_codepoint_integer_list(_pipe);
  return map2(_pipe$1, codepoint);
}
function to_utf_codepoints(string) {
  return do_to_utf_codepoints(string);
}
function utf_codepoint(value) {
  let i = value;
  if (i > 1114111) {
    return new Error2(undefined);
  } else {
    let i$1 = value;
    if (i$1 >= 55296 && i$1 <= 57343) {
      return new Error2(undefined);
    } else {
      let i$2 = value;
      if (i$2 < 0) {
        return new Error2(undefined);
      } else {
        let i$3 = value;
        return new Ok(codepoint(i$3));
      }
    }
  }
}
function inspect2(term) {
  let _pipe = term;
  let _pipe$1 = inspect(_pipe);
  return identity(_pipe$1);
}

// build/dev/javascript/gleam_stdlib/gleam/bit_array.mjs
function pad_to_bytes(data) {
  let $ = bit_array_bit_size(data) % 8;
  if ($ === 0) {
    return data;
  } else {
    let trailing_bit_count = $;
    let padding_bits = 8 - trailing_bit_count;
    return toBitArray([data, sizedInt(0, padding_bits, true)]);
  }
}
function append2(first, second) {
  return bit_array_concat(prepend(first, prepend(second, List$Empty$const)));
}
function base64_decode2(encoded) {
  let _block;
  let $ = bit_array_byte_size(bit_array_from_string(encoded)) % 4;
  if ($ === 0) {
    _block = encoded;
  } else {
    let n = $;
    _block = append(encoded, repeat("=", 4 - n));
  }
  let padded = _block;
  return base64_decode(padded);
}
function compare3(loop$a, loop$b) {
  while (true) {
    let a = loop$a;
    let b = loop$b;
    if (a.bitSize >= 8) {
      if (b.bitSize >= 8) {
        let first_byte = a.byteAt(0);
        let first_rest = bitArraySlice(a, 8);
        let second_byte = b.byteAt(0);
        let second_rest = bitArraySlice(b, 8);
        let f = first_byte;
        let s = second_byte;
        if (f > s) {
          return Order$Gt$const;
        } else {
          let f$1 = first_byte;
          let s$1 = second_byte;
          if (f$1 < s$1) {
            return Order$Lt$const;
          } else {
            loop$a = first_rest;
            loop$b = second_rest;
          }
        }
      } else if (b.bitSize === 0) {
        return Order$Gt$const;
      } else {
        let first = a;
        let second = b;
        let $ = bit_array_to_int_and_size(first);
        let $1 = bit_array_to_int_and_size(second);
        let a$1 = $[0];
        let b$1 = $1[0];
        if (a$1 > b$1) {
          return Order$Gt$const;
        } else {
          let a$2 = $[0];
          let b$2 = $1[0];
          if (a$2 < b$2) {
            return Order$Lt$const;
          } else {
            let size_a = $[1];
            let size_b = $1[1];
            if (size_a > size_b) {
              return Order$Gt$const;
            } else {
              let size_a$1 = $[1];
              let size_b$1 = $1[1];
              if (size_a$1 < size_b$1) {
                return Order$Lt$const;
              } else {
                return Order$Eq$const;
              }
            }
          }
        }
      }
    } else if (b.bitSize === 0) {
      if (a.bitSize === 0) {
        return Order$Eq$const;
      } else {
        return Order$Gt$const;
      }
    } else if (a.bitSize === 0) {
      return Order$Lt$const;
    } else {
      let first = a;
      let second = b;
      let $ = bit_array_to_int_and_size(first);
      let $1 = bit_array_to_int_and_size(second);
      let a$1 = $[0];
      let b$1 = $1[0];
      if (a$1 > b$1) {
        return Order$Gt$const;
      } else {
        let a$2 = $[0];
        let b$2 = $1[0];
        if (a$2 < b$2) {
          return Order$Lt$const;
        } else {
          let size_a = $[1];
          let size_b = $1[1];
          if (size_a > size_b) {
            return Order$Gt$const;
          } else {
            let size_a$1 = $[1];
            let size_b$1 = $1[1];
            if (size_a$1 < size_b$1) {
              return Order$Lt$const;
            } else {
              return Order$Eq$const;
            }
          }
        }
      }
    }
  }
}

// build/dev/javascript/gleam_stdlib/gleam/dynamic/decode.mjs
class DecodeError extends CustomType {
  constructor(expected, found, path) {
    super();
    this.expected = expected;
    this.found = found;
    this.path = path;
  }
}
var DecodeError$DecodeError = (expected, found, path) => new DecodeError(expected, found, path);
class Decoder extends CustomType {
  constructor(function$) {
    super();
    this.function = function$;
  }
}
var dynamic = /* @__PURE__ */ new Decoder(decode_dynamic);
var float2 = /* @__PURE__ */ new Decoder(decode_float);
var int2 = /* @__PURE__ */ new Decoder(decode_int);
var bit_array2 = /* @__PURE__ */ new Decoder(decode_bit_array);
var string2 = /* @__PURE__ */ new Decoder(decode_string);
var bool = /* @__PURE__ */ new Decoder(decode_bool);
function decode_dynamic(data) {
  return [data, List$Empty$const];
}
function run(data, decoder) {
  let $ = decoder.function(data);
  let maybe_invalid_data = $[0];
  let errors = $[1];
  if (errors instanceof Empty) {
    return new Ok(maybe_invalid_data);
  } else {
    return new Error2(errors);
  }
}
function run_dynamic_function(data, name, f) {
  let $ = f(data);
  if ($ instanceof Ok) {
    let data$1 = $[0];
    return [data$1, List$Empty$const];
  } else {
    let placeholder = $[0];
    return [
      placeholder,
      prepend(new DecodeError(name, classify_dynamic(data), List$Empty$const), List$Empty$const)
    ];
  }
}
function decode_float(data) {
  return run_dynamic_function(data, "Float", float);
}
function map3(decoder, transformer) {
  return new Decoder((d) => {
    let $ = decoder.function(d);
    let data = $[0];
    let errors = $[1];
    return [transformer(data), errors];
  });
}
function decode_int(data) {
  return run_dynamic_function(data, "Int", int);
}
function decode_bit_array(data) {
  return run_dynamic_function(data, "BitArray", bit_array);
}
function decode_string(data) {
  return run_dynamic_function(data, "String", string);
}
function run_decoders(loop$data, loop$failure, loop$decoders) {
  while (true) {
    let data = loop$data;
    let failure = loop$failure;
    let decoders = loop$decoders;
    if (decoders instanceof Empty) {
      return failure;
    } else {
      let decoder = decoders.head;
      let decoders$1 = decoders.tail;
      let $ = decoder.function(data);
      let layer = $;
      let errors = $[1];
      if (errors instanceof Empty) {
        return layer;
      } else {
        loop$data = data;
        loop$failure = failure;
        loop$decoders = decoders$1;
      }
    }
  }
}
function one_of(first, alternatives) {
  return new Decoder((dynamic_data) => {
    let $ = first.function(dynamic_data);
    let layer = $;
    let errors = $[1];
    if (errors instanceof Empty) {
      return layer;
    } else {
      return run_decoders(dynamic_data, layer, alternatives);
    }
  });
}
function path_segment_to_string(key) {
  let decoder = one_of(string2, prepend((() => {
    let _pipe = int2;
    return map3(_pipe, to_string);
  })(), prepend((() => {
    let _pipe = float2;
    return map3(_pipe, float_to_string);
  })(), List$Empty$const)));
  let $ = run(key, decoder);
  if ($ instanceof Ok) {
    let key$1 = $[0];
    return key$1;
  } else {
    return "<" + classify_dynamic(key) + ">";
  }
}
function push_path(layer, path) {
  let path$1 = map2(path, (key) => {
    let _pipe = key;
    let _pipe$1 = identity(_pipe);
    return path_segment_to_string(_pipe$1);
  });
  let errors = map2(layer[1], (error) => {
    return new DecodeError(error.expected, error.found, append3(path$1, error.path));
  });
  return [layer[0], errors];
}
function list2(inner) {
  return new Decoder((data) => {
    return list(data, inner.function, (p, k) => {
      return push_path(p, prepend(k, List$Empty$const));
    }, 0, List$Empty$const);
  });
}
function index3(loop$path, loop$position, loop$inner, loop$data, loop$handle_miss) {
  while (true) {
    let path = loop$path;
    let position = loop$position;
    let inner = loop$inner;
    let data = loop$data;
    let handle_miss = loop$handle_miss;
    if (path instanceof Empty) {
      let _pipe = data;
      let _pipe$1 = inner(_pipe);
      return push_path(_pipe$1, reverse(position));
    } else {
      let key = path.head;
      let path$1 = path.tail;
      let $ = index2(data, key);
      if ($ instanceof Ok) {
        let $1 = $[0];
        if ($1 instanceof Some) {
          let data$1 = $1[0];
          loop$path = path$1;
          loop$position = prepend(key, position);
          loop$inner = inner;
          loop$data = data$1;
          loop$handle_miss = handle_miss;
        } else {
          return handle_miss(data, prepend(key, position));
        }
      } else {
        let kind = $[0];
        let $1 = inner(data);
        let default$ = $1[0];
        let _pipe = [
          default$,
          prepend(new DecodeError(kind, classify_dynamic(data), List$Empty$const), List$Empty$const)
        ];
        return push_path(_pipe, reverse(position));
      }
    }
  }
}
function subfield(field_path, field_decoder, next) {
  return new Decoder((data) => {
    let $ = index3(field_path, List$Empty$const, field_decoder.function, data, (data2, position) => {
      let $12 = field_decoder.function(data2);
      let default$ = $12[0];
      let _pipe = [
        default$,
        prepend(new DecodeError("Field", "Nothing", List$Empty$const), List$Empty$const)
      ];
      return push_path(_pipe, reverse(position));
    });
    let out = $[0];
    let errors1 = $[1];
    let $1 = next(out).function(data);
    let out$1 = $1[0];
    let errors2 = $1[1];
    return [out$1, append3(errors1, errors2)];
  });
}
function success(data) {
  return new Decoder((_) => {
    return [data, List$Empty$const];
  });
}
function decode_error(expected, found) {
  return prepend(new DecodeError(expected, classify_dynamic(found), List$Empty$const), List$Empty$const);
}
function field(field_name, field_decoder, next) {
  return subfield(prepend(field_name, List$Empty$const), field_decoder, next);
}
function optional_field(key, default$, field_decoder, next) {
  return new Decoder((data) => {
    let _block;
    let _block$1;
    let $1 = index2(data, key);
    if ($1 instanceof Ok) {
      let $22 = $1[0];
      if ($22 instanceof Some) {
        let data$1 = $22[0];
        _block$1 = field_decoder.function(data$1);
      } else {
        _block$1 = [default$, List$Empty$const];
      }
    } else {
      let kind = $1[0];
      _block$1 = [
        default$,
        prepend(new DecodeError(kind, classify_dynamic(data), List$Empty$const), List$Empty$const)
      ];
    }
    let _pipe = _block$1;
    _block = push_path(_pipe, prepend(key, List$Empty$const));
    let $ = _block;
    let out = $[0];
    let errors1 = $[1];
    let $2 = next(out).function(data);
    let out$1 = $2[0];
    let errors2 = $2[1];
    return [out$1, append3(errors1, errors2)];
  });
}
function decode_bool(data) {
  let $ = isEqual(identity(true), data);
  if ($) {
    return [true, List$Empty$const];
  } else {
    let $1 = isEqual(identity(false), data);
    if ($1) {
      return [false, List$Empty$const];
    } else {
      return [false, decode_error("Bool", data)];
    }
  }
}
function fold_dict(acc, key, value, key_decoder, value_decoder) {
  let $ = key_decoder(key);
  let $1 = $[1];
  if ($1 instanceof Empty) {
    let key_decoded = $[0];
    let $2 = value_decoder(value);
    let $3 = $2[1];
    if ($3 instanceof Empty) {
      let value$1 = $2[0];
      let dict$1 = insert(acc[0], key_decoded, value$1);
      return [dict$1, acc[1]];
    } else {
      let errors = $3;
      let key_identifier = path_segment_to_string(key);
      return push_path([make(), errors], prepend(key_identifier, List$Empty$const));
    }
  } else {
    let errors = $1;
    return push_path([make(), errors], prepend("keys", List$Empty$const));
  }
}
function dict2(key, value) {
  return new Decoder((data) => {
    let $ = dict(data);
    if ($ instanceof Ok) {
      let dict$1 = $[0];
      return fold(dict$1, [make(), List$Empty$const], (a, k, v) => {
        let $1 = a[1];
        if ($1 instanceof Empty) {
          return fold_dict(a, k, v, key.function, value.function);
        } else {
          return a;
        }
      });
    } else {
      return [make(), decode_error("Dict", data)];
    }
  });
}
function optional(inner) {
  return new Decoder((data) => {
    let $ = is_null(data);
    if ($) {
      return [Option$None$const, List$Empty$const];
    } else {
      let $1 = inner.function(data);
      let data$1 = $1[0];
      let errors = $1[1];
      return [new Some(data$1), errors];
    }
  });
}
function failure(placeholder, name) {
  return new Decoder((d) => {
    return [placeholder, decode_error(name, d)];
  });
}

// build/dev/javascript/gleam_stdlib/gleam_stdlib.mjs
var Nil = undefined;
function identity(x) {
  return x;
}
function parse_int(value) {
  if (/^[-+]?(\d+)$/.test(value)) {
    return Result$Ok(parseInt(value));
  } else {
    return Result$Error(Nil);
  }
}
function to_string(term) {
  return term.toString();
}
function string_replace(string3, target, substitute) {
  return string3.replaceAll(target, substitute);
}
function string_length(string3) {
  if (string3 === "") {
    return 0;
  }
  const iterator = graphemes_iterator(string3);
  if (iterator) {
    let i = 0;
    for (const _ of iterator) {
      i++;
    }
    return i;
  } else {
    return string3.match(/./gsu).length;
  }
}
function graphemes(string3) {
  const iterator = graphemes_iterator(string3);
  if (iterator) {
    return arrayToList(Array.from(iterator).map((item) => item.segment));
  } else {
    return arrayToList(string3.match(/./gsu));
  }
}
var segmenter = undefined;
function graphemes_iterator(string3) {
  if (globalThis.Intl && Intl.Segmenter) {
    segmenter ||= new Intl.Segmenter;
    return segmenter.segment(string3)[Symbol.iterator]();
  }
}
function pop_grapheme(string3) {
  let first;
  const iterator = graphemes_iterator(string3);
  if (iterator) {
    first = iterator.next().value?.segment;
  } else {
    first = string3.match(/./su)?.[0];
  }
  if (first) {
    return Result$Ok([first, string3.slice(first.length)]);
  } else {
    return Result$Error(Nil);
  }
}
function lowercase(string3) {
  return string3.toLowerCase();
}
function uppercase(string3) {
  return string3.toUpperCase();
}
function less_than(a, b) {
  return a < b;
}
function split(xs, pattern) {
  return arrayToList(xs.split(pattern));
}
function string_byte_slice(string3, index4, length2) {
  return string3.slice(index4, index4 + length2);
}
function string_grapheme_slice(string3, idx, len) {
  if (len <= 0 || idx >= string3.length) {
    return "";
  }
  const iterator = graphemes_iterator(string3);
  if (iterator) {
    while (idx-- > 0) {
      iterator.next();
    }
    let result = "";
    while (len-- > 0) {
      const v = iterator.next().value;
      if (v === undefined) {
        break;
      }
      result += v.segment;
    }
    return result;
  } else {
    return string3.match(/./gsu).slice(idx, idx + len).join("");
  }
}
function starts_with(haystack, needle) {
  return haystack.startsWith(needle);
}
function ends_with(haystack, needle) {
  return haystack.endsWith(needle);
}
function split_once(haystack, needle) {
  const index4 = haystack.indexOf(needle);
  if (index4 >= 0) {
    const before = haystack.slice(0, index4);
    const after = haystack.slice(index4 + needle.length);
    return Result$Ok([before, after]);
  } else {
    return Result$Error(Nil);
  }
}
var unicode_whitespaces = [
  " ",
  "\t",
  `
`,
  "\v",
  "\f",
  "\r",
  "\x85",
  "\u2028",
  "\u2029"
].join("");
var trim_start_regex = /* @__PURE__ */ new RegExp(`^[${unicode_whitespaces}]*`);
var trim_end_regex = /* @__PURE__ */ new RegExp(`[${unicode_whitespaces}]*$`);
function bit_array_from_string(string3) {
  return toBitArray([stringBits(string3)]);
}
function bit_array_bit_size(bit_array3) {
  return bit_array3.bitSize;
}
function bit_array_byte_size(bit_array3) {
  return bit_array3.byteSize;
}
function bit_array_concat(bit_arrays) {
  return toBitArray(bit_arrays.toArray());
}
function console_log(term) {
  console.log(term);
}
function bit_array_to_string(bit_array3) {
  if (bit_array3.bitSize % 8 !== 0) {
    return Result$Error(Nil);
  }
  try {
    const decoder = new TextDecoder("utf-8", { fatal: true });
    if (bit_array3.bitOffset === 0) {
      return Result$Ok(decoder.decode(bit_array3.rawBuffer));
    } else {
      const buffer = new Uint8Array(bit_array3.byteSize);
      for (let i = 0;i < buffer.length; i++) {
        buffer[i] = bit_array3.byteAt(i);
      }
      return Result$Ok(decoder.decode(buffer));
    }
  } catch {
    return Result$Error(Nil);
  }
}
function print(string3) {
  if (typeof process === "object" && process.stdout?.write) {
    process.stdout.write(string3);
  } else if (typeof Deno === "object") {
    Deno.stdout.writeSync(new TextEncoder().encode(string3));
  } else {
    console.log(string3);
  }
}
function print_error(string3) {
  if (typeof process === "object" && process.stderr?.write) {
    process.stderr.write(string3);
  } else if (typeof Deno === "object") {
    Deno.stderr.writeSync(new TextEncoder().encode(string3));
  } else {
    console.error(string3);
  }
}
function floor(float3) {
  return Math.floor(float3);
}
function round2(float3) {
  return Math.round(float3);
}
function random_uniform() {
  const random_uniform_result = Math.random();
  if (random_uniform_result === 1) {
    return random_uniform();
  }
  return random_uniform_result;
}
function bit_array_slice(bits2, position, length2) {
  const start = Math.min(position, position + length2);
  const end = Math.max(position, position + length2);
  if (start < 0 || end * 8 > bits2.bitSize) {
    return Result$Error(Nil);
  }
  return Result$Ok(bitArraySlice(bits2, start * 8, end * 8));
}
function codepoint(int3) {
  return new UtfCodepoint(int3);
}
function string_to_codepoint_integer_list(string3) {
  return arrayToList(Array.from(string3).map((item) => item.codePointAt(0)));
}
function utf_codepoint_to_int(utf_codepoint2) {
  return utf_codepoint2.value;
}
function percent_encode(string3) {
  return encodeURIComponent(string3).replaceAll("%2B", "+");
}
var b64EncodeLookup = [
  65,
  66,
  67,
  68,
  69,
  70,
  71,
  72,
  73,
  74,
  75,
  76,
  77,
  78,
  79,
  80,
  81,
  82,
  83,
  84,
  85,
  86,
  87,
  88,
  89,
  90,
  97,
  98,
  99,
  100,
  101,
  102,
  103,
  104,
  105,
  106,
  107,
  108,
  109,
  110,
  111,
  112,
  113,
  114,
  115,
  116,
  117,
  118,
  119,
  120,
  121,
  122,
  48,
  49,
  50,
  51,
  52,
  53,
  54,
  55,
  56,
  57,
  43,
  47
];
var b64TextDecoder;
function base64_encode(bit_array3, padding) {
  b64TextDecoder ??= new TextDecoder;
  bit_array3 = pad_to_bytes(bit_array3);
  const m = bit_array3.byteSize;
  const k = m % 3;
  const n = Math.floor(m / 3) * 4 + (k && k + 1);
  const N = Math.ceil(m / 3) * 4;
  const encoded = new Uint8Array(N);
  for (let i = 0, j = 0;j < m; i += 4, j += 3) {
    const y = (bit_array3.byteAt(j) << 16) + (bit_array3.byteAt(j + 1) << 8) + (bit_array3.byteAt(j + 2) | 0);
    encoded[i] = b64EncodeLookup[y >> 18];
    encoded[i + 1] = b64EncodeLookup[y >> 12 & 63];
    encoded[i + 2] = b64EncodeLookup[y >> 6 & 63];
    encoded[i + 3] = b64EncodeLookup[y & 63];
  }
  let base64 = b64TextDecoder.decode(new Uint8Array(encoded.buffer, 0, n));
  if (padding) {
    if (k === 1) {
      base64 += "==";
    } else if (k === 2) {
      base64 += "=";
    }
  }
  return base64;
}
function base64_decode(sBase64) {
  try {
    const binString = atob(sBase64);
    const length2 = binString.length;
    const array = new Uint8Array(length2);
    for (let i = 0;i < length2; i++) {
      array[i] = binString.charCodeAt(i);
    }
    return Result$Ok(new BitArray(array));
  } catch {
    return Result$Error(Nil);
  }
}
function classify_dynamic(data) {
  if (typeof data === "string") {
    return "String";
  } else if (typeof data === "boolean") {
    return "Bool";
  } else if (isResult(data)) {
    return "Result";
  } else if (isList(data)) {
    return "List";
  } else if (data instanceof BitArray) {
    return "BitArray";
  } else if (data instanceof Dict) {
    return "Dict";
  } else if (Number.isInteger(data)) {
    return "Int";
  } else if (Array.isArray(data)) {
    return `Array`;
  } else if (typeof data === "number") {
    return "Float";
  } else if (data === null) {
    return "Nil";
  } else if (data === undefined) {
    return "Nil";
  } else {
    const type = typeof data;
    return type.charAt(0).toUpperCase() + type.slice(1);
  }
}
function byte_size(string3) {
  return new TextEncoder().encode(string3).length;
}
var MIN_I32 = -(2 ** 31);
var MAX_I32 = 2 ** 31 - 1;
var U32 = 2 ** 32;
var MAX_SAFE = Number.MAX_SAFE_INTEGER;
var MIN_SAFE = Number.MIN_SAFE_INTEGER;
function bitwise_and(x, y) {
  if (x >= MIN_I32 && x <= MAX_I32 && y >= MIN_I32 && y <= MAX_I32)
    return x & y;
  if (x < MIN_SAFE || x > MAX_SAFE || y < MIN_SAFE || y > MAX_SAFE)
    return Number(BigInt(x) & BigInt(y));
  return (Math.floor(x / U32) & Math.floor(y / U32)) * U32 + ((x & y) >>> 0);
}
function bitwise_or(x, y) {
  if (x >= MIN_I32 && x <= MAX_I32 && y >= MIN_I32 && y <= MAX_I32)
    return x | y;
  if (x < MIN_SAFE || x > MAX_SAFE || y < MIN_SAFE || y > MAX_SAFE)
    return Number(BigInt(x) | BigInt(y));
  return (Math.floor(x / U32) | Math.floor(y / U32)) * U32 + ((x | y) >>> 0);
}
function bitwise_shift_right(x, y) {
  if (y === 0)
    return x;
  if (y < 0)
    return bitwise_shift_left(x, -y);
  if (y < 32 && x >= MIN_I32 && x <= MAX_I32)
    return x >> y;
  if (x < MIN_SAFE || x > MAX_SAFE)
    return Number(BigInt(x) >> BigInt(y));
  const ahi = Math.floor(x / U32);
  if (y < 32)
    return (ahi >> y) * U32 + ((x >>> y | ahi << 32 - y) >>> 0);
  return ahi >> y - 32;
}
function bitwise_shift_left(x, y) {
  if (y === 0)
    return x;
  if (y < 0)
    return bitwise_shift_right(x, -y);
  if (y < 31)
    return x * (1 << y);
  return x * 2 ** y;
}
function inspect(v) {
  return new Inspector().inspect(v);
}
function float_to_string(float3) {
  const string3 = float3.toString().replace("+", "");
  if (string3.indexOf(".") >= 0) {
    return string3;
  } else {
    const index4 = string3.indexOf("e");
    if (index4 >= 0) {
      return string3.slice(0, index4) + ".0" + string3.slice(index4);
    } else {
      return string3 + ".0";
    }
  }
}

class Inspector {
  #references = new Set;
  inspect(v) {
    const t = typeof v;
    if (v === true)
      return "True";
    if (v === false)
      return "False";
    if (v === null)
      return "//js(null)";
    if (v === undefined)
      return "Nil";
    if (t === "string")
      return this.#string(v);
    if (t === "bigint" || Number.isInteger(v))
      return v.toString();
    if (t === "number")
      return float_to_string(v);
    if (v instanceof UtfCodepoint)
      return this.#utfCodepoint(v);
    if (v instanceof BitArray)
      return this.#bit_array(v);
    if (v instanceof RegExp)
      return `//js(${v})`;
    if (v instanceof Date)
      return `//js(Date("${v.toISOString()}"))`;
    if (v instanceof globalThis.Error)
      return `//js(${v.toString()})`;
    if (v instanceof Function) {
      const args = [];
      for (const i of Array(v.length).keys())
        args.push(String.fromCharCode(i + 97));
      return `//fn(${args.join(", ")}) { ... }`;
    }
    if (this.#references.size === this.#references.add(v).size) {
      return "//js(circular reference)";
    }
    let printed;
    if (Array.isArray(v)) {
      printed = `#(${v.map((v2) => this.inspect(v2)).join(", ")})`;
    } else if (isList(v)) {
      printed = this.#list(v);
    } else if (v instanceof CustomType) {
      printed = this.#customType(v);
    } else if (v instanceof Dict) {
      printed = this.#dict(v);
    } else if (v instanceof Set) {
      return `//js(Set(${[...v].map((v2) => this.inspect(v2)).join(", ")}))`;
    } else {
      printed = this.#object(v);
    }
    this.#references.delete(v);
    return printed;
  }
  #object(v) {
    const name = Object.getPrototypeOf(v)?.constructor?.name || "Object";
    const props = [];
    for (const k of Object.keys(v)) {
      props.push(`${this.inspect(k)}: ${this.inspect(v[k])}`);
    }
    const body = props.length ? " " + props.join(", ") + " " : "";
    const head = name === "Object" ? "" : name + " ";
    return `//js(${head}{${body}})`;
  }
  #dict(map4) {
    let body = "dict.from_list([";
    let first = true;
    body = fold(map4, body, (body2, key, value) => {
      if (!first)
        body2 = body2 + ", ";
      first = false;
      return body2 + "#(" + this.inspect(key) + ", " + this.inspect(value) + ")";
    });
    return body + "])";
  }
  #customType(record) {
    const props = Object.keys(record).map((label) => {
      const value = this.inspect(record[label]);
      return isNaN(parseInt(label)) ? `${label}: ${value}` : value;
    }).join(", ");
    return props ? `${record.constructor.name}(${props})` : record.constructor.name;
  }
  #list(list3) {
    if (List$isEmpty(list3)) {
      return "[]";
    }
    let char_out = 'charlist.from_string("';
    let list_out = "[";
    let current = list3;
    while (List$isNonEmpty(current)) {
      let element = current.head;
      current = current.tail;
      if (list_out !== "[") {
        list_out += ", ";
      }
      list_out += this.inspect(element);
      if (char_out) {
        if (Number.isInteger(element) && element >= 32 && element <= 126) {
          char_out += String.fromCharCode(element);
        } else {
          char_out = null;
        }
      }
    }
    if (char_out) {
      return char_out + '")';
    } else {
      return list_out + "]";
    }
  }
  #string(str) {
    let new_str = '"';
    for (let i = 0;i < str.length; i++) {
      const char = str[i];
      switch (char) {
        case `
`:
          new_str += "\\n";
          break;
        case "\r":
          new_str += "\\r";
          break;
        case "\t":
          new_str += "\\t";
          break;
        case "\f":
          new_str += "\\f";
          break;
        case "\\":
          new_str += "\\\\";
          break;
        case '"':
          new_str += "\\\"";
          break;
        default:
          if (char < " " || char > "~" && char < "\xA0") {
            new_str += "\\u{" + char.charCodeAt(0).toString(16).toUpperCase().padStart(4, "0") + "}";
          } else {
            new_str += char;
          }
      }
    }
    new_str += '"';
    return new_str;
  }
  #utfCodepoint(codepoint2) {
    return `//utfcodepoint(${String.fromCodePoint(codepoint2.value)})`;
  }
  #bit_array(bits2) {
    if (bits2.bitSize === 0) {
      return "<<>>";
    }
    let acc = "<<";
    for (let i = 0;i < bits2.byteSize - 1; i++) {
      acc += bits2.byteAt(i).toString();
      acc += ", ";
    }
    if (bits2.byteSize * 8 === bits2.bitSize) {
      acc += bits2.byteAt(bits2.byteSize - 1).toString();
    } else {
      const trailingBitsCount = bits2.bitSize % 8;
      acc += bits2.byteAt(bits2.byteSize - 1) >> 8 - trailingBitsCount;
      acc += `:size(${trailingBitsCount})`;
    }
    acc += ">>";
    return acc;
  }
}
function bit_array_to_int_and_size(bits2) {
  const trailingBitsCount = bits2.bitSize % 8;
  const unusedBitsCount = trailingBitsCount === 0 ? 0 : 8 - trailingBitsCount;
  return [bits2.byteAt(0) >> unusedBitsCount, bits2.bitSize];
}
function index2(data, key) {
  if (data instanceof Dict) {
    const result = get(data, key);
    return Result$Ok(result.isOk() ? new Some(result[0]) : new None);
  }
  if (data instanceof WeakMap || data instanceof Map) {
    const token = {};
    const entry = data.get(key, token);
    if (entry === token)
      return Result$Ok(new None);
    return Result$Ok(new Some(entry));
  }
  const key_is_int = Number.isInteger(key);
  if (key_is_int && key >= 0 && key < 8 && isList(data)) {
    let i = 0;
    for (const value of data) {
      if (i === key)
        return Result$Ok(new Some(value));
      i++;
    }
    return Result$Error("Indexable");
  }
  if (key_is_int && Array.isArray(data) || data && typeof data === "object" || data && Object.getPrototypeOf(data) === Object.prototype) {
    if (key in data)
      return Result$Ok(new Some(data[key]));
    return Result$Ok(new None);
  }
  return Result$Error(key_is_int ? "Indexable" : "Dict");
}
function list(data, decode, pushPath, index4, emptyList) {
  if (!(isList(data) || Array.isArray(data))) {
    const error = DecodeError$DecodeError("List", classify_dynamic(data), emptyList);
    return [emptyList, arrayToList([error])];
  }
  const decoded = [];
  for (const element of data) {
    const layer = decode(element);
    const [out, errors] = layer;
    if (List$isNonEmpty(errors)) {
      const [_, errors2] = pushPath(layer, index4.toString());
      return [emptyList, errors2];
    }
    decoded.push(out);
    index4++;
  }
  return [arrayToList(decoded), emptyList];
}
function dict(data) {
  if (data instanceof Dict) {
    return Result$Ok(data);
  }
  if (data instanceof Map || data instanceof WeakMap) {
    return Result$Ok(from(data));
  }
  if (data == null) {
    return Result$Error("Dict");
  }
  if (typeof data !== "object") {
    return Result$Error("Dict");
  }
  const proto = Object.getPrototypeOf(data);
  if (proto === Object.prototype || proto === null) {
    return Result$Ok(from(Object.entries(data)));
  }
  return Result$Error("Dict");
}
function bit_array(data) {
  if (data instanceof BitArray)
    return Result$Ok(data);
  if (data instanceof Uint8Array)
    return Result$Ok(new BitArray(data));
  return Result$Error(new BitArray(new Uint8Array));
}
function float(data) {
  if (typeof data === "number")
    return Result$Ok(data);
  return Result$Error(0);
}
function int(data) {
  if (Number.isInteger(data))
    return Result$Ok(data);
  return Result$Error(0);
}
function string(data) {
  if (typeof data === "string")
    return Result$Ok(data);
  return Result$Error("");
}
function is_null(data) {
  return data === null || data === undefined;
}
function arrayToList(array) {
  let list3 = List$Empty();
  let i = array.length;
  while (i--) {
    list3 = List$NonEmpty(array[i], list3);
  }
  return list3;
}
function isList(data) {
  return List$isEmpty(data) || List$isNonEmpty(data);
}
function isResult(data) {
  return Result$isOk(data) || Result$isError(data);
}

// build/dev/javascript/gleam_stdlib/gleam/float.mjs
function negate(x) {
  return -1 * x;
}
function round(x) {
  let $ = x >= 0;
  if ($) {
    return round2(x);
  } else {
    return 0 - round2(negate(x));
  }
}

// build/dev/javascript/gleam_stdlib/gleam/list.mjs
class Ascending extends CustomType {
}
var Sorting$Ascending$const = new Ascending;

class Descending extends CustomType {
}
var Sorting$Descending$const = new Descending;
function length_loop(loop$list, loop$count) {
  while (true) {
    let list3 = loop$list;
    let count = loop$count;
    if (list3 instanceof Empty) {
      return count;
    } else {
      let list$1 = list3.tail;
      loop$list = list$1;
      loop$count = count + 1;
    }
  }
}
function length2(list3) {
  return length_loop(list3, 0);
}
function reverse_and_prepend(loop$prefix, loop$suffix) {
  while (true) {
    let prefix = loop$prefix;
    let suffix = loop$suffix;
    if (prefix instanceof Empty) {
      return suffix;
    } else {
      let first$1 = prefix.head;
      let rest$1 = prefix.tail;
      loop$prefix = rest$1;
      loop$suffix = prepend(first$1, suffix);
    }
  }
}
function reverse(list3) {
  return reverse_and_prepend(list3, List$Empty$const);
}
function contains(loop$list, loop$elem) {
  while (true) {
    let list3 = loop$list;
    let elem = loop$elem;
    if (list3 instanceof Empty) {
      return false;
    } else {
      let first$1 = list3.head;
      if (isEqual(first$1, elem)) {
        return true;
      } else {
        let rest$1 = list3.tail;
        loop$list = rest$1;
        loop$elem = elem;
      }
    }
  }
}
function filter_loop(loop$list, loop$fun, loop$acc) {
  while (true) {
    let list3 = loop$list;
    let fun = loop$fun;
    let acc = loop$acc;
    if (list3 instanceof Empty) {
      return reverse(acc);
    } else {
      let first$1 = list3.head;
      let rest$1 = list3.tail;
      let _block;
      let $ = fun(first$1);
      if ($) {
        _block = prepend(first$1, acc);
      } else {
        _block = acc;
      }
      let new_acc = _block;
      loop$list = rest$1;
      loop$fun = fun;
      loop$acc = new_acc;
    }
  }
}
function filter(list3, predicate) {
  return filter_loop(list3, predicate, List$Empty$const);
}
function filter_map_loop(loop$list, loop$fun, loop$acc) {
  while (true) {
    let list3 = loop$list;
    let fun = loop$fun;
    let acc = loop$acc;
    if (list3 instanceof Empty) {
      return reverse(acc);
    } else {
      let first$1 = list3.head;
      let rest$1 = list3.tail;
      let _block;
      let $ = fun(first$1);
      if ($ instanceof Ok) {
        let first$2 = $[0];
        _block = prepend(first$2, acc);
      } else {
        _block = acc;
      }
      let new_acc = _block;
      loop$list = rest$1;
      loop$fun = fun;
      loop$acc = new_acc;
    }
  }
}
function filter_map(list3, fun) {
  return filter_map_loop(list3, fun, List$Empty$const);
}
function map_loop(loop$list, loop$fun, loop$acc) {
  while (true) {
    let list3 = loop$list;
    let fun = loop$fun;
    let acc = loop$acc;
    if (list3 instanceof Empty) {
      return reverse(acc);
    } else {
      let first$1 = list3.head;
      let rest$1 = list3.tail;
      loop$list = rest$1;
      loop$fun = fun;
      loop$acc = prepend(fun(first$1), acc);
    }
  }
}
function map2(list3, fun) {
  return map_loop(list3, fun, List$Empty$const);
}
function try_map_loop(loop$list, loop$fun, loop$acc) {
  while (true) {
    let list3 = loop$list;
    let fun = loop$fun;
    let acc = loop$acc;
    if (list3 instanceof Empty) {
      return new Ok(reverse(acc));
    } else {
      let first$1 = list3.head;
      let rest$1 = list3.tail;
      let $ = fun(first$1);
      if ($ instanceof Ok) {
        let first$2 = $[0];
        loop$list = rest$1;
        loop$fun = fun;
        loop$acc = prepend(first$2, acc);
      } else {
        return $;
      }
    }
  }
}
function try_map(list3, fun) {
  return try_map_loop(list3, fun, List$Empty$const);
}
function append_loop(loop$first, loop$second) {
  while (true) {
    let first = loop$first;
    let second = loop$second;
    if (first instanceof Empty) {
      return second;
    } else {
      let first$1 = first.head;
      let rest$1 = first.tail;
      loop$first = rest$1;
      loop$second = prepend(first$1, second);
    }
  }
}
function append3(first, second) {
  return append_loop(reverse(first), second);
}
function flatten_loop(loop$lists, loop$acc) {
  while (true) {
    let lists = loop$lists;
    let acc = loop$acc;
    if (lists instanceof Empty) {
      return reverse(acc);
    } else {
      let list3 = lists.head;
      let further_lists = lists.tail;
      loop$lists = further_lists;
      loop$acc = reverse_and_prepend(list3, acc);
    }
  }
}
function flatten(lists) {
  return flatten_loop(lists, List$Empty$const);
}
function flat_map(list3, fun) {
  return flatten(map2(list3, fun));
}
function fold2(loop$list, loop$initial, loop$fun) {
  while (true) {
    let list3 = loop$list;
    let initial = loop$initial;
    let fun = loop$fun;
    if (list3 instanceof Empty) {
      return initial;
    } else {
      let first$1 = list3.head;
      let rest$1 = list3.tail;
      loop$list = rest$1;
      loop$initial = fun(initial, first$1);
      loop$fun = fun;
    }
  }
}
function fold_right(list3, initial, fun) {
  if (list3 instanceof Empty) {
    return initial;
  } else {
    let first$1 = list3.head;
    let rest$1 = list3.tail;
    return fun(fold_right(rest$1, initial, fun), first$1);
  }
}
function find(loop$list, loop$is_desired) {
  while (true) {
    let list3 = loop$list;
    let is_desired = loop$is_desired;
    if (list3 instanceof Empty) {
      return new Error2(undefined);
    } else {
      let first$1 = list3.head;
      let rest$1 = list3.tail;
      let $ = is_desired(first$1);
      if ($) {
        return new Ok(first$1);
      } else {
        loop$list = rest$1;
        loop$is_desired = is_desired;
      }
    }
  }
}
function find_map(loop$list, loop$fun) {
  while (true) {
    let list3 = loop$list;
    let fun = loop$fun;
    if (list3 instanceof Empty) {
      return new Error2(undefined);
    } else {
      let first$1 = list3.head;
      let rest$1 = list3.tail;
      let $ = fun(first$1);
      if ($ instanceof Ok) {
        return $;
      } else {
        loop$list = rest$1;
        loop$fun = fun;
      }
    }
  }
}
function any(loop$list, loop$predicate) {
  while (true) {
    let list3 = loop$list;
    let predicate = loop$predicate;
    if (list3 instanceof Empty) {
      return false;
    } else {
      let first$1 = list3.head;
      let rest$1 = list3.tail;
      let $ = predicate(first$1);
      if ($) {
        return $;
      } else {
        loop$list = rest$1;
        loop$predicate = predicate;
      }
    }
  }
}
function intersperse_loop(loop$list, loop$separator, loop$acc) {
  while (true) {
    let list3 = loop$list;
    let separator = loop$separator;
    let acc = loop$acc;
    if (list3 instanceof Empty) {
      return reverse(acc);
    } else {
      let first$1 = list3.head;
      let rest$1 = list3.tail;
      loop$list = rest$1;
      loop$separator = separator;
      loop$acc = prepend(first$1, prepend(separator, acc));
    }
  }
}
function intersperse(list3, elem) {
  if (list3 instanceof Empty) {
    return list3;
  } else {
    let $ = list3.tail;
    if ($ instanceof Empty) {
      return list3;
    } else {
      let first$1 = list3.head;
      let rest$1 = $;
      return intersperse_loop(rest$1, elem, prepend(first$1, List$Empty$const));
    }
  }
}
function merge_descendings(loop$list1, loop$list2, loop$compare, loop$acc) {
  while (true) {
    let list1 = loop$list1;
    let list22 = loop$list2;
    let compare5 = loop$compare;
    let acc = loop$acc;
    if (list1 instanceof Empty) {
      let list3 = list22;
      return reverse_and_prepend(list3, acc);
    } else if (list22 instanceof Empty) {
      let list3 = list1;
      return reverse_and_prepend(list3, acc);
    } else {
      let first1 = list1.head;
      let rest1 = list1.tail;
      let first2 = list22.head;
      let rest2 = list22.tail;
      let $ = compare5(first1, first2);
      if ($ instanceof Lt) {
        loop$list1 = list1;
        loop$list2 = rest2;
        loop$compare = compare5;
        loop$acc = prepend(first2, acc);
      } else if ($ instanceof Eq) {
        loop$list1 = rest1;
        loop$list2 = list22;
        loop$compare = compare5;
        loop$acc = prepend(first1, acc);
      } else {
        loop$list1 = rest1;
        loop$list2 = list22;
        loop$compare = compare5;
        loop$acc = prepend(first1, acc);
      }
    }
  }
}
function merge_descending_pairs(loop$sequences, loop$compare, loop$acc) {
  while (true) {
    let sequences = loop$sequences;
    let compare5 = loop$compare;
    let acc = loop$acc;
    if (sequences instanceof Empty) {
      return reverse(acc);
    } else {
      let $ = sequences.tail;
      if ($ instanceof Empty) {
        let sequence = sequences.head;
        return reverse(prepend(reverse(sequence), acc));
      } else {
        let descending1 = sequences.head;
        let descending2 = $.head;
        let rest$1 = $.tail;
        let ascending = merge_descendings(descending1, descending2, compare5, List$Empty$const);
        loop$sequences = rest$1;
        loop$compare = compare5;
        loop$acc = prepend(ascending, acc);
      }
    }
  }
}
function merge_ascendings(loop$list1, loop$list2, loop$compare, loop$acc) {
  while (true) {
    let list1 = loop$list1;
    let list22 = loop$list2;
    let compare5 = loop$compare;
    let acc = loop$acc;
    if (list1 instanceof Empty) {
      let list3 = list22;
      return reverse_and_prepend(list3, acc);
    } else if (list22 instanceof Empty) {
      let list3 = list1;
      return reverse_and_prepend(list3, acc);
    } else {
      let first1 = list1.head;
      let rest1 = list1.tail;
      let first2 = list22.head;
      let rest2 = list22.tail;
      let $ = compare5(first1, first2);
      if ($ instanceof Lt) {
        loop$list1 = rest1;
        loop$list2 = list22;
        loop$compare = compare5;
        loop$acc = prepend(first1, acc);
      } else if ($ instanceof Eq) {
        loop$list1 = list1;
        loop$list2 = rest2;
        loop$compare = compare5;
        loop$acc = prepend(first2, acc);
      } else {
        loop$list1 = list1;
        loop$list2 = rest2;
        loop$compare = compare5;
        loop$acc = prepend(first2, acc);
      }
    }
  }
}
function merge_ascending_pairs(loop$sequences, loop$compare, loop$acc) {
  while (true) {
    let sequences = loop$sequences;
    let compare5 = loop$compare;
    let acc = loop$acc;
    if (sequences instanceof Empty) {
      return reverse(acc);
    } else {
      let $ = sequences.tail;
      if ($ instanceof Empty) {
        let sequence = sequences.head;
        return reverse(prepend(reverse(sequence), acc));
      } else {
        let ascending1 = sequences.head;
        let ascending2 = $.head;
        let rest$1 = $.tail;
        let descending = merge_ascendings(ascending1, ascending2, compare5, List$Empty$const);
        loop$sequences = rest$1;
        loop$compare = compare5;
        loop$acc = prepend(descending, acc);
      }
    }
  }
}
function merge_all(loop$sequences, loop$direction, loop$compare) {
  while (true) {
    let sequences = loop$sequences;
    let direction = loop$direction;
    let compare5 = loop$compare;
    if (sequences instanceof Empty) {
      return sequences;
    } else if (direction instanceof Ascending) {
      if (sequences.tail instanceof Empty) {
        let sequence = sequences.head;
        return sequence;
      } else {
        let sequences$1 = merge_ascending_pairs(sequences, compare5, List$Empty$const);
        loop$sequences = sequences$1;
        loop$direction = Sorting$Descending$const;
        loop$compare = compare5;
      }
    } else if (sequences.tail instanceof Empty) {
      let sequence = sequences.head;
      return reverse(sequence);
    } else {
      let sequences$1 = merge_descending_pairs(sequences, compare5, List$Empty$const);
      loop$sequences = sequences$1;
      loop$direction = Sorting$Ascending$const;
      loop$compare = compare5;
    }
  }
}
function sequences(loop$list, loop$compare, loop$growing, loop$direction, loop$prev, loop$acc) {
  while (true) {
    let list3 = loop$list;
    let compare5 = loop$compare;
    let growing = loop$growing;
    let direction = loop$direction;
    let prev = loop$prev;
    let acc = loop$acc;
    let growing$1 = prepend(prev, growing);
    if (list3 instanceof Empty) {
      if (direction instanceof Ascending) {
        return prepend(reverse(growing$1), acc);
      } else {
        return prepend(growing$1, acc);
      }
    } else {
      let new$1 = list3.head;
      let rest$1 = list3.tail;
      let $ = compare5(prev, new$1);
      if (direction instanceof Ascending) {
        if ($ instanceof Lt) {
          loop$list = rest$1;
          loop$compare = compare5;
          loop$growing = growing$1;
          loop$direction = direction;
          loop$prev = new$1;
          loop$acc = acc;
        } else if ($ instanceof Eq) {
          loop$list = rest$1;
          loop$compare = compare5;
          loop$growing = growing$1;
          loop$direction = direction;
          loop$prev = new$1;
          loop$acc = acc;
        } else {
          let _block;
          if (direction instanceof Ascending) {
            _block = prepend(reverse(growing$1), acc);
          } else {
            _block = prepend(growing$1, acc);
          }
          let acc$1 = _block;
          if (rest$1 instanceof Empty) {
            return prepend(prepend(new$1, List$Empty$const), acc$1);
          } else {
            let next = rest$1.head;
            let rest$2 = rest$1.tail;
            let _block$1;
            let $1 = compare5(new$1, next);
            if ($1 instanceof Lt) {
              _block$1 = Sorting$Ascending$const;
            } else if ($1 instanceof Eq) {
              _block$1 = Sorting$Ascending$const;
            } else {
              _block$1 = Sorting$Descending$const;
            }
            let direction$1 = _block$1;
            loop$list = rest$2;
            loop$compare = compare5;
            loop$growing = prepend(new$1, List$Empty$const);
            loop$direction = direction$1;
            loop$prev = next;
            loop$acc = acc$1;
          }
        }
      } else if ($ instanceof Lt) {
        let _block;
        if (direction instanceof Ascending) {
          _block = prepend(reverse(growing$1), acc);
        } else {
          _block = prepend(growing$1, acc);
        }
        let acc$1 = _block;
        if (rest$1 instanceof Empty) {
          return prepend(prepend(new$1, List$Empty$const), acc$1);
        } else {
          let next = rest$1.head;
          let rest$2 = rest$1.tail;
          let _block$1;
          let $1 = compare5(new$1, next);
          if ($1 instanceof Lt) {
            _block$1 = Sorting$Ascending$const;
          } else if ($1 instanceof Eq) {
            _block$1 = Sorting$Ascending$const;
          } else {
            _block$1 = Sorting$Descending$const;
          }
          let direction$1 = _block$1;
          loop$list = rest$2;
          loop$compare = compare5;
          loop$growing = prepend(new$1, List$Empty$const);
          loop$direction = direction$1;
          loop$prev = next;
          loop$acc = acc$1;
        }
      } else if ($ instanceof Eq) {
        let _block;
        if (direction instanceof Ascending) {
          _block = prepend(reverse(growing$1), acc);
        } else {
          _block = prepend(growing$1, acc);
        }
        let acc$1 = _block;
        if (rest$1 instanceof Empty) {
          return prepend(prepend(new$1, List$Empty$const), acc$1);
        } else {
          let next = rest$1.head;
          let rest$2 = rest$1.tail;
          let _block$1;
          let $1 = compare5(new$1, next);
          if ($1 instanceof Lt) {
            _block$1 = Sorting$Ascending$const;
          } else if ($1 instanceof Eq) {
            _block$1 = Sorting$Ascending$const;
          } else {
            _block$1 = Sorting$Descending$const;
          }
          let direction$1 = _block$1;
          loop$list = rest$2;
          loop$compare = compare5;
          loop$growing = prepend(new$1, List$Empty$const);
          loop$direction = direction$1;
          loop$prev = next;
          loop$acc = acc$1;
        }
      } else {
        loop$list = rest$1;
        loop$compare = compare5;
        loop$growing = growing$1;
        loop$direction = direction;
        loop$prev = new$1;
        loop$acc = acc;
      }
    }
  }
}
function sort(list3, compare5) {
  if (list3 instanceof Empty) {
    return list3;
  } else {
    let $ = list3.tail;
    if ($ instanceof Empty) {
      return list3;
    } else {
      let x = list3.head;
      let y = $.head;
      let rest$1 = $.tail;
      let _block;
      let $1 = compare5(x, y);
      if ($1 instanceof Lt) {
        _block = Sorting$Ascending$const;
      } else if ($1 instanceof Eq) {
        _block = Sorting$Ascending$const;
      } else {
        _block = Sorting$Descending$const;
      }
      let direction = _block;
      let sequences$1 = sequences(rest$1, compare5, prepend(x, List$Empty$const), direction, y, List$Empty$const);
      return merge_all(sequences$1, Sorting$Ascending$const, compare5);
    }
  }
}
function key_find(keyword_list, desired_key) {
  return find_map(keyword_list, (keyword) => {
    let key = keyword[0];
    let value = keyword[1];
    let $ = isEqual(key, desired_key);
    if ($) {
      return new Ok(value);
    } else {
      return new Error2(undefined);
    }
  });
}

// build/dev/javascript/gleam_stdlib/gleam/result.mjs
function is_ok(result) {
  if (result instanceof Ok) {
    return true;
  } else {
    return false;
  }
}
function map4(result, fun) {
  if (result instanceof Ok) {
    let x = result[0];
    return new Ok(fun(x));
  } else {
    return result;
  }
}
function map_error(result, fun) {
  if (result instanceof Ok) {
    return result;
  } else {
    let error = result[0];
    return new Error2(fun(error));
  }
}
function try$(result, fun) {
  if (result instanceof Ok) {
    let x = result[0];
    return fun(x);
  } else {
    return result;
  }
}
function unwrap(result, default$) {
  if (result instanceof Ok) {
    let v = result[0];
    return v;
  } else {
    return default$;
  }
}
function replace_error(result, error) {
  if (result instanceof Ok) {
    return result;
  } else {
    return new Error2(error);
  }
}

// build/dev/javascript/filepath/filepath_ffi.mjs
function is_windows() {
  return globalThis?.process?.platform === "win32" || globalThis?.Deno?.build?.os === "windows";
}
// build/dev/javascript/filepath/filepath.mjs
function remove_trailing_slash(path) {
  let $ = ends_with(path, "/");
  if ($) {
    return drop_end(path, 1);
  } else {
    return path;
  }
}
function relative(loop$path) {
  while (true) {
    let path = loop$path;
    if (path.charCodeAt(0) === 47) {
      let path$1 = path.slice(1);
      loop$path = path$1;
    } else {
      return path;
    }
  }
}
function join2(left, right) {
  let _block;
  if (right === "/") {
    _block = left;
  } else if (right.charCodeAt(0) === 47) {
    if (left === "") {
      _block = relative(right);
    } else if (left === "/") {
      _block = right;
    } else {
      let _pipe2 = remove_trailing_slash(left);
      let _pipe$1 = append(_pipe2, "/");
      _block = append(_pipe$1, relative(right));
    }
  } else if (left === "") {
    _block = relative(right);
  } else if (left === "/") {
    _block = left + right;
  } else {
    let _pipe2 = remove_trailing_slash(left);
    let _pipe$1 = append(_pipe2, "/");
    _block = append(_pipe$1, relative(right));
  }
  let _pipe = _block;
  return remove_trailing_slash(_pipe);
}
function split_unix(path) {
  let _block;
  let $ = split2(path, "/");
  if ($ instanceof Empty) {
    _block = $;
  } else {
    let $1 = $.tail;
    if ($1 instanceof Empty) {
      if ($.head === "") {
        _block = List$Empty$const;
      } else {
        _block = $;
      }
    } else if ($.head === "") {
      let rest = $1;
      _block = prepend("/", rest);
    } else {
      _block = $;
    }
  }
  let _pipe = _block;
  return filter(_pipe, (x) => {
    return x !== "";
  });
}
function pop_windows_drive_specifier(path) {
  let start = slice(path, 0, 3);
  let codepoints = to_utf_codepoints(start);
  let $ = map2(codepoints, utf_codepoint_to_int);
  if ($ instanceof Empty) {
    return [Option$None$const, path];
  } else {
    let $1 = $.tail;
    if ($1 instanceof Empty) {
      return [Option$None$const, path];
    } else {
      let $2 = $1.tail;
      if ($2 instanceof Empty) {
        return [Option$None$const, path];
      } else if ($2.tail instanceof Empty) {
        let drive = $.head;
        let colon = $1.head;
        let slash = $2.head;
        if ((slash === 47 || slash === 92) && colon === 58 && (drive >= 65 && drive <= 90 || drive >= 97 && drive <= 122)) {
          let drive_letter = slice(path, 0, 1);
          let drive$1 = lowercase(drive_letter) + ":/";
          let path$1 = drop_start(path, 3);
          return [new Some(drive$1), path$1];
        } else {
          return [Option$None$const, path];
        }
      } else {
        return [Option$None$const, path];
      }
    }
  }
}
function split_windows(path) {
  let $ = pop_windows_drive_specifier(path);
  let drive = $[0];
  let path$1 = $[1];
  let _block;
  let _pipe = split2(path$1, "/");
  _block = flat_map(_pipe, (_capture) => {
    return split2(_capture, "\\");
  });
  let segments = _block;
  let _block$1;
  if (drive instanceof Some) {
    let drive$1 = drive[0];
    _block$1 = prepend(drive$1, segments);
  } else {
    _block$1 = segments;
  }
  let segments$1 = _block$1;
  if (segments$1 instanceof Empty) {
    return segments$1;
  } else {
    let $1 = segments$1.tail;
    if ($1 instanceof Empty) {
      if (segments$1.head === "") {
        return List$Empty$const;
      } else {
        return segments$1;
      }
    } else if (segments$1.head === "") {
      let rest = $1;
      return prepend("/", rest);
    } else {
      return segments$1;
    }
  }
}
function split3(path) {
  let $ = is_windows();
  if ($) {
    return split_windows(path);
  } else {
    return split_unix(path);
  }
}
function get_directory_name(loop$path, loop$acc, loop$segment) {
  while (true) {
    let path = loop$path;
    let acc = loop$acc;
    let segment = loop$segment;
    if (path instanceof Empty) {
      return acc;
    } else {
      let $ = path.head;
      if ($ === "/") {
        let rest = path.tail;
        loop$path = rest;
        loop$acc = acc + segment;
        loop$segment = "/";
      } else {
        let first = $;
        let rest = path.tail;
        loop$path = rest;
        loop$acc = acc;
        loop$segment = segment + first;
      }
    }
  }
}
function directory_name(path) {
  let path$1 = remove_trailing_slash(path);
  if (path$1.charCodeAt(0) === 47) {
    let rest = path$1.slice(1);
    return get_directory_name(graphemes(rest), "/", "");
  } else {
    return get_directory_name(graphemes(path$1), "", "");
  }
}
function is_absolute(path) {
  return starts_with(path, "/");
}
function expand_segments(loop$path, loop$base) {
  while (true) {
    let path = loop$path;
    let base = loop$base;
    if (path instanceof Empty) {
      return new Ok(join(reverse(base), "/"));
    } else if (base instanceof Empty) {
      let $ = path.head;
      if ($ === "..") {
        return new Error2(undefined);
      } else if ($ === ".") {
        let path$1 = path.tail;
        loop$path = path$1;
        loop$base = base;
      } else {
        let s = $;
        let path$1 = path.tail;
        loop$path = path$1;
        loop$base = prepend(s, base);
      }
    } else {
      let $ = base.tail;
      if ($ instanceof Empty) {
        let $1 = path.head;
        if ($1 === "..") {
          if (base.head === "") {
            return new Error2(undefined);
          } else {
            let path$1 = path.tail;
            let base$1 = $;
            loop$path = path$1;
            loop$base = base$1;
          }
        } else if ($1 === ".") {
          let path$1 = path.tail;
          loop$path = path$1;
          loop$base = base;
        } else {
          let s = $1;
          let path$1 = path.tail;
          loop$path = path$1;
          loop$base = prepend(s, base);
        }
      } else {
        let $1 = path.head;
        if ($1 === "..") {
          let path$1 = path.tail;
          let base$1 = $;
          loop$path = path$1;
          loop$base = base$1;
        } else if ($1 === ".") {
          let path$1 = path.tail;
          loop$path = path$1;
          loop$base = base;
        } else {
          let s = $1;
          let path$1 = path.tail;
          loop$path = path$1;
          loop$base = prepend(s, base);
        }
      }
    }
  }
}
function root_slash_to_empty(segments) {
  if (segments instanceof Empty) {
    return segments;
  } else if (segments.head === "/") {
    let rest = segments.tail;
    return prepend("", rest);
  } else {
    return segments;
  }
}
function expand(path) {
  let is_absolute$1 = is_absolute(path);
  let _block;
  let _pipe = path;
  let _pipe$1 = split3(_pipe);
  let _pipe$2 = root_slash_to_empty(_pipe$1);
  let _pipe$3 = expand_segments(_pipe$2, List$Empty$const);
  _block = map4(_pipe$3, remove_trailing_slash);
  let result = _block;
  let $ = is_absolute$1 && isEqual(result, new Ok(""));
  if ($) {
    return new Ok("/");
  } else {
    return result;
  }
}
// build/dev/javascript/midas/midas/continuation.mjs
function return$(value) {
  return (k) => {
    return k(value);
  };
}
function then$(cont, next) {
  return (k) => {
    return cont((a) => {
      return next(a)(k);
    });
  };
}
// build/dev/javascript/multiformats/multiformats/base32.mjs
var FILEPATH = "src/multiformats/base32.gleam";
function num(a) {
  let a$1 = a;
  if (a$1 >= 65 && a$1 <= 90) {
    return a$1 - 65;
  } else {
    let a$2 = a;
    if (a$2 >= 97 && a$2 <= 122) {
      return a$2 - 97;
    } else {
      let a$3 = a;
      if (a$3 >= 50 && a$3 <= 55) {
        return a$3 - 24;
      } else {
        throw makeError("panic", FILEPATH, "multiformats/base32", 73, "num", "Invalid base32 charachter", {});
      }
    }
  }
}
function do_decode(encoded) {
  if (encoded.bitSize === 0) {
    return toBitArray([]);
  } else if (encoded.bitSize >= 8) {
    if (encoded.bitSize === 16) {
      let a = encoded.byteAt(0);
      let b = encoded.byteAt(1);
      let $ = toBitArray([
        sizedInt(num(a), 5, true),
        sizedInt(num(b), 5, true),
        sizedInt(0, 6, true)
      ]);
      let out;
      if ($.bitSize >= 8 && $.bitSize === 16) {
        out = bitArraySlice($, 0, 8);
      } else {
        throw makeError("let_assert", FILEPATH, "multiformats/base32", 12, "do_decode", "Pattern match failed, no pattern matched the value.", {
          value: $,
          start: 269,
          end: 367,
          pattern_start: 280,
          pattern_end: 304
        });
      }
      return out;
    } else if (encoded.bitSize >= 16) {
      if (encoded.bitSize === 64) {
        if (encoded.byteAt(2) === 61 && encoded.byteAt(3) === 61 && encoded.byteAt(4) === 61 && encoded.byteAt(5) === 61 && encoded.byteAt(6) === 61 && encoded.byteAt(7) === 61) {
          let a = encoded.byteAt(0);
          let b = encoded.byteAt(1);
          let $ = toBitArray([
            sizedInt(num(a), 5, true),
            sizedInt(num(b), 5, true),
            sizedInt(0, 6, true)
          ]);
          let out;
          if ($.bitSize >= 8 && $.bitSize === 16) {
            out = bitArraySlice($, 0, 8);
          } else {
            throw makeError("let_assert", FILEPATH, "multiformats/base32", 12, "do_decode", "Pattern match failed, no pattern matched the value.", {
              value: $,
              start: 269,
              end: 367,
              pattern_start: 280,
              pattern_end: 304
            });
          }
          return out;
        } else if (encoded.byteAt(4) === 61 && encoded.byteAt(5) === 61 && encoded.byteAt(6) === 61 && encoded.byteAt(7) === 61) {
          let a = encoded.byteAt(0);
          let b = encoded.byteAt(1);
          let c = encoded.byteAt(2);
          let d = encoded.byteAt(3);
          let $ = toBitArray([
            sizedInt(num(a), 5, true),
            sizedInt(num(b), 5, true),
            sizedInt(num(c), 5, true),
            sizedInt(num(d), 5, true),
            sizedInt(0, 4, true)
          ]);
          let out;
          if ($.bitSize >= 16 && $.bitSize === 24) {
            out = bitArraySlice($, 0, 16);
          } else {
            throw makeError("let_assert", FILEPATH, "multiformats/base32", 20, "do_decode", "Pattern match failed, no pattern matched the value.", {
              value: $,
              start: 439,
              end: 573,
              pattern_start: 450,
              pattern_end: 474
            });
          }
          return out;
        } else if (encoded.byteAt(5) === 61 && encoded.byteAt(6) === 61 && encoded.byteAt(7) === 61) {
          let a = encoded.byteAt(0);
          let b = encoded.byteAt(1);
          let c = encoded.byteAt(2);
          let d = encoded.byteAt(3);
          let e = encoded.byteAt(4);
          let $ = toBitArray([
            sizedInt(num(a), 5, true),
            sizedInt(num(b), 5, true),
            sizedInt(num(c), 5, true),
            sizedInt(num(d), 5, true),
            sizedInt(num(e), 5, true),
            sizedInt(0, 7, true)
          ]);
          let out;
          if ($.bitSize >= 24 && $.bitSize === 32) {
            out = bitArraySlice($, 0, 24);
          } else {
            throw makeError("let_assert", FILEPATH, "multiformats/base32", 30, "do_decode", "Pattern match failed, no pattern matched the value.", {
              value: $,
              start: 650,
              end: 802,
              pattern_start: 661,
              pattern_end: 685
            });
          }
          return out;
        } else if (encoded.byteAt(7) === 61) {
          let a = encoded.byteAt(0);
          let b = encoded.byteAt(1);
          let c = encoded.byteAt(2);
          let d = encoded.byteAt(3);
          let e = encoded.byteAt(4);
          let f = encoded.byteAt(5);
          let g = encoded.byteAt(6);
          let $ = toBitArray([
            sizedInt(num(a), 5, true),
            sizedInt(num(b), 5, true),
            sizedInt(num(c), 5, true),
            sizedInt(num(d), 5, true),
            sizedInt(num(e), 5, true),
            sizedInt(num(f), 5, true),
            sizedInt(num(g), 5, true),
            sizedInt(0, 5, true)
          ]);
          let out;
          if ($.bitSize >= 32 && $.bitSize === 40) {
            out = bitArraySlice($, 0, 32);
          } else {
            throw makeError("let_assert", FILEPATH, "multiformats/base32", 41, "do_decode", "Pattern match failed, no pattern matched the value.", {
              value: $,
              start: 889,
              end: 1077,
              pattern_start: 900,
              pattern_end: 924
            });
          }
          return out;
        } else if (encoded.bitSize % 8 === 0) {
          let a = encoded.byteAt(0);
          let b = encoded.byteAt(1);
          let c = encoded.byteAt(2);
          let d = encoded.byteAt(3);
          let e = encoded.byteAt(4);
          let f = encoded.byteAt(5);
          let g = encoded.byteAt(6);
          let h = encoded.byteAt(7);
          let rest = bitArraySlice(encoded, 64);
          return toBitArray([
            sizedInt(num(a), 5, true),
            sizedInt(num(b), 5, true),
            sizedInt(num(c), 5, true),
            sizedInt(num(d), 5, true),
            sizedInt(num(e), 5, true),
            sizedInt(num(f), 5, true),
            sizedInt(num(g), 5, true),
            sizedInt(num(h), 5, true),
            do_decode(rest)
          ]);
        } else {
          throw makeError("panic", FILEPATH, "multiformats/base32", 64, "do_decode", "Invalid base32 string", {});
        }
      } else if (encoded.bitSize >= 24) {
        if (encoded.bitSize === 32) {
          let a = encoded.byteAt(0);
          let b = encoded.byteAt(1);
          let c = encoded.byteAt(2);
          let d = encoded.byteAt(3);
          let $ = toBitArray([
            sizedInt(num(a), 5, true),
            sizedInt(num(b), 5, true),
            sizedInt(num(c), 5, true),
            sizedInt(num(d), 5, true),
            sizedInt(0, 4, true)
          ]);
          let out;
          if ($.bitSize >= 16 && $.bitSize === 24) {
            out = bitArraySlice($, 0, 16);
          } else {
            throw makeError("let_assert", FILEPATH, "multiformats/base32", 20, "do_decode", "Pattern match failed, no pattern matched the value.", {
              value: $,
              start: 439,
              end: 573,
              pattern_start: 450,
              pattern_end: 474
            });
          }
          return out;
        } else if (encoded.bitSize >= 32) {
          if (encoded.bitSize === 40) {
            let a = encoded.byteAt(0);
            let b = encoded.byteAt(1);
            let c = encoded.byteAt(2);
            let d = encoded.byteAt(3);
            let e = encoded.byteAt(4);
            let $ = toBitArray([
              sizedInt(num(a), 5, true),
              sizedInt(num(b), 5, true),
              sizedInt(num(c), 5, true),
              sizedInt(num(d), 5, true),
              sizedInt(num(e), 5, true),
              sizedInt(0, 7, true)
            ]);
            let out;
            if ($.bitSize >= 24 && $.bitSize === 32) {
              out = bitArraySlice($, 0, 24);
            } else {
              throw makeError("let_assert", FILEPATH, "multiformats/base32", 30, "do_decode", "Pattern match failed, no pattern matched the value.", {
                value: $,
                start: 650,
                end: 802,
                pattern_start: 661,
                pattern_end: 685
              });
            }
            return out;
          } else if (encoded.bitSize >= 40 && encoded.bitSize >= 48) {
            if (encoded.bitSize === 56) {
              let a = encoded.byteAt(0);
              let b = encoded.byteAt(1);
              let c = encoded.byteAt(2);
              let d = encoded.byteAt(3);
              let e = encoded.byteAt(4);
              let f = encoded.byteAt(5);
              let g = encoded.byteAt(6);
              let $ = toBitArray([
                sizedInt(num(a), 5, true),
                sizedInt(num(b), 5, true),
                sizedInt(num(c), 5, true),
                sizedInt(num(d), 5, true),
                sizedInt(num(e), 5, true),
                sizedInt(num(f), 5, true),
                sizedInt(num(g), 5, true),
                sizedInt(0, 5, true)
              ]);
              let out;
              if ($.bitSize >= 32 && $.bitSize === 40) {
                out = bitArraySlice($, 0, 32);
              } else {
                throw makeError("let_assert", FILEPATH, "multiformats/base32", 41, "do_decode", "Pattern match failed, no pattern matched the value.", {
                  value: $,
                  start: 889,
                  end: 1077,
                  pattern_start: 900,
                  pattern_end: 924
                });
              }
              return out;
            } else if (encoded.bitSize >= 56 && encoded.bitSize >= 64 && encoded.bitSize % 8 === 0) {
              let a = encoded.byteAt(0);
              let b = encoded.byteAt(1);
              let c = encoded.byteAt(2);
              let d = encoded.byteAt(3);
              let e = encoded.byteAt(4);
              let f = encoded.byteAt(5);
              let g = encoded.byteAt(6);
              let h = encoded.byteAt(7);
              let rest = bitArraySlice(encoded, 64);
              return toBitArray([
                sizedInt(num(a), 5, true),
                sizedInt(num(b), 5, true),
                sizedInt(num(c), 5, true),
                sizedInt(num(d), 5, true),
                sizedInt(num(e), 5, true),
                sizedInt(num(f), 5, true),
                sizedInt(num(g), 5, true),
                sizedInt(num(h), 5, true),
                do_decode(rest)
              ]);
            } else {
              throw makeError("panic", FILEPATH, "multiformats/base32", 64, "do_decode", "Invalid base32 string", {});
            }
          } else {
            throw makeError("panic", FILEPATH, "multiformats/base32", 64, "do_decode", "Invalid base32 string", {});
          }
        } else {
          throw makeError("panic", FILEPATH, "multiformats/base32", 64, "do_decode", "Invalid base32 string", {});
        }
      } else {
        throw makeError("panic", FILEPATH, "multiformats/base32", 64, "do_decode", "Invalid base32 string", {});
      }
    } else {
      throw makeError("panic", FILEPATH, "multiformats/base32", 64, "do_decode", "Invalid base32 string", {});
    }
  } else {
    throw makeError("panic", FILEPATH, "multiformats/base32", 64, "do_decode", "Invalid base32 string", {});
  }
}
function decode(encoded) {
  return do_decode(bit_array_from_string(encoded));
}
function char(n) {
  let n$1 = n;
  if (n$1 >= 0 && n$1 <= 25) {
    return n$1 + 65;
  } else {
    let n$2 = n;
    if (n$2 >= 26 && n$2 <= 31) {
      return n$2 + 24;
    } else {
      throw makeError("panic", FILEPATH, "multiformats/base32", 87, "char", "`panic` expression evaluated.", {});
    }
  }
}
function do_encode(input) {
  if (input.bitSize === 0) {
    return toBitArray([]);
  } else if (input.bitSize >= 5) {
    if (input.bitSize === 8) {
      let a = bitArraySliceToInt(input, 0, 5, true, false);
      let b = bitArraySliceToInt(input, 5, 8, true, false);
      return toBitArray([char(a), char(b * 4), stringBits("======")]);
    } else if (input.bitSize >= 10 && input.bitSize >= 15) {
      if (input.bitSize === 16) {
        let a = bitArraySliceToInt(input, 0, 5, true, false);
        let b = bitArraySliceToInt(input, 5, 10, true, false);
        let c = bitArraySliceToInt(input, 10, 15, true, false);
        let d = bitArraySliceToInt(input, 15, 16, true, false);
        return toBitArray([
          char(a),
          char(b),
          char(c),
          char(d * 16),
          stringBits("====")
        ]);
      } else if (input.bitSize >= 20) {
        if (input.bitSize === 24) {
          let a = bitArraySliceToInt(input, 0, 5, true, false);
          let b = bitArraySliceToInt(input, 5, 10, true, false);
          let c = bitArraySliceToInt(input, 10, 15, true, false);
          let d = bitArraySliceToInt(input, 15, 20, true, false);
          let e = bitArraySliceToInt(input, 20, 24, true, false);
          return toBitArray([
            char(a),
            char(b),
            char(c),
            char(d),
            char(e * 2),
            stringBits("===")
          ]);
        } else if (input.bitSize >= 25 && input.bitSize >= 30) {
          if (input.bitSize === 32) {
            let a = bitArraySliceToInt(input, 0, 5, true, false);
            let b = bitArraySliceToInt(input, 5, 10, true, false);
            let c = bitArraySliceToInt(input, 10, 15, true, false);
            let d = bitArraySliceToInt(input, 15, 20, true, false);
            let e = bitArraySliceToInt(input, 20, 25, true, false);
            let f = bitArraySliceToInt(input, 25, 30, true, false);
            let g = bitArraySliceToInt(input, 30, 32, true, false);
            return toBitArray([
              char(a),
              char(b),
              char(c),
              char(d),
              char(e),
              char(f),
              char(g * 8),
              stringBits("=")
            ]);
          } else if (input.bitSize >= 35 && input.bitSize >= 40) {
            let a = bitArraySliceToInt(input, 0, 5, true, false);
            let b = bitArraySliceToInt(input, 5, 10, true, false);
            let c = bitArraySliceToInt(input, 10, 15, true, false);
            let d = bitArraySliceToInt(input, 15, 20, true, false);
            let e = bitArraySliceToInt(input, 20, 25, true, false);
            let f = bitArraySliceToInt(input, 25, 30, true, false);
            let g = bitArraySliceToInt(input, 30, 35, true, false);
            let h = bitArraySliceToInt(input, 35, 40, true, false);
            let rest = bitArraySlice(input, 40);
            return toBitArray([
              char(a),
              char(b),
              char(c),
              char(d),
              char(e),
              char(f),
              char(g),
              char(h),
              do_encode(rest)
            ]);
          } else {
            throw makeError("panic", FILEPATH, "multiformats/base32", 131, "do_encode", "`panic` expression evaluated.", {});
          }
        } else {
          throw makeError("panic", FILEPATH, "multiformats/base32", 131, "do_encode", "`panic` expression evaluated.", {});
        }
      } else {
        throw makeError("panic", FILEPATH, "multiformats/base32", 131, "do_encode", "`panic` expression evaluated.", {});
      }
    } else {
      throw makeError("panic", FILEPATH, "multiformats/base32", 131, "do_encode", "`panic` expression evaluated.", {});
    }
  } else {
    throw makeError("panic", FILEPATH, "multiformats/base32", 131, "do_encode", "`panic` expression evaluated.", {});
  }
}
function encode(input) {
  let $ = bit_array_to_string(do_encode(input));
  let out;
  if ($ instanceof Ok) {
    out = $[0];
  } else {
    throw makeError("let_assert", FILEPATH, "multiformats/base32", 79, "encode", "Pattern match failed, no pattern matched the value.", {
      value: $,
      start: 1641,
      end: 1699,
      pattern_start: 1652,
      pattern_end: 1659
    });
  }
  return out;
}

// build/dev/javascript/gleam_stdlib/gleam/bytes_tree.mjs
class Bytes extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class Text extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class Many extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
function concat3(trees) {
  return new Many(trees);
}
function new$() {
  return concat3(List$Empty$const);
}
function wrap_list(bits2) {
  return new Bytes(bits2);
}
function from_bit_array(bits2) {
  let _pipe = bits2;
  let _pipe$1 = pad_to_bytes(_pipe);
  return wrap_list(_pipe$1);
}
function append_tree(first, second) {
  if (second instanceof Bytes) {
    return new Many(prepend(first, prepend(second, List$Empty$const)));
  } else if (second instanceof Text) {
    return new Many(prepend(first, prepend(second, List$Empty$const)));
  } else {
    let trees = second[0];
    return new Many(prepend(first, trees));
  }
}
function append4(first, second) {
  return append_tree(first, from_bit_array(second));
}
function to_list2(loop$stack, loop$acc) {
  while (true) {
    let stack = loop$stack;
    let acc = loop$acc;
    if (stack instanceof Empty) {
      return acc;
    } else {
      let $ = stack.head;
      if ($ instanceof Empty) {
        let remaining_stack = stack.tail;
        loop$stack = remaining_stack;
        loop$acc = acc;
      } else {
        let $1 = $.head;
        if ($1 instanceof Bytes) {
          let remaining_stack = stack.tail;
          let rest = $.tail;
          let bits2 = $1[0];
          loop$stack = prepend(rest, remaining_stack);
          loop$acc = prepend(bits2, acc);
        } else if ($1 instanceof Text) {
          let remaining_stack = stack.tail;
          let rest = $.tail;
          let tree = $1[0];
          let bits2 = bit_array_from_string(identity(tree));
          loop$stack = prepend(rest, remaining_stack);
          loop$acc = prepend(bits2, acc);
        } else {
          let remaining_stack = stack.tail;
          let rest = $.tail;
          let trees = $1[0];
          loop$stack = prepend(trees, prepend(rest, remaining_stack));
          loop$acc = acc;
        }
      }
    }
  }
}
function to_bit_array(tree) {
  let _pipe = prepend(prepend(tree, List$Empty$const), List$Empty$const);
  let _pipe$1 = to_list2(_pipe, List$Empty$const);
  let _pipe$2 = reverse(_pipe$1);
  return bit_array_concat(_pipe$2);
}
// build/dev/javascript/gleb128/gleb128.mjs
function do_encode_unsigned(loop$value, loop$builder) {
  while (true) {
    let value = loop$value;
    let builder = loop$builder;
    let $ = value >= 0;
    if ($) {
      let current_chunk = bitwise_and(value, 127);
      let next_chunk = bitwise_shift_right(value, 7);
      if (next_chunk === 0) {
        return new Ok(append4(builder, toBitArray([current_chunk])));
      } else {
        let current_chunk$1 = bitwise_or(current_chunk, 128);
        loop$value = next_chunk;
        loop$builder = append4(builder, toBitArray([current_chunk$1]));
      }
    } else {
      return new Error2(undefined);
    }
  }
}
function do_decode_unsigned(loop$data, loop$position_accumulator, loop$result_accumulator, loop$shift_accumulator) {
  while (true) {
    let data = loop$data;
    let position_accumulator = loop$position_accumulator;
    let result_accumulator = loop$result_accumulator;
    let shift_accumulator = loop$shift_accumulator;
    let $ = bit_array_slice(data, position_accumulator, 1);
    if ($ instanceof Ok) {
      let slice2 = $[0];
      if (slice2.bitSize === 8) {
        let byte = slice2.byteAt(0);
        let current_chunk = bitwise_and(byte, 127);
        let current_chunk$1 = bitwise_shift_left(current_chunk, shift_accumulator);
        let result_accumulator$1 = bitwise_or(result_accumulator, current_chunk$1);
        let next_chunk = bitwise_shift_right(byte, 7);
        if (next_chunk === 0) {
          return new Ok([result_accumulator$1, position_accumulator + 1]);
        } else {
          loop$data = data;
          loop$position_accumulator = position_accumulator + 1;
          loop$result_accumulator = result_accumulator$1;
          loop$shift_accumulator = shift_accumulator + 7;
        }
      } else {
        return new Error2(undefined);
      }
    } else {
      return new Error2(undefined);
    }
  }
}
function do_fast_decode_unsigned(loop$data, loop$position_accumulator, loop$result_accumulator, loop$shift_accumulator) {
  while (true) {
    let data = loop$data;
    let position_accumulator = loop$position_accumulator;
    let result_accumulator = loop$result_accumulator;
    let shift_accumulator = loop$shift_accumulator;
    let byte = bitwise_shift_right(data, 8 * position_accumulator);
    let byte$1 = bitwise_and(byte, 255);
    let current_chunk = bitwise_and(byte$1, 127);
    let current_chunk$1 = bitwise_shift_left(current_chunk, shift_accumulator);
    let result_accumulator$1 = bitwise_or(result_accumulator, current_chunk$1);
    let next_chunk = bitwise_shift_right(byte$1, 7);
    if (next_chunk === 0) {
      return new Ok([result_accumulator$1, position_accumulator + 1]);
    } else {
      loop$data = data;
      loop$position_accumulator = position_accumulator + 1;
      loop$result_accumulator = result_accumulator$1;
      loop$shift_accumulator = shift_accumulator + 7;
    }
  }
}
function encode_unsigned(value) {
  let $ = do_encode_unsigned(value, new$());
  if ($ instanceof Ok) {
    let result = $[0];
    return new Ok(to_bit_array(result));
  } else {
    return $;
  }
}
function decode_unsigned(data) {
  let $ = bit_array_byte_size(data);
  let size2 = $;
  if (size2 <= 8) {
    let $1 = bit_array_slice(toBitArray([data, sizedInt(0, 64, true)]), 0, 8);
    if ($1 instanceof Ok) {
      let $2 = $1[0];
      if ($2.bitSize === 64) {
        let value = bitArraySliceToInt($2, 0, 64, false, false);
        return do_fast_decode_unsigned(value, 0, 0, 0);
      } else {
        return new Error2(undefined);
      }
    } else {
      return new Error2(undefined);
    }
  } else {
    return do_decode_unsigned(data, 0, 0, 0);
  }
}

// build/dev/javascript/multiformats/multiformats/leb128.mjs
var FILEPATH2 = "src/multiformats/leb128.gleam";
function decode2(buffer) {
  let $ = decode_unsigned(buffer);
  if ($ instanceof Ok) {
    let value = $[0][0];
    let consumed = $[0][1];
    let rest;
    if (consumed * 8 >= 0 && buffer.bitSize >= consumed * 8 && (buffer.bitSize - consumed * 8) % 8 === 0) {
      rest = bitArraySlice(buffer, consumed * 8);
    } else {
      throw makeError("let_assert", FILEPATH2, "multiformats/leb128", 7, "decode", "Pattern match failed, no pattern matched the value.", {
        value: buffer,
        start: 138,
        end: 196,
        pattern_start: 149,
        pattern_end: 187
      });
    }
    return new Ok([value, rest]);
  } else {
    return new Error2(undefined);
  }
}
function encode2(int3) {
  return encode_unsigned(int3);
}

// build/dev/javascript/multiformats/multiformats/hashes.mjs
var FILEPATH3 = "src/multiformats/hashes.gleam";

class Multihash extends CustomType {
  constructor(algorithm, digest) {
    super();
    this.algorithm = algorithm;
    this.digest = digest;
  }
}
class Sha256 extends CustomType {
}
var Algorithm$Sha256$const = new Sha256;
function code(algorithm) {
  return 18;
}
function from_code(code2) {
  if (code2 === 18) {
    return new Ok(Algorithm$Sha256$const);
  } else {
    return new Error2(undefined);
  }
}
function decode3(buffer) {
  return try$(decode2(buffer), (_use0) => {
    let code$1 = _use0[0];
    let buffer$1 = _use0[1];
    return try$(from_code(code$1), (algorithm) => {
      return try$(decode2(buffer$1), (_use02) => {
        let length3 = _use02[0];
        let buffer$2 = _use02[1];
        if (length3 * 8 >= 0 && buffer$2.bitSize >= length3 * 8 && (buffer$2.bitSize - length3 * 8) % 8 === 0) {
          let digest = bitArraySlice(buffer$2, 0, length3 * 8);
          let rest = bitArraySlice(buffer$2, length3 * 8);
          return new Ok([new Multihash(algorithm, digest), rest]);
        } else {
          return new Error2(undefined);
        }
      });
    });
  });
}
function encode3(hash) {
  let algorithm = hash.algorithm;
  let digest = hash.digest;
  let code$1 = code(algorithm);
  let $ = encode2(code$1);
  let code$2;
  if ($ instanceof Ok) {
    code$2 = $[0];
  } else {
    throw makeError("let_assert", FILEPATH3, "multiformats/hashes", 47, "encode", "Pattern match failed, no pattern matched the value.", { value: $, start: 858, end: 899, pattern_start: 869, pattern_end: 877 });
  }
  let $1 = encode2(bit_array_byte_size(digest));
  let length3;
  if ($1 instanceof Ok) {
    length3 = $1[0];
  } else {
    throw makeError("let_assert", FILEPATH3, "multiformats/hashes", 49, "encode", "Pattern match failed, no pattern matched the value.", { value: $1, start: 933, end: 999, pattern_start: 944, pattern_end: 954 });
  }
  return toBitArray([code$2, length3, digest]);
}

// build/dev/javascript/multiformats/multiformats/cid/v1.mjs
var FILEPATH4 = "src/multiformats/cid/v1.gleam";

class Cid extends CustomType {
  constructor(content_type, content) {
    super();
    this.content_type = content_type;
    this.content = content;
  }
}
function to_bytes(cid) {
  let content_type = cid.content_type;
  let content = cid.content;
  let $ = encode2(1);
  let cid_version;
  if ($ instanceof Ok) {
    cid_version = $[0];
  } else {
    throw makeError("let_assert", FILEPATH4, "multiformats/cid/v1", 15, "to_bytes", "Pattern match failed, no pattern matched the value.", { value: $, start: 335, end: 380, pattern_start: 346, pattern_end: 361 });
  }
  let $1 = encode2(max(content_type, 0));
  let content_type$1;
  if ($1 instanceof Ok) {
    content_type$1 = $1[0];
  } else {
    throw makeError("let_assert", FILEPATH4, "multiformats/cid/v1", 18, "to_bytes", "Pattern match failed, no pattern matched the value.", { value: $1, start: 536, end: 605, pattern_start: 547, pattern_end: 563 });
  }
  let content$1 = encode3(content);
  return toBitArray([cid_version, content_type$1, content$1]);
}
function to_string2(cid) {
  let bytes = to_bytes(cid);
  let _block;
  let _pipe = encode(bytes);
  let _pipe$1 = lowercase(_pipe);
  _block = replace(_pipe$1, "=", "");
  let encoded = _block;
  return "b" + encoded;
}
function from_bytes(cid) {
  if (cid.bitSize >= 8 && cid.byteAt(0) === 12 && cid.bitSize >= 16 && cid.byteAt(1) === 20 && cid.bitSize === 272) {
    return new Error2("V0 cid");
  } else {
    let buffer = cid;
    return try$((() => {
      let _pipe = decode2(buffer);
      return replace_error(_pipe, "Failed to decode CID version");
    })(), (_use0) => {
      let version = _use0[0];
      let buffer$1 = _use0[1];
      return try$((() => {
        let $ = version === 1;
        if ($) {
          return new Ok(undefined);
        } else {
          return new Error2("not a version 1 CID");
        }
      })(), (_use02) => {
        return try$((() => {
          let _pipe = decode2(buffer$1);
          return replace_error(_pipe, "Failed to decode content-type");
        })(), (_use03) => {
          let content_type = _use03[0];
          let buffer$2 = _use03[1];
          return try$((() => {
            let _pipe = decode3(buffer$2);
            return replace_error(_pipe, "Failed to decoded content hash");
          })(), (_use04) => {
            let multihash = _use04[0];
            let buffer$3 = _use04[1];
            return new Ok([new Cid(content_type, multihash), buffer$3]);
          });
        });
      });
    });
  }
}
function from_string(cid) {
  return try$((() => {
    if (cid.startsWith("Qm")) {
      let $ = byte_size(cid) === 46;
      if ($) {
        return new Error2(" Decode V0 cid as base58btc and continue to step 2.");
      } else {
        return new Error2("not v0 but also not a known encoding");
      }
    } else if (cid.charCodeAt(0) === 98) {
      let rest = cid.slice(1);
      return new Ok(decode(rest));
    } else {
      return new Error2("unsuppoted multibase encoding");
    }
  })(), (decoded) => {
    return from_bytes(decoded);
  });
}
// build/dev/javascript/eyg_ir/eyg/ir/tree.mjs
class Variable extends CustomType {
  constructor(label) {
    super();
    this.label = label;
  }
}
class Lambda extends CustomType {
  constructor(label, body) {
    super();
    this.label = label;
    this.body = body;
  }
}
class Apply extends CustomType {
  constructor(func, argument) {
    super();
    this.func = func;
    this.argument = argument;
  }
}
class Let extends CustomType {
  constructor(label, definition, body) {
    super();
    this.label = label;
    this.definition = definition;
    this.body = body;
  }
}
class Binary extends CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}
class Integer extends CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}
class String2 extends CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}
class Tail extends CustomType {
}
var Expression$Tail$const = new Tail;
class Cons extends CustomType {
}
var Expression$Cons$const = new Cons;
class Vacant extends CustomType {
}
var Expression$Vacant$const = new Vacant;
class Empty2 extends CustomType {
}
var Expression$Empty$const = new Empty2;
class Extend extends CustomType {
  constructor(label) {
    super();
    this.label = label;
  }
}
class Select extends CustomType {
  constructor(label) {
    super();
    this.label = label;
  }
}
class Overwrite extends CustomType {
  constructor(label) {
    super();
    this.label = label;
  }
}
class Tag extends CustomType {
  constructor(label) {
    super();
    this.label = label;
  }
}
class Case extends CustomType {
  constructor(label) {
    super();
    this.label = label;
  }
}
class NoCases extends CustomType {
}
var Expression$NoCases$const = new NoCases;
class Perform extends CustomType {
  constructor(label) {
    super();
    this.label = label;
  }
}
class Handle extends CustomType {
  constructor(label) {
    super();
    this.label = label;
  }
}
class Builtin extends CustomType {
  constructor(identifier) {
    super();
    this.identifier = identifier;
  }
}
class Reference extends CustomType {
  constructor(reference) {
    super();
    this.reference = reference;
  }
}
class Content extends CustomType {
  constructor(cid) {
    super();
    this.cid = cid;
  }
}
class Package extends CustomType {
  constructor(package$) {
    super();
    this.package = package$;
  }
}
class Version extends CustomType {
  constructor(package$, version) {
    super();
    this.package = package$;
    this.version = version;
  }
}
class Pinned extends CustomType {
  constructor(release) {
    super();
    this.release = release;
  }
}
class Relative extends CustomType {
  constructor(location) {
    super();
    this.location = location;
  }
}
class Release extends CustomType {
  constructor(package$, version, module) {
    super();
    this.package = package$;
    this.version = version;
    this.module = module;
  }
}
function map_children(exp2, f) {
  if (exp2 instanceof Variable) {
    let label = exp2.label;
    return return$(new Variable(label));
  } else if (exp2 instanceof Lambda) {
    let parameter = exp2.label;
    let body = exp2.body;
    return then$(f(body), (body2) => {
      return return$(new Lambda(parameter, body2));
    });
  } else if (exp2 instanceof Apply) {
    let function$ = exp2.func;
    let argument = exp2.argument;
    return then$(f(function$), (function$2) => {
      return then$(f(argument), (argument2) => {
        return return$(new Apply(function$2, argument2));
      });
    });
  } else if (exp2 instanceof Let) {
    let label = exp2.label;
    let definition = exp2.definition;
    let body = exp2.body;
    return then$(f(definition), (definition2) => {
      return then$(f(body), (body2) => {
        return return$(new Let(label, definition2, body2));
      });
    });
  } else if (exp2 instanceof Binary) {
    let value = exp2.value;
    return return$(new Binary(value));
  } else if (exp2 instanceof Integer) {
    let value = exp2.value;
    return return$(new Integer(value));
  } else if (exp2 instanceof String2) {
    let value = exp2.value;
    return return$(new String2(value));
  } else if (exp2 instanceof Tail) {
    return return$(Expression$Tail$const);
  } else if (exp2 instanceof Cons) {
    return return$(Expression$Cons$const);
  } else if (exp2 instanceof Vacant) {
    return return$(Expression$Vacant$const);
  } else if (exp2 instanceof Empty2) {
    return return$(Expression$Empty$const);
  } else if (exp2 instanceof Extend) {
    let label = exp2.label;
    return return$(new Extend(label));
  } else if (exp2 instanceof Select) {
    let label = exp2.label;
    return return$(new Select(label));
  } else if (exp2 instanceof Overwrite) {
    let label = exp2.label;
    return return$(new Overwrite(label));
  } else if (exp2 instanceof Tag) {
    let label = exp2.label;
    return return$(new Tag(label));
  } else if (exp2 instanceof Case) {
    let label = exp2.label;
    return return$(new Case(label));
  } else if (exp2 instanceof NoCases) {
    return return$(Expression$NoCases$const);
  } else if (exp2 instanceof Perform) {
    let label = exp2.label;
    return return$(new Perform(label));
  } else if (exp2 instanceof Handle) {
    let label = exp2.label;
    return return$(new Handle(label));
  } else if (exp2 instanceof Builtin) {
    let identifier = exp2.identifier;
    return return$(new Builtin(identifier));
  } else {
    let reference$1 = exp2.reference;
    return return$(new Reference(reference$1));
  }
}
function rewrite(node, f) {
  let recur = (child) => {
    return rewrite(child, f);
  };
  let exp2 = node[0];
  let meta = node[1];
  return then$(map_children(exp2, recur), (rebuilt) => {
    return f([rebuilt, meta]);
  });
}
function rewrite_meta(node, f) {
  return rewrite(node, (node2) => {
    let exp2 = node2[0];
    let meta = node2[1];
    return then$(f(meta), (meta2) => {
      return return$([exp2, meta2]);
    });
  });
}
function map_annotation(in$, f) {
  return rewrite_meta(in$, (m) => {
    return return$(f(m));
  })((x) => {
    return x;
  });
}

// build/dev/javascript/gleam_stdlib/gleam/set.mjs
class Set2 extends CustomType {
  constructor(dict3) {
    super();
    this.dict = dict3;
  }
}
var token = undefined;
function new$2() {
  return new Set2(make());
}
function insert2(set, member) {
  return new Set2(insert(set.dict, member, token));
}
function contains2(set, member) {
  let _pipe = set.dict;
  let _pipe$1 = get(_pipe, member);
  return is_ok(_pipe$1);
}
function from_list2(members) {
  let dict3 = fold2(members, make(), (m, k) => {
    return insert(m, k, token);
  });
  return new Set2(dict3);
}
function fold3(set, initial, reducer) {
  return fold(set.dict, initial, (a, k, _) => {
    return reducer(a, k);
  });
}
function order(first, second) {
  let $ = size(first.dict) > size(second.dict);
  if ($) {
    return [first, second];
  } else {
    return [second, first];
  }
}
function union(first, second) {
  let $ = order(first, second);
  let larger = $[0];
  let smaller = $[1];
  return fold3(smaller, larger, insert2);
}
// build/dev/javascript/eyg_analysis/eyg/analysis/type_/isomorphic.mjs
class Var extends CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
class Fun extends CustomType {
  constructor($0, $1, $2) {
    super();
    this[0] = $0;
    this[1] = $1;
    this[2] = $2;
  }
}
class Binary2 extends CustomType {
}
var Type$Binary$const = new Binary2;
class Integer2 extends CustomType {
}
var Type$Integer$const = new Integer2;
class String3 extends CustomType {
}
var Type$String$const = new String3;
class List2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Record extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Union extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Empty3 extends CustomType {
}
var Type$Empty$const = new Empty3;
class RowExtend extends CustomType {
  constructor($0, $1, $2) {
    super();
    this[0] = $0;
    this[1] = $1;
    this[2] = $2;
  }
}
class EffectExtend extends CustomType {
  constructor($0, $1, $2) {
    super();
    this[0] = $0;
    this[1] = $1;
    this[2] = $2;
  }
}
class Never extends CustomType {
}
var Type$Never$const = new Never;
class Promise2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
var unit = /* @__PURE__ */ new Record(Type$Empty$const);
var boolean = /* @__PURE__ */ new Union(/* @__PURE__ */ new RowExtend("True", unit, /* @__PURE__ */ new RowExtend("False", unit, Type$Empty$const)));
function do_rows(rows, tail) {
  return fold2(reverse(rows), tail, (tail2, row) => {
    let label = row[0];
    let value = row[1];
    return new RowExtend(label, value, tail2);
  });
}
function rows(rows2) {
  return do_rows(rows2, Type$Empty$const);
}
function record(fields) {
  return new Record(rows(fields));
}
function union2(fields) {
  return new Union(rows(fields));
}
function result(value, reason) {
  return new Union(new RowExtend("Ok", value, new RowExtend("Error", reason, Type$Empty$const)));
}
function option(value) {
  return new Union(new RowExtend("Some", value, new RowExtend("None", unit, Type$Empty$const)));
}
function reference() {
  return union2(prepend(["Content", Type$String$const], prepend(["Package", Type$String$const], prepend([
    "Version",
    record(prepend(["package", Type$String$const], prepend(["version", Type$Integer$const], List$Empty$const)))
  ], prepend([
    "Pinned",
    record(prepend(["package", Type$String$const], prepend(["version", Type$Integer$const], prepend(["cid", Type$String$const], List$Empty$const))))
  ], prepend(["Relative", Type$String$const], List$Empty$const))))));
}
function ast() {
  return new List2(union2(toList([
    ["Variable", Type$String$const],
    ["Lambda", Type$String$const],
    ["Apply", unit],
    ["Let", Type$String$const],
    ["Binary", Type$Binary$const],
    ["Integer", Type$Integer$const],
    ["String", Type$String$const],
    ["Tail", unit],
    ["Cons", unit],
    ["Vacant", unit],
    ["Empty", unit],
    ["Extend", Type$String$const],
    ["Select", Type$String$const],
    ["Overwrite", Type$String$const],
    ["Tag", Type$String$const],
    ["Case", Type$String$const],
    ["NoCases", unit],
    ["Perform", Type$String$const],
    ["Handle", Type$String$const],
    ["Builtin", Type$String$const],
    ["Reference", reference()]
  ])));
}

// build/dev/javascript/eyg_analysis/eyg/analysis/type_/binding.mjs
var FILEPATH5 = "src/eyg/analysis/type_/binding.gleam";

class Bound extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Unbound extends CustomType {
  constructor(level) {
    super();
    this.level = level;
  }
}
function new$3(level, bindings) {
  let i = size(bindings);
  let bindings$1 = insert(bindings, i, new Unbound(level));
  return [i, bindings$1];
}
function mono(level, bindings) {
  let $ = new$3(level, bindings);
  let i = $[0];
  let bindings$1 = $[1];
  return [new Var(i), bindings$1];
}
function resolve(loop$type_, loop$bindings) {
  while (true) {
    let type_ = loop$type_;
    let bindings = loop$bindings;
    if (type_ instanceof Var) {
      let i = type_.key;
      let $ = get(bindings, i);
      let binding;
      if ($ instanceof Ok) {
        binding = $[0];
      } else {
        throw makeError("let_assert", FILEPATH5, "eyg/analysis/type_/binding", 30, "resolve", "Pattern match failed, no pattern matched the value.", {
          value: $,
          start: 537,
          end: 583,
          pattern_start: 548,
          pattern_end: 559
        });
      }
      if (binding instanceof Bound) {
        let type_$1 = binding[0];
        loop$type_ = type_$1;
        loop$bindings = bindings;
      } else {
        return type_;
      }
    } else if (type_ instanceof Fun) {
      let arg = type_[0];
      let eff = type_[1];
      let ret = type_[2];
      return new Fun(resolve(arg, bindings), resolve(eff, bindings), resolve(ret, bindings));
    } else if (type_ instanceof Binary2) {
      return type_;
    } else if (type_ instanceof Integer2) {
      return type_;
    } else if (type_ instanceof String3) {
      return type_;
    } else if (type_ instanceof List2) {
      let el = type_[0];
      return new List2(resolve(el, bindings));
    } else if (type_ instanceof Record) {
      let rows2 = type_[0];
      return new Record(resolve(rows2, bindings));
    } else if (type_ instanceof Union) {
      let rows2 = type_[0];
      return new Union(resolve(rows2, bindings));
    } else if (type_ instanceof Empty3) {
      return type_;
    } else if (type_ instanceof RowExtend) {
      let label = type_[0];
      let field2 = type_[1];
      let rest = type_[2];
      return new RowExtend(label, resolve(field2, bindings), resolve(rest, bindings));
    } else if (type_ instanceof EffectExtend) {
      let label = type_[0];
      let rest = type_[2];
      let lift = type_[1][0];
      let reply = type_[1][1];
      return new EffectExtend(label, [resolve(lift, bindings), resolve(reply, bindings)], resolve(rest, bindings));
    } else if (type_ instanceof Never) {
      return type_;
    } else {
      let inner = type_[0];
      return new Promise2(resolve(inner, bindings));
    }
  }
}
function gen(loop$type_, loop$level, loop$bindings) {
  while (true) {
    let type_ = loop$type_;
    let level = loop$level;
    let bindings = loop$bindings;
    if (type_ instanceof Var) {
      let i = type_.key;
      let $ = get(bindings, i);
      let binding;
      if ($ instanceof Ok) {
        binding = $[0];
      } else {
        throw makeError("let_assert", FILEPATH5, "eyg/analysis/type_/binding", 70, "gen", "Pattern match failed, no pattern matched the value.", {
          value: $,
          start: 1674,
          end: 1720,
          pattern_start: 1685,
          pattern_end: 1696
        });
      }
      if (binding instanceof Bound) {
        let t = binding[0];
        loop$type_ = t;
        loop$level = level;
        loop$bindings = bindings;
      } else {
        let l = binding.level;
        let $1 = l > level;
        if ($1) {
          return new Var([true, i]);
        } else {
          return new Var([false, i]);
        }
      }
    } else if (type_ instanceof Fun) {
      let arg = type_[0];
      let eff = type_[1];
      let ret = type_[2];
      let arg$1 = gen(arg, level, bindings);
      let eff$1 = gen(eff, level, bindings);
      let ret$1 = gen(ret, level, bindings);
      return new Fun(arg$1, eff$1, ret$1);
    } else if (type_ instanceof Binary2) {
      return type_;
    } else if (type_ instanceof Integer2) {
      return type_;
    } else if (type_ instanceof String3) {
      return type_;
    } else if (type_ instanceof List2) {
      let el = type_[0];
      return new List2(gen(el, level, bindings));
    } else if (type_ instanceof Record) {
      let rows2 = type_[0];
      return new Record(gen(rows2, level, bindings));
    } else if (type_ instanceof Union) {
      let rows2 = type_[0];
      return new Union(gen(rows2, level, bindings));
    } else if (type_ instanceof Empty3) {
      return type_;
    } else if (type_ instanceof RowExtend) {
      let label = type_[0];
      let field2 = type_[1];
      let rest = type_[2];
      let field$1 = gen(field2, level, bindings);
      let rest$1 = gen(rest, level, bindings);
      return new RowExtend(label, field$1, rest$1);
    } else if (type_ instanceof EffectExtend) {
      let label = type_[0];
      let rest = type_[2];
      let lift = type_[1][0];
      let reply = type_[1][1];
      let lift$1 = gen(lift, level, bindings);
      let reply$1 = gen(reply, level, bindings);
      let rest$1 = gen(rest, level, bindings);
      return new EffectExtend(label, [lift$1, reply$1], rest$1);
    } else if (type_ instanceof Never) {
      return type_;
    } else {
      let inner = type_[0];
      return new Promise2(gen(inner, level, bindings));
    }
  }
}
function do_inst(poly, level, bindings, subs) {
  if (poly instanceof Var) {
    if (poly.key[0]) {
      let i = poly.key[1];
      let $ = get(subs, i);
      if ($ instanceof Ok) {
        let tv = $[0];
        return [tv, bindings, subs];
      } else {
        let $1 = mono(level, bindings);
        let tv = $1[0];
        let bindings$1 = $1[1];
        let subs$1 = insert(subs, i, tv);
        return [tv, bindings$1, subs$1];
      }
    } else {
      let i = poly.key[1];
      return [new Var(i), bindings, subs];
    }
  } else if (poly instanceof Fun) {
    let arg = poly[0];
    let eff = poly[1];
    let ret = poly[2];
    let $ = do_inst(arg, level, bindings, subs);
    let arg$1 = $[0];
    let bindings$1 = $[1];
    let subs$1 = $[2];
    let $1 = do_inst(eff, level, bindings$1, subs$1);
    let eff$1 = $1[0];
    let bindings$2 = $1[1];
    let subs$2 = $1[2];
    let $2 = do_inst(ret, level, bindings$2, subs$2);
    let ret$1 = $2[0];
    let bindings$3 = $2[1];
    let subs$3 = $2[2];
    return [new Fun(arg$1, eff$1, ret$1), bindings$3, subs$3];
  } else if (poly instanceof Binary2) {
    return [Type$Binary$const, bindings, subs];
  } else if (poly instanceof Integer2) {
    return [Type$Integer$const, bindings, subs];
  } else if (poly instanceof String3) {
    return [Type$String$const, bindings, subs];
  } else if (poly instanceof List2) {
    let el = poly[0];
    let $ = do_inst(el, level, bindings, subs);
    let el$1 = $[0];
    let bindings$1 = $[1];
    let subs$1 = $[2];
    return [new List2(el$1), bindings$1, subs$1];
  } else if (poly instanceof Record) {
    let rows2 = poly[0];
    let $ = do_inst(rows2, level, bindings, subs);
    let rows$1 = $[0];
    let bindings$1 = $[1];
    let subs$1 = $[2];
    return [new Record(rows$1), bindings$1, subs$1];
  } else if (poly instanceof Union) {
    let rows2 = poly[0];
    let $ = do_inst(rows2, level, bindings, subs);
    let rows$1 = $[0];
    let bindings$1 = $[1];
    let subs$1 = $[2];
    return [new Union(rows$1), bindings$1, subs$1];
  } else if (poly instanceof Empty3) {
    return [Type$Empty$const, bindings, subs];
  } else if (poly instanceof RowExtend) {
    let label = poly[0];
    let field2 = poly[1];
    let rest = poly[2];
    let $ = do_inst(field2, level, bindings, subs);
    let field$1 = $[0];
    let bindings$1 = $[1];
    let subs$1 = $[2];
    let $1 = do_inst(rest, level, bindings$1, subs$1);
    let rest$1 = $1[0];
    let bindings$2 = $1[1];
    let subs$2 = $1[2];
    return [new RowExtend(label, field$1, rest$1), bindings$2, subs$2];
  } else if (poly instanceof EffectExtend) {
    let label = poly[0];
    let rest = poly[2];
    let lift = poly[1][0];
    let reply = poly[1][1];
    let $ = do_inst(lift, level, bindings, subs);
    let lift$1 = $[0];
    let bindings$1 = $[1];
    let subs$1 = $[2];
    let $1 = do_inst(reply, level, bindings$1, subs$1);
    let reply$1 = $1[0];
    let bindings$2 = $1[1];
    let subs$2 = $1[2];
    let $2 = do_inst(rest, level, bindings$2, subs$2);
    let rest$1 = $2[0];
    let bindings$3 = $2[1];
    let subs$3 = $2[2];
    return [
      new EffectExtend(label, [lift$1, reply$1], rest$1),
      bindings$3,
      subs$3
    ];
  } else if (poly instanceof Never) {
    return [Type$Never$const, bindings, subs];
  } else {
    let inner = poly[0];
    let $ = do_inst(inner, level, bindings, subs);
    let inner$1 = $[0];
    let bindings$1 = $[1];
    let subs$1 = $[2];
    return [new Promise2(inner$1), bindings$1, subs$1];
  }
}
function instantiate(poly, level, bindings) {
  let $ = do_inst(poly, level, bindings, make());
  let mono$1 = $[0];
  let bindings$1 = $[1];
  return [mono$1, bindings$1];
}

// build/dev/javascript/eyg_analysis/eyg/analysis/type_/binding/error.mjs
class Todo extends CustomType {
}
var Reason$Todo$const = new Todo;
class MissingVariable extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class MissingBuiltin extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class MissingReference extends CustomType {
  constructor(reference2) {
    super();
    this.reference = reference2;
  }
}
class TypeMismatch extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class MissingRow extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Recursive extends CustomType {
}
var Reason$Recursive$const = new Recursive;
class SameTail extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}

// build/dev/javascript/eyg_analysis/eyg/analysis/type_/binding/unify.mjs
var FILEPATH6 = "src/eyg/analysis/type_/binding/unify.gleam";
function rewrite_effect(loop$required, loop$type_, loop$level, loop$bindings, loop$check) {
  while (true) {
    let required = loop$required;
    let type_ = loop$type_;
    let level = loop$level;
    let bindings = loop$bindings;
    let check = loop$check;
    if (type_ instanceof Var) {
      let i = type_.key;
      let $ = get(bindings, i);
      if ($ instanceof Ok) {
        let $1 = $[0];
        if ($1 instanceof Bound) {
          let type_$1 = $1[0];
          loop$required = required;
          loop$type_ = type_$1;
          loop$level = level;
          loop$bindings = bindings;
          loop$check = check;
        } else {
          if (check instanceof Var) {
            let j = check.key;
            if (i === j) {
              console_log("same effect tails");
              return new Error2(new TypeMismatch(new Var(i), new Var(j)));
            } else {
              let $2 = mono(level, bindings);
              let lift = $2[0];
              let bindings$1 = $2[1];
              let $3 = mono(level, bindings$1);
              let reply = $3[0];
              let bindings$2 = $3[1];
              let $4 = get(bindings$2, i);
              let binding;
              if ($4 instanceof Ok) {
                binding = $4[0];
              } else {
                throw makeError("let_assert", FILEPATH6, "eyg/analysis/type_/binding/unify", 219, "rewrite_effect", "Pattern match failed, no pattern matched the value.", {
                  value: $4,
                  start: 8138,
                  end: 8184,
                  pattern_start: 8149,
                  pattern_end: 8160
                });
              }
              if (binding instanceof Bound) {
                let type_$1 = binding[0];
                loop$required = required;
                loop$type_ = type_$1;
                loop$level = level;
                loop$bindings = bindings$2;
                loop$check = check;
              } else {
                let level$1 = binding.level;
                let $5 = mono(level$1, bindings$2);
                let rest = $5[0];
                let bindings$3 = $5[1];
                let type_$1 = new EffectExtend(required, [lift, reply], rest);
                let bindings$4 = insert(bindings$3, i, new Bound(type_$1));
                return new Ok([[lift, reply], rest, bindings$4]);
              }
            }
          } else {
            let $2 = mono(level, bindings);
            let lift = $2[0];
            let bindings$1 = $2[1];
            let $3 = mono(level, bindings$1);
            let reply = $3[0];
            let bindings$2 = $3[1];
            let $4 = get(bindings$2, i);
            let binding;
            if ($4 instanceof Ok) {
              binding = $4[0];
            } else {
              throw makeError("let_assert", FILEPATH6, "eyg/analysis/type_/binding/unify", 219, "rewrite_effect", "Pattern match failed, no pattern matched the value.", {
                value: $4,
                start: 8138,
                end: 8184,
                pattern_start: 8149,
                pattern_end: 8160
              });
            }
            if (binding instanceof Bound) {
              let type_$1 = binding[0];
              loop$required = required;
              loop$type_ = type_$1;
              loop$level = level;
              loop$bindings = bindings$2;
              loop$check = check;
            } else {
              let level$1 = binding.level;
              let $5 = mono(level$1, bindings$2);
              let rest = $5[0];
              let bindings$3 = $5[1];
              let type_$1 = new EffectExtend(required, [lift, reply], rest);
              let bindings$4 = insert(bindings$3, i, new Bound(type_$1));
              return new Ok([[lift, reply], rest, bindings$4]);
            }
          }
        }
      } else {
        if (check instanceof Var) {
          let j = check.key;
          if (i === j) {
            console_log("same effect tails");
            return new Error2(new TypeMismatch(new Var(i), new Var(j)));
          } else {
            let $1 = mono(level, bindings);
            let lift = $1[0];
            let bindings$1 = $1[1];
            let $2 = mono(level, bindings$1);
            let reply = $2[0];
            let bindings$2 = $2[1];
            let $3 = get(bindings$2, i);
            let binding;
            if ($3 instanceof Ok) {
              binding = $3[0];
            } else {
              throw makeError("let_assert", FILEPATH6, "eyg/analysis/type_/binding/unify", 219, "rewrite_effect", "Pattern match failed, no pattern matched the value.", {
                value: $3,
                start: 8138,
                end: 8184,
                pattern_start: 8149,
                pattern_end: 8160
              });
            }
            if (binding instanceof Bound) {
              let type_$1 = binding[0];
              loop$required = required;
              loop$type_ = type_$1;
              loop$level = level;
              loop$bindings = bindings$2;
              loop$check = check;
            } else {
              let level$1 = binding.level;
              let $4 = mono(level$1, bindings$2);
              let rest = $4[0];
              let bindings$3 = $4[1];
              let type_$1 = new EffectExtend(required, [lift, reply], rest);
              let bindings$4 = insert(bindings$3, i, new Bound(type_$1));
              return new Ok([[lift, reply], rest, bindings$4]);
            }
          }
        } else {
          let $1 = mono(level, bindings);
          let lift = $1[0];
          let bindings$1 = $1[1];
          let $2 = mono(level, bindings$1);
          let reply = $2[0];
          let bindings$2 = $2[1];
          let $3 = get(bindings$2, i);
          let binding;
          if ($3 instanceof Ok) {
            binding = $3[0];
          } else {
            throw makeError("let_assert", FILEPATH6, "eyg/analysis/type_/binding/unify", 219, "rewrite_effect", "Pattern match failed, no pattern matched the value.", {
              value: $3,
              start: 8138,
              end: 8184,
              pattern_start: 8149,
              pattern_end: 8160
            });
          }
          if (binding instanceof Bound) {
            let type_$1 = binding[0];
            loop$required = required;
            loop$type_ = type_$1;
            loop$level = level;
            loop$bindings = bindings$2;
            loop$check = check;
          } else {
            let level$1 = binding.level;
            let $4 = mono(level$1, bindings$2);
            let rest = $4[0];
            let bindings$3 = $4[1];
            let type_$1 = new EffectExtend(required, [lift, reply], rest);
            let bindings$4 = insert(bindings$3, i, new Bound(type_$1));
            return new Ok([[lift, reply], rest, bindings$4]);
          }
        }
      }
    } else if (type_ instanceof Empty3) {
      return new Error2(new MissingRow(required));
    } else if (type_ instanceof EffectExtend) {
      let l = type_[0];
      if (l === required) {
        let eff = type_[1];
        let rest = type_[2];
        return new Ok([eff, rest, bindings]);
      } else {
        let l$1 = type_[0];
        let other_eff = type_[1];
        let rest$1 = type_[2];
        return try$(rewrite_effect(required, rest$1, level, bindings, check), (_use0) => {
          let eff$1 = _use0[0];
          let new_tail = _use0[1];
          let bindings$1 = _use0[2];
          let rest$2 = new EffectExtend(l$1, other_eff, new_tail);
          return new Ok([eff$1, rest$2, bindings$1]);
        });
      }
    } else {
      throw makeError("panic", FILEPATH6, "eyg/analysis/type_/binding/unify", 236, "rewrite_effect", "bad effect", {});
    }
  }
}
function rewrite_row(loop$required, loop$type_, loop$level, loop$bindings, loop$check) {
  while (true) {
    let required = loop$required;
    let type_ = loop$type_;
    let level = loop$level;
    let bindings = loop$bindings;
    let check = loop$check;
    if (type_ instanceof Var) {
      let i = type_.key;
      let $ = get(bindings, i);
      if ($ instanceof Ok) {
        let $1 = $[0];
        if ($1 instanceof Bound) {
          let type_$1 = $1[0];
          loop$required = required;
          loop$type_ = type_$1;
          loop$level = level;
          loop$bindings = bindings;
          loop$check = check;
        } else {
          if (check instanceof Var) {
            let j = check.key;
            if (i === j) {
              console_log("same tails");
              return new Error2(new SameTail(new Var(i), new Var(j)));
            } else {
              let $2 = mono(level, bindings);
              let field2 = $2[0];
              let bindings$1 = $2[1];
              let $3 = mono(level, bindings$1);
              let rest = $3[0];
              let bindings$2 = $3[1];
              let type_$1 = new RowExtend(required, field2, rest);
              return new Ok([
                field2,
                rest,
                insert(bindings$2, i, new Bound(type_$1))
              ]);
            }
          } else {
            let $2 = mono(level, bindings);
            let field2 = $2[0];
            let bindings$1 = $2[1];
            let $3 = mono(level, bindings$1);
            let rest = $3[0];
            let bindings$2 = $3[1];
            let type_$1 = new RowExtend(required, field2, rest);
            return new Ok([
              field2,
              rest,
              insert(bindings$2, i, new Bound(type_$1))
            ]);
          }
        }
      } else {
        if (check instanceof Var) {
          let j = check.key;
          if (i === j) {
            console_log("same tails");
            return new Error2(new SameTail(new Var(i), new Var(j)));
          } else {
            let $1 = mono(level, bindings);
            let field2 = $1[0];
            let bindings$1 = $1[1];
            let $2 = mono(level, bindings$1);
            let rest = $2[0];
            let bindings$2 = $2[1];
            let type_$1 = new RowExtend(required, field2, rest);
            return new Ok([
              field2,
              rest,
              insert(bindings$2, i, new Bound(type_$1))
            ]);
          }
        } else {
          let $1 = mono(level, bindings);
          let field2 = $1[0];
          let bindings$1 = $1[1];
          let $2 = mono(level, bindings$1);
          let rest = $2[0];
          let bindings$2 = $2[1];
          let type_$1 = new RowExtend(required, field2, rest);
          return new Ok([
            field2,
            rest,
            insert(bindings$2, i, new Bound(type_$1))
          ]);
        }
      }
    } else if (type_ instanceof Empty3) {
      return new Error2(new MissingRow(required));
    } else if (type_ instanceof RowExtend) {
      let l = type_[0];
      if (l === required) {
        let field2 = type_[1];
        let rest = type_[2];
        return new Ok([field2, rest, bindings]);
      } else {
        let l$1 = type_[0];
        let other_field = type_[1];
        let rest$1 = type_[2];
        return try$(rewrite_row(required, rest$1, level, bindings, check), (_use0) => {
          let field$1 = _use0[0];
          let new_tail = _use0[1];
          let bindings$1 = _use0[2];
          let rest$2 = new RowExtend(l$1, other_field, new_tail);
          return new Ok([field$1, rest$2, bindings$1]);
        });
      }
    } else {
      throw makeError("panic", FILEPATH6, "eyg/analysis/type_/binding/unify", 184, "rewrite_row", "bad row", {});
    }
  }
}
function do_occurs_and_levels(loop$i, loop$level, loop$types, loop$bindings) {
  while (true) {
    let i = loop$i;
    let level = loop$level;
    let types = loop$types;
    let bindings = loop$bindings;
    if (types instanceof Empty) {
      return new Ok(bindings);
    } else {
      let type_ = types.head;
      let types$1 = types.tail;
      if (type_ instanceof Var) {
        let j = type_.key;
        if (i === j) {
          return new Error2(Reason$Recursive$const);
        } else {
          let j$1 = type_.key;
          let $ = get(bindings, j$1);
          let binding;
          if ($ instanceof Ok) {
            binding = $[0];
          } else {
            throw makeError("let_assert", FILEPATH6, "eyg/analysis/type_/binding/unify", 109, "do_occurs_and_levels", "Pattern match failed, no pattern matched the value.", {
              value: $,
              start: 4131,
              end: 4177,
              pattern_start: 4142,
              pattern_end: 4153
            });
          }
          if (binding instanceof Bound) {
            let type_$1 = binding[0];
            loop$i = i;
            loop$level = level;
            loop$types = prepend(type_$1, types$1);
            loop$bindings = bindings;
          } else {
            let l = binding.level;
            let l$1 = min(l, level);
            let bindings$1 = insert(bindings, j$1, new Unbound(l$1));
            loop$i = i;
            loop$level = level;
            loop$types = types$1;
            loop$bindings = bindings$1;
          }
        }
      } else if (type_ instanceof Fun) {
        let arg = type_[0];
        let eff = type_[1];
        let ret = type_[2];
        let types$2 = prepend(arg, prepend(eff, prepend(ret, types$1)));
        loop$i = i;
        loop$level = level;
        loop$types = types$2;
        loop$bindings = bindings;
      } else if (type_ instanceof Binary2) {
        loop$i = i;
        loop$level = level;
        loop$types = types$1;
        loop$bindings = bindings;
      } else if (type_ instanceof Integer2) {
        loop$i = i;
        loop$level = level;
        loop$types = types$1;
        loop$bindings = bindings;
      } else if (type_ instanceof String3) {
        loop$i = i;
        loop$level = level;
        loop$types = types$1;
        loop$bindings = bindings;
      } else if (type_ instanceof List2) {
        let el = type_[0];
        loop$i = i;
        loop$level = level;
        loop$types = prepend(el, types$1);
        loop$bindings = bindings;
      } else if (type_ instanceof Record) {
        let row = type_[0];
        loop$i = i;
        loop$level = level;
        loop$types = prepend(row, types$1);
        loop$bindings = bindings;
      } else if (type_ instanceof Union) {
        let row = type_[0];
        loop$i = i;
        loop$level = level;
        loop$types = prepend(row, types$1);
        loop$bindings = bindings;
      } else if (type_ instanceof Empty3) {
        loop$i = i;
        loop$level = level;
        loop$types = types$1;
        loop$bindings = bindings;
      } else if (type_ instanceof RowExtend) {
        let field2 = type_[1];
        let rest = type_[2];
        let types$2 = prepend(field2, prepend(rest, types$1));
        loop$i = i;
        loop$level = level;
        loop$types = types$2;
        loop$bindings = bindings;
      } else if (type_ instanceof EffectExtend) {
        let rest = type_[2];
        let lift = type_[1][0];
        let reply = type_[1][1];
        let types$2 = prepend(lift, prepend(reply, prepend(rest, types$1)));
        loop$i = i;
        loop$level = level;
        loop$types = types$2;
        loop$bindings = bindings;
      } else if (type_ instanceof Never) {
        loop$i = i;
        loop$level = level;
        loop$types = types$1;
        loop$bindings = bindings;
      } else {
        let inner = type_[0];
        loop$i = i;
        loop$level = level;
        loop$types = prepend(inner, types$1);
        loop$bindings = bindings;
      }
    }
  }
}
function find2(type_, bindings) {
  if (type_ instanceof Var) {
    let i = type_.key;
    return get(bindings, i);
  } else {
    return new Error2(undefined);
  }
}
function do_unify(loop$ts, loop$level, loop$bindings) {
  while (true) {
    let ts = loop$ts;
    let level = loop$level;
    let bindings = loop$bindings;
    if (ts instanceof Empty) {
      return new Ok(bindings);
    } else {
      let ts$1 = ts.tail;
      let t1 = ts.head[0];
      let t2 = ts.head[1];
      let $ = find2(t1, bindings);
      let $1 = find2(t2, bindings);
      if (t1 instanceof Var) {
        if (t2 instanceof Var) {
          let i = t1.key;
          let j = t2.key;
          if (i === j) {
            loop$ts = ts$1;
            loop$level = level;
            loop$bindings = bindings;
          } else if ($ instanceof Ok) {
            let $2 = $[0];
            if ($2 instanceof Bound) {
              let t1$1 = $2[0];
              loop$ts = prepend([t1$1, t2], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if ($1 instanceof Ok) {
              let $3 = $1[0];
              if ($3 instanceof Bound) {
                let t2$1 = $3[0];
                loop$ts = prepend([t1, t2$1], ts$1);
                loop$level = level;
                loop$bindings = bindings;
              } else {
                let other = t2;
                let i$1 = t1.key;
                let level$1 = $2.level;
                let $4 = do_occurs_and_levels(i$1, level$1, prepend(other, List$Empty$const), bindings);
                if ($4 instanceof Ok) {
                  let bindings$1 = $4[0];
                  let bindings$2 = insert(bindings$1, i$1, new Bound(other));
                  loop$ts = ts$1;
                  loop$level = level$1;
                  loop$bindings = bindings$2;
                } else {
                  return $4;
                }
              }
            } else {
              let other = t2;
              let i$1 = t1.key;
              let level$1 = $2.level;
              let $3 = do_occurs_and_levels(i$1, level$1, prepend(other, List$Empty$const), bindings);
              if ($3 instanceof Ok) {
                let bindings$1 = $3[0];
                let bindings$2 = insert(bindings$1, i$1, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $3;
              }
            }
          } else if ($1 instanceof Ok) {
            let $2 = $1[0];
            if ($2 instanceof Bound) {
              let t2$1 = $2[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else {
              let other = t1;
              let i$1 = t2.key;
              let level$1 = $2.level;
              let $3 = do_occurs_and_levels(i$1, level$1, prepend(other, List$Empty$const), bindings);
              if ($3 instanceof Ok) {
                let bindings$1 = $3[0];
                let bindings$2 = insert(bindings$1, i$1, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $3;
              }
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if (t2 instanceof RowExtend) {
          if ($ instanceof Ok) {
            let $2 = $[0];
            if ($2 instanceof Bound) {
              let t1$1 = $2[0];
              loop$ts = prepend([t1$1, t2], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if ($1 instanceof Ok) {
              let $3 = $1[0];
              if ($3 instanceof Bound) {
                let t2$1 = $3[0];
                loop$ts = prepend([t1, t2$1], ts$1);
                loop$level = level;
                loop$bindings = bindings;
              } else {
                let other = t2;
                let i = t1.key;
                let level$1 = $2.level;
                let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
                if ($4 instanceof Ok) {
                  let bindings$1 = $4[0];
                  let bindings$2 = insert(bindings$1, i, new Bound(other));
                  loop$ts = ts$1;
                  loop$level = level$1;
                  loop$bindings = bindings$2;
                } else {
                  return $4;
                }
              }
            } else {
              let other = t2;
              let i = t1.key;
              let level$1 = $2.level;
              let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($3 instanceof Ok) {
                let bindings$1 = $3[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $3;
              }
            }
          } else if ($1 instanceof Ok) {
            let $2 = $1[0];
            if ($2 instanceof Bound) {
              let t2$1 = $2[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else {
              let other = t1;
              let l1 = t2[0];
              let field1 = t2[1];
              let rest1 = t2[2];
              let $3 = rewrite_row(l1, other, level, bindings, rest1);
              if ($3 instanceof Ok) {
                let field2 = $3[0][0];
                let rest2 = $3[0][1];
                let bindings$1 = $3[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $3;
              }
            }
          } else {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $2 = rewrite_row(l1, other, level, bindings, rest1);
            if ($2 instanceof Ok) {
              let field2 = $2[0][0];
              let rest2 = $2[0][1];
              let bindings$1 = $2[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $2;
            }
          }
        } else if (t2 instanceof EffectExtend) {
          if ($ instanceof Ok) {
            let $2 = $[0];
            if ($2 instanceof Bound) {
              let t1$1 = $2[0];
              loop$ts = prepend([t1$1, t2], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if ($1 instanceof Ok) {
              let $3 = $1[0];
              if ($3 instanceof Bound) {
                let t2$1 = $3[0];
                loop$ts = prepend([t1, t2$1], ts$1);
                loop$level = level;
                loop$bindings = bindings;
              } else {
                let other = t2;
                let i = t1.key;
                let level$1 = $2.level;
                let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
                if ($4 instanceof Ok) {
                  let bindings$1 = $4[0];
                  let bindings$2 = insert(bindings$1, i, new Bound(other));
                  loop$ts = ts$1;
                  loop$level = level$1;
                  loop$bindings = bindings$2;
                } else {
                  return $4;
                }
              }
            } else {
              let other = t2;
              let i = t1.key;
              let level$1 = $2.level;
              let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($3 instanceof Ok) {
                let bindings$1 = $3[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $3;
              }
            }
          } else if ($1 instanceof Ok) {
            let $2 = $1[0];
            if ($2 instanceof Bound) {
              let t2$1 = $2[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else {
              let other = t1;
              let l1 = t2[0];
              let r1 = t2[2];
              let lift1 = t2[1][0];
              let reply1 = t2[1][1];
              let $3 = rewrite_effect(l1, other, level, bindings, r1);
              if ($3 instanceof Ok) {
                let r2 = $3[0][1];
                let bindings$1 = $3[0][2];
                let lift2 = $3[0][0][0];
                let reply2 = $3[0][0][1];
                let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $3;
              }
            }
          } else {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $2 = rewrite_effect(l1, other, level, bindings, r1);
            if ($2 instanceof Ok) {
              let r2 = $2[0][1];
              let bindings$1 = $2[0][2];
              let lift2 = $2[0][0][0];
              let reply2 = $2[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $2;
            }
          }
        } else if ($ instanceof Ok) {
          let $2 = $[0];
          if ($2 instanceof Bound) {
            let t1$1 = $2[0];
            loop$ts = prepend([t1$1, t2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if ($1 instanceof Ok) {
            let $3 = $1[0];
            if ($3 instanceof Bound) {
              let t2$1 = $3[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else {
              let other = t2;
              let i = t1.key;
              let level$1 = $2.level;
              let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($4 instanceof Ok) {
                let bindings$1 = $4[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $4;
              }
            }
          } else {
            let other = t2;
            let i = t1.key;
            let level$1 = $2.level;
            let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
            if ($3 instanceof Ok) {
              let bindings$1 = $3[0];
              let bindings$2 = insert(bindings$1, i, new Bound(other));
              loop$ts = ts$1;
              loop$level = level$1;
              loop$bindings = bindings$2;
            } else {
              return $3;
            }
          }
        } else if ($1 instanceof Ok) {
          let $2 = $1[0];
          if ($2 instanceof Bound) {
            let t2$1 = $2[0];
            loop$ts = prepend([t1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else {
          return new Error2(new TypeMismatch(t1, t2));
        }
      } else if (t1 instanceof Fun) {
        if ($ instanceof Ok) {
          let $2 = $[0];
          if ($2 instanceof Bound) {
            let t1$1 = $2[0];
            loop$ts = prepend([t1$1, t2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if ($1 instanceof Ok) {
            let $3 = $1[0];
            if ($3 instanceof Bound) {
              let t2$1 = $3[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof Var) {
              let other = t1;
              let level$1 = $3.level;
              let i = t2.key;
              let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($4 instanceof Ok) {
                let bindings$1 = $4[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $4;
              }
            } else if (t2 instanceof Fun) {
              let arg1 = t1[0];
              let eff1 = t1[1];
              let ret1 = t1[2];
              let arg2 = t2[0];
              let eff2 = t2[1];
              let ret2 = t2[2];
              let ts$2 = prepend([arg1, arg2], prepend([eff1, eff2], prepend([ret1, ret2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof RowExtend) {
              let other = t1;
              let l1 = t2[0];
              let field1 = t2[1];
              let rest1 = t2[2];
              let $4 = rewrite_row(l1, other, level, bindings, rest1);
              if ($4 instanceof Ok) {
                let field2 = $4[0][0];
                let rest2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else if (t2 instanceof EffectExtend) {
              let other = t1;
              let l1 = t2[0];
              let r1 = t2[2];
              let lift1 = t2[1][0];
              let reply1 = t2[1][1];
              let $4 = rewrite_effect(l1, other, level, bindings, r1);
              if ($4 instanceof Ok) {
                let r2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let lift2 = $4[0][0][0];
                let reply2 = $4[0][0][1];
                let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else {
              return new Error2(new TypeMismatch(t1, t2));
            }
          } else if (t2 instanceof Fun) {
            let arg1 = t1[0];
            let eff1 = t1[1];
            let ret1 = t1[2];
            let arg2 = t2[0];
            let eff2 = t2[1];
            let ret2 = t2[2];
            let ts$2 = prepend([arg1, arg2], prepend([eff1, eff2], prepend([ret1, ret2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if ($1 instanceof Ok) {
          let $2 = $1[0];
          if ($2 instanceof Bound) {
            let t2$1 = $2[0];
            loop$ts = prepend([t1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof Var) {
            let other = t1;
            let level$1 = $2.level;
            let i = t2.key;
            let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
            if ($3 instanceof Ok) {
              let bindings$1 = $3[0];
              let bindings$2 = insert(bindings$1, i, new Bound(other));
              loop$ts = ts$1;
              loop$level = level$1;
              loop$bindings = bindings$2;
            } else {
              return $3;
            }
          } else if (t2 instanceof Fun) {
            let arg1 = t1[0];
            let eff1 = t1[1];
            let ret1 = t1[2];
            let arg2 = t2[0];
            let eff2 = t2[1];
            let ret2 = t2[2];
            let ts$2 = prepend([arg1, arg2], prepend([eff1, eff2], prepend([ret1, ret2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if (t2 instanceof Fun) {
          let arg1 = t1[0];
          let eff1 = t1[1];
          let ret1 = t1[2];
          let arg2 = t2[0];
          let eff2 = t2[1];
          let ret2 = t2[2];
          let ts$2 = prepend([arg1, arg2], prepend([eff1, eff2], prepend([ret1, ret2], ts$1)));
          loop$ts = ts$2;
          loop$level = level;
          loop$bindings = bindings;
        } else if (t2 instanceof RowExtend) {
          let other = t1;
          let l1 = t2[0];
          let field1 = t2[1];
          let rest1 = t2[2];
          let $2 = rewrite_row(l1, other, level, bindings, rest1);
          if ($2 instanceof Ok) {
            let field2 = $2[0][0];
            let rest2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else if (t2 instanceof EffectExtend) {
          let other = t1;
          let l1 = t2[0];
          let r1 = t2[2];
          let lift1 = t2[1][0];
          let reply1 = t2[1][1];
          let $2 = rewrite_effect(l1, other, level, bindings, r1);
          if ($2 instanceof Ok) {
            let r2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let lift2 = $2[0][0][0];
            let reply2 = $2[0][0][1];
            let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else {
          return new Error2(new TypeMismatch(t1, t2));
        }
      } else if (t1 instanceof Binary2) {
        if ($ instanceof Ok) {
          let $2 = $[0];
          if ($2 instanceof Bound) {
            let t1$1 = $2[0];
            loop$ts = prepend([t1$1, t2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if ($1 instanceof Ok) {
            let $3 = $1[0];
            if ($3 instanceof Bound) {
              let t2$1 = $3[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof Var) {
              let other = t1;
              let level$1 = $3.level;
              let i = t2.key;
              let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($4 instanceof Ok) {
                let bindings$1 = $4[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $4;
              }
            } else if (t2 instanceof Binary2) {
              loop$ts = ts$1;
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof RowExtend) {
              let other = t1;
              let l1 = t2[0];
              let field1 = t2[1];
              let rest1 = t2[2];
              let $4 = rewrite_row(l1, other, level, bindings, rest1);
              if ($4 instanceof Ok) {
                let field2 = $4[0][0];
                let rest2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else if (t2 instanceof EffectExtend) {
              let other = t1;
              let l1 = t2[0];
              let r1 = t2[2];
              let lift1 = t2[1][0];
              let reply1 = t2[1][1];
              let $4 = rewrite_effect(l1, other, level, bindings, r1);
              if ($4 instanceof Ok) {
                let r2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let lift2 = $4[0][0][0];
                let reply2 = $4[0][0][1];
                let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else {
              return new Error2(new TypeMismatch(t1, t2));
            }
          } else if (t2 instanceof Binary2) {
            loop$ts = ts$1;
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if ($1 instanceof Ok) {
          let $2 = $1[0];
          if ($2 instanceof Bound) {
            let t2$1 = $2[0];
            loop$ts = prepend([t1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof Var) {
            let other = t1;
            let level$1 = $2.level;
            let i = t2.key;
            let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
            if ($3 instanceof Ok) {
              let bindings$1 = $3[0];
              let bindings$2 = insert(bindings$1, i, new Bound(other));
              loop$ts = ts$1;
              loop$level = level$1;
              loop$bindings = bindings$2;
            } else {
              return $3;
            }
          } else if (t2 instanceof Binary2) {
            loop$ts = ts$1;
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if (t2 instanceof Binary2) {
          loop$ts = ts$1;
          loop$level = level;
          loop$bindings = bindings;
        } else if (t2 instanceof RowExtend) {
          let other = t1;
          let l1 = t2[0];
          let field1 = t2[1];
          let rest1 = t2[2];
          let $2 = rewrite_row(l1, other, level, bindings, rest1);
          if ($2 instanceof Ok) {
            let field2 = $2[0][0];
            let rest2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else if (t2 instanceof EffectExtend) {
          let other = t1;
          let l1 = t2[0];
          let r1 = t2[2];
          let lift1 = t2[1][0];
          let reply1 = t2[1][1];
          let $2 = rewrite_effect(l1, other, level, bindings, r1);
          if ($2 instanceof Ok) {
            let r2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let lift2 = $2[0][0][0];
            let reply2 = $2[0][0][1];
            let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else {
          return new Error2(new TypeMismatch(t1, t2));
        }
      } else if (t1 instanceof Integer2) {
        if ($ instanceof Ok) {
          let $2 = $[0];
          if ($2 instanceof Bound) {
            let t1$1 = $2[0];
            loop$ts = prepend([t1$1, t2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if ($1 instanceof Ok) {
            let $3 = $1[0];
            if ($3 instanceof Bound) {
              let t2$1 = $3[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof Var) {
              let other = t1;
              let level$1 = $3.level;
              let i = t2.key;
              let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($4 instanceof Ok) {
                let bindings$1 = $4[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $4;
              }
            } else if (t2 instanceof Integer2) {
              loop$ts = ts$1;
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof RowExtend) {
              let other = t1;
              let l1 = t2[0];
              let field1 = t2[1];
              let rest1 = t2[2];
              let $4 = rewrite_row(l1, other, level, bindings, rest1);
              if ($4 instanceof Ok) {
                let field2 = $4[0][0];
                let rest2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else if (t2 instanceof EffectExtend) {
              let other = t1;
              let l1 = t2[0];
              let r1 = t2[2];
              let lift1 = t2[1][0];
              let reply1 = t2[1][1];
              let $4 = rewrite_effect(l1, other, level, bindings, r1);
              if ($4 instanceof Ok) {
                let r2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let lift2 = $4[0][0][0];
                let reply2 = $4[0][0][1];
                let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else {
              return new Error2(new TypeMismatch(t1, t2));
            }
          } else if (t2 instanceof Integer2) {
            loop$ts = ts$1;
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if ($1 instanceof Ok) {
          let $2 = $1[0];
          if ($2 instanceof Bound) {
            let t2$1 = $2[0];
            loop$ts = prepend([t1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof Var) {
            let other = t1;
            let level$1 = $2.level;
            let i = t2.key;
            let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
            if ($3 instanceof Ok) {
              let bindings$1 = $3[0];
              let bindings$2 = insert(bindings$1, i, new Bound(other));
              loop$ts = ts$1;
              loop$level = level$1;
              loop$bindings = bindings$2;
            } else {
              return $3;
            }
          } else if (t2 instanceof Integer2) {
            loop$ts = ts$1;
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if (t2 instanceof Integer2) {
          loop$ts = ts$1;
          loop$level = level;
          loop$bindings = bindings;
        } else if (t2 instanceof RowExtend) {
          let other = t1;
          let l1 = t2[0];
          let field1 = t2[1];
          let rest1 = t2[2];
          let $2 = rewrite_row(l1, other, level, bindings, rest1);
          if ($2 instanceof Ok) {
            let field2 = $2[0][0];
            let rest2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else if (t2 instanceof EffectExtend) {
          let other = t1;
          let l1 = t2[0];
          let r1 = t2[2];
          let lift1 = t2[1][0];
          let reply1 = t2[1][1];
          let $2 = rewrite_effect(l1, other, level, bindings, r1);
          if ($2 instanceof Ok) {
            let r2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let lift2 = $2[0][0][0];
            let reply2 = $2[0][0][1];
            let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else {
          return new Error2(new TypeMismatch(t1, t2));
        }
      } else if (t1 instanceof String3) {
        if ($ instanceof Ok) {
          let $2 = $[0];
          if ($2 instanceof Bound) {
            let t1$1 = $2[0];
            loop$ts = prepend([t1$1, t2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if ($1 instanceof Ok) {
            let $3 = $1[0];
            if ($3 instanceof Bound) {
              let t2$1 = $3[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof Var) {
              let other = t1;
              let level$1 = $3.level;
              let i = t2.key;
              let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($4 instanceof Ok) {
                let bindings$1 = $4[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $4;
              }
            } else if (t2 instanceof String3) {
              loop$ts = ts$1;
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof RowExtend) {
              let other = t1;
              let l1 = t2[0];
              let field1 = t2[1];
              let rest1 = t2[2];
              let $4 = rewrite_row(l1, other, level, bindings, rest1);
              if ($4 instanceof Ok) {
                let field2 = $4[0][0];
                let rest2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else if (t2 instanceof EffectExtend) {
              let other = t1;
              let l1 = t2[0];
              let r1 = t2[2];
              let lift1 = t2[1][0];
              let reply1 = t2[1][1];
              let $4 = rewrite_effect(l1, other, level, bindings, r1);
              if ($4 instanceof Ok) {
                let r2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let lift2 = $4[0][0][0];
                let reply2 = $4[0][0][1];
                let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else {
              return new Error2(new TypeMismatch(t1, t2));
            }
          } else if (t2 instanceof String3) {
            loop$ts = ts$1;
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if ($1 instanceof Ok) {
          let $2 = $1[0];
          if ($2 instanceof Bound) {
            let t2$1 = $2[0];
            loop$ts = prepend([t1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof Var) {
            let other = t1;
            let level$1 = $2.level;
            let i = t2.key;
            let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
            if ($3 instanceof Ok) {
              let bindings$1 = $3[0];
              let bindings$2 = insert(bindings$1, i, new Bound(other));
              loop$ts = ts$1;
              loop$level = level$1;
              loop$bindings = bindings$2;
            } else {
              return $3;
            }
          } else if (t2 instanceof String3) {
            loop$ts = ts$1;
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if (t2 instanceof String3) {
          loop$ts = ts$1;
          loop$level = level;
          loop$bindings = bindings;
        } else if (t2 instanceof RowExtend) {
          let other = t1;
          let l1 = t2[0];
          let field1 = t2[1];
          let rest1 = t2[2];
          let $2 = rewrite_row(l1, other, level, bindings, rest1);
          if ($2 instanceof Ok) {
            let field2 = $2[0][0];
            let rest2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else if (t2 instanceof EffectExtend) {
          let other = t1;
          let l1 = t2[0];
          let r1 = t2[2];
          let lift1 = t2[1][0];
          let reply1 = t2[1][1];
          let $2 = rewrite_effect(l1, other, level, bindings, r1);
          if ($2 instanceof Ok) {
            let r2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let lift2 = $2[0][0][0];
            let reply2 = $2[0][0][1];
            let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else {
          return new Error2(new TypeMismatch(t1, t2));
        }
      } else if (t1 instanceof List2) {
        if ($ instanceof Ok) {
          let $2 = $[0];
          if ($2 instanceof Bound) {
            let t1$1 = $2[0];
            loop$ts = prepend([t1$1, t2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if ($1 instanceof Ok) {
            let $3 = $1[0];
            if ($3 instanceof Bound) {
              let t2$1 = $3[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof Var) {
              let other = t1;
              let level$1 = $3.level;
              let i = t2.key;
              let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($4 instanceof Ok) {
                let bindings$1 = $4[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $4;
              }
            } else if (t2 instanceof List2) {
              let el1 = t1[0];
              let el2 = t2[0];
              loop$ts = prepend([el1, el2], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof RowExtend) {
              let other = t1;
              let l1 = t2[0];
              let field1 = t2[1];
              let rest1 = t2[2];
              let $4 = rewrite_row(l1, other, level, bindings, rest1);
              if ($4 instanceof Ok) {
                let field2 = $4[0][0];
                let rest2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else if (t2 instanceof EffectExtend) {
              let other = t1;
              let l1 = t2[0];
              let r1 = t2[2];
              let lift1 = t2[1][0];
              let reply1 = t2[1][1];
              let $4 = rewrite_effect(l1, other, level, bindings, r1);
              if ($4 instanceof Ok) {
                let r2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let lift2 = $4[0][0][0];
                let reply2 = $4[0][0][1];
                let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else {
              return new Error2(new TypeMismatch(t1, t2));
            }
          } else if (t2 instanceof List2) {
            let el1 = t1[0];
            let el2 = t2[0];
            loop$ts = prepend([el1, el2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if ($1 instanceof Ok) {
          let $2 = $1[0];
          if ($2 instanceof Bound) {
            let t2$1 = $2[0];
            loop$ts = prepend([t1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof Var) {
            let other = t1;
            let level$1 = $2.level;
            let i = t2.key;
            let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
            if ($3 instanceof Ok) {
              let bindings$1 = $3[0];
              let bindings$2 = insert(bindings$1, i, new Bound(other));
              loop$ts = ts$1;
              loop$level = level$1;
              loop$bindings = bindings$2;
            } else {
              return $3;
            }
          } else if (t2 instanceof List2) {
            let el1 = t1[0];
            let el2 = t2[0];
            loop$ts = prepend([el1, el2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if (t2 instanceof List2) {
          let el1 = t1[0];
          let el2 = t2[0];
          loop$ts = prepend([el1, el2], ts$1);
          loop$level = level;
          loop$bindings = bindings;
        } else if (t2 instanceof RowExtend) {
          let other = t1;
          let l1 = t2[0];
          let field1 = t2[1];
          let rest1 = t2[2];
          let $2 = rewrite_row(l1, other, level, bindings, rest1);
          if ($2 instanceof Ok) {
            let field2 = $2[0][0];
            let rest2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else if (t2 instanceof EffectExtend) {
          let other = t1;
          let l1 = t2[0];
          let r1 = t2[2];
          let lift1 = t2[1][0];
          let reply1 = t2[1][1];
          let $2 = rewrite_effect(l1, other, level, bindings, r1);
          if ($2 instanceof Ok) {
            let r2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let lift2 = $2[0][0][0];
            let reply2 = $2[0][0][1];
            let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else {
          return new Error2(new TypeMismatch(t1, t2));
        }
      } else if (t1 instanceof Record) {
        if ($ instanceof Ok) {
          let $2 = $[0];
          if ($2 instanceof Bound) {
            let t1$1 = $2[0];
            loop$ts = prepend([t1$1, t2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if ($1 instanceof Ok) {
            let $3 = $1[0];
            if ($3 instanceof Bound) {
              let t2$1 = $3[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof Var) {
              let other = t1;
              let level$1 = $3.level;
              let i = t2.key;
              let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($4 instanceof Ok) {
                let bindings$1 = $4[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $4;
              }
            } else if (t2 instanceof Record) {
              let rows1 = t1[0];
              let rows2 = t2[0];
              loop$ts = prepend([rows1, rows2], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof RowExtend) {
              let other = t1;
              let l1 = t2[0];
              let field1 = t2[1];
              let rest1 = t2[2];
              let $4 = rewrite_row(l1, other, level, bindings, rest1);
              if ($4 instanceof Ok) {
                let field2 = $4[0][0];
                let rest2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else if (t2 instanceof EffectExtend) {
              let other = t1;
              let l1 = t2[0];
              let r1 = t2[2];
              let lift1 = t2[1][0];
              let reply1 = t2[1][1];
              let $4 = rewrite_effect(l1, other, level, bindings, r1);
              if ($4 instanceof Ok) {
                let r2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let lift2 = $4[0][0][0];
                let reply2 = $4[0][0][1];
                let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else {
              return new Error2(new TypeMismatch(t1, t2));
            }
          } else if (t2 instanceof Record) {
            let rows1 = t1[0];
            let rows2 = t2[0];
            loop$ts = prepend([rows1, rows2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if ($1 instanceof Ok) {
          let $2 = $1[0];
          if ($2 instanceof Bound) {
            let t2$1 = $2[0];
            loop$ts = prepend([t1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof Var) {
            let other = t1;
            let level$1 = $2.level;
            let i = t2.key;
            let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
            if ($3 instanceof Ok) {
              let bindings$1 = $3[0];
              let bindings$2 = insert(bindings$1, i, new Bound(other));
              loop$ts = ts$1;
              loop$level = level$1;
              loop$bindings = bindings$2;
            } else {
              return $3;
            }
          } else if (t2 instanceof Record) {
            let rows1 = t1[0];
            let rows2 = t2[0];
            loop$ts = prepend([rows1, rows2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if (t2 instanceof Record) {
          let rows1 = t1[0];
          let rows2 = t2[0];
          loop$ts = prepend([rows1, rows2], ts$1);
          loop$level = level;
          loop$bindings = bindings;
        } else if (t2 instanceof RowExtend) {
          let other = t1;
          let l1 = t2[0];
          let field1 = t2[1];
          let rest1 = t2[2];
          let $2 = rewrite_row(l1, other, level, bindings, rest1);
          if ($2 instanceof Ok) {
            let field2 = $2[0][0];
            let rest2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else if (t2 instanceof EffectExtend) {
          let other = t1;
          let l1 = t2[0];
          let r1 = t2[2];
          let lift1 = t2[1][0];
          let reply1 = t2[1][1];
          let $2 = rewrite_effect(l1, other, level, bindings, r1);
          if ($2 instanceof Ok) {
            let r2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let lift2 = $2[0][0][0];
            let reply2 = $2[0][0][1];
            let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else {
          return new Error2(new TypeMismatch(t1, t2));
        }
      } else if (t1 instanceof Union) {
        if ($ instanceof Ok) {
          let $2 = $[0];
          if ($2 instanceof Bound) {
            let t1$1 = $2[0];
            loop$ts = prepend([t1$1, t2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if ($1 instanceof Ok) {
            let $3 = $1[0];
            if ($3 instanceof Bound) {
              let t2$1 = $3[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof Var) {
              let other = t1;
              let level$1 = $3.level;
              let i = t2.key;
              let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($4 instanceof Ok) {
                let bindings$1 = $4[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $4;
              }
            } else if (t2 instanceof Union) {
              let rows1 = t1[0];
              let rows2 = t2[0];
              loop$ts = prepend([rows1, rows2], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof RowExtend) {
              let other = t1;
              let l1 = t2[0];
              let field1 = t2[1];
              let rest1 = t2[2];
              let $4 = rewrite_row(l1, other, level, bindings, rest1);
              if ($4 instanceof Ok) {
                let field2 = $4[0][0];
                let rest2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else if (t2 instanceof EffectExtend) {
              let other = t1;
              let l1 = t2[0];
              let r1 = t2[2];
              let lift1 = t2[1][0];
              let reply1 = t2[1][1];
              let $4 = rewrite_effect(l1, other, level, bindings, r1);
              if ($4 instanceof Ok) {
                let r2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let lift2 = $4[0][0][0];
                let reply2 = $4[0][0][1];
                let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else {
              return new Error2(new TypeMismatch(t1, t2));
            }
          } else if (t2 instanceof Union) {
            let rows1 = t1[0];
            let rows2 = t2[0];
            loop$ts = prepend([rows1, rows2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if ($1 instanceof Ok) {
          let $2 = $1[0];
          if ($2 instanceof Bound) {
            let t2$1 = $2[0];
            loop$ts = prepend([t1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof Var) {
            let other = t1;
            let level$1 = $2.level;
            let i = t2.key;
            let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
            if ($3 instanceof Ok) {
              let bindings$1 = $3[0];
              let bindings$2 = insert(bindings$1, i, new Bound(other));
              loop$ts = ts$1;
              loop$level = level$1;
              loop$bindings = bindings$2;
            } else {
              return $3;
            }
          } else if (t2 instanceof Union) {
            let rows1 = t1[0];
            let rows2 = t2[0];
            loop$ts = prepend([rows1, rows2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if (t2 instanceof Union) {
          let rows1 = t1[0];
          let rows2 = t2[0];
          loop$ts = prepend([rows1, rows2], ts$1);
          loop$level = level;
          loop$bindings = bindings;
        } else if (t2 instanceof RowExtend) {
          let other = t1;
          let l1 = t2[0];
          let field1 = t2[1];
          let rest1 = t2[2];
          let $2 = rewrite_row(l1, other, level, bindings, rest1);
          if ($2 instanceof Ok) {
            let field2 = $2[0][0];
            let rest2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else if (t2 instanceof EffectExtend) {
          let other = t1;
          let l1 = t2[0];
          let r1 = t2[2];
          let lift1 = t2[1][0];
          let reply1 = t2[1][1];
          let $2 = rewrite_effect(l1, other, level, bindings, r1);
          if ($2 instanceof Ok) {
            let r2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let lift2 = $2[0][0][0];
            let reply2 = $2[0][0][1];
            let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else {
          return new Error2(new TypeMismatch(t1, t2));
        }
      } else if (t1 instanceof Empty3) {
        if ($ instanceof Ok) {
          let $2 = $[0];
          if ($2 instanceof Bound) {
            let t1$1 = $2[0];
            loop$ts = prepend([t1$1, t2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if ($1 instanceof Ok) {
            let $3 = $1[0];
            if ($3 instanceof Bound) {
              let t2$1 = $3[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof Var) {
              let other = t1;
              let level$1 = $3.level;
              let i = t2.key;
              let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($4 instanceof Ok) {
                let bindings$1 = $4[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $4;
              }
            } else if (t2 instanceof Empty3) {
              loop$ts = ts$1;
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof RowExtend) {
              let other = t1;
              let l1 = t2[0];
              let field1 = t2[1];
              let rest1 = t2[2];
              let $4 = rewrite_row(l1, other, level, bindings, rest1);
              if ($4 instanceof Ok) {
                let field2 = $4[0][0];
                let rest2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else if (t2 instanceof EffectExtend) {
              let other = t1;
              let l1 = t2[0];
              let r1 = t2[2];
              let lift1 = t2[1][0];
              let reply1 = t2[1][1];
              let $4 = rewrite_effect(l1, other, level, bindings, r1);
              if ($4 instanceof Ok) {
                let r2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let lift2 = $4[0][0][0];
                let reply2 = $4[0][0][1];
                let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else {
              return new Error2(new TypeMismatch(t1, t2));
            }
          } else if (t2 instanceof Empty3) {
            loop$ts = ts$1;
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if ($1 instanceof Ok) {
          let $2 = $1[0];
          if ($2 instanceof Bound) {
            let t2$1 = $2[0];
            loop$ts = prepend([t1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof Var) {
            let other = t1;
            let level$1 = $2.level;
            let i = t2.key;
            let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
            if ($3 instanceof Ok) {
              let bindings$1 = $3[0];
              let bindings$2 = insert(bindings$1, i, new Bound(other));
              loop$ts = ts$1;
              loop$level = level$1;
              loop$bindings = bindings$2;
            } else {
              return $3;
            }
          } else if (t2 instanceof Empty3) {
            loop$ts = ts$1;
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if (t2 instanceof Empty3) {
          loop$ts = ts$1;
          loop$level = level;
          loop$bindings = bindings;
        } else if (t2 instanceof RowExtend) {
          let other = t1;
          let l1 = t2[0];
          let field1 = t2[1];
          let rest1 = t2[2];
          let $2 = rewrite_row(l1, other, level, bindings, rest1);
          if ($2 instanceof Ok) {
            let field2 = $2[0][0];
            let rest2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else if (t2 instanceof EffectExtend) {
          let other = t1;
          let l1 = t2[0];
          let r1 = t2[2];
          let lift1 = t2[1][0];
          let reply1 = t2[1][1];
          let $2 = rewrite_effect(l1, other, level, bindings, r1);
          if ($2 instanceof Ok) {
            let r2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let lift2 = $2[0][0][0];
            let reply2 = $2[0][0][1];
            let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else {
          return new Error2(new TypeMismatch(t1, t2));
        }
      } else if (t1 instanceof RowExtend) {
        if ($ instanceof Ok) {
          let $2 = $[0];
          if ($2 instanceof Bound) {
            let t1$1 = $2[0];
            loop$ts = prepend([t1$1, t2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if ($1 instanceof Ok) {
            let $3 = $1[0];
            if ($3 instanceof Bound) {
              let t2$1 = $3[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof Var) {
              let other = t1;
              let level$1 = $3.level;
              let i = t2.key;
              let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($4 instanceof Ok) {
                let bindings$1 = $4[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $4;
              }
            } else if (t2 instanceof RowExtend) {
              let other = t2;
              let l1 = t1[0];
              let field1 = t1[1];
              let rest1 = t1[2];
              let $4 = rewrite_row(l1, other, level, bindings, rest1);
              if ($4 instanceof Ok) {
                let field2 = $4[0][0];
                let rest2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else if (t2 instanceof EffectExtend) {
              let other = t2;
              let l1 = t1[0];
              let field1 = t1[1];
              let rest1 = t1[2];
              let $4 = rewrite_row(l1, other, level, bindings, rest1);
              if ($4 instanceof Ok) {
                let field2 = $4[0][0];
                let rest2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else {
              let other = t2;
              let l1 = t1[0];
              let field1 = t1[1];
              let rest1 = t1[2];
              let $4 = rewrite_row(l1, other, level, bindings, rest1);
              if ($4 instanceof Ok) {
                let field2 = $4[0][0];
                let rest2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            }
          } else {
            let other = t2;
            let l1 = t1[0];
            let field1 = t1[1];
            let rest1 = t1[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          }
        } else if ($1 instanceof Ok) {
          let $2 = $1[0];
          if ($2 instanceof Bound) {
            let t2$1 = $2[0];
            loop$ts = prepend([t1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof Var) {
            let other = t1;
            let level$1 = $2.level;
            let i = t2.key;
            let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
            if ($3 instanceof Ok) {
              let bindings$1 = $3[0];
              let bindings$2 = insert(bindings$1, i, new Bound(other));
              loop$ts = ts$1;
              loop$level = level$1;
              loop$bindings = bindings$2;
            } else {
              return $3;
            }
          } else if (t2 instanceof RowExtend) {
            let other = t2;
            let l1 = t1[0];
            let field1 = t1[1];
            let rest1 = t1[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t2;
            let l1 = t1[0];
            let field1 = t1[1];
            let rest1 = t1[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            let other = t2;
            let l1 = t1[0];
            let field1 = t1[1];
            let rest1 = t1[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          }
        } else {
          let other = t2;
          let l1 = t1[0];
          let field1 = t1[1];
          let rest1 = t1[2];
          let $2 = rewrite_row(l1, other, level, bindings, rest1);
          if ($2 instanceof Ok) {
            let field2 = $2[0][0];
            let rest2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        }
      } else if (t1 instanceof EffectExtend) {
        if ($ instanceof Ok) {
          let $2 = $[0];
          if ($2 instanceof Bound) {
            let t1$1 = $2[0];
            loop$ts = prepend([t1$1, t2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if ($1 instanceof Ok) {
            let $3 = $1[0];
            if ($3 instanceof Bound) {
              let t2$1 = $3[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof Var) {
              let other = t1;
              let level$1 = $3.level;
              let i = t2.key;
              let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($4 instanceof Ok) {
                let bindings$1 = $4[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $4;
              }
            } else if (t2 instanceof RowExtend) {
              let other = t1;
              let l1 = t2[0];
              let field1 = t2[1];
              let rest1 = t2[2];
              let $4 = rewrite_row(l1, other, level, bindings, rest1);
              if ($4 instanceof Ok) {
                let field2 = $4[0][0];
                let rest2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else if (t2 instanceof EffectExtend) {
              let other = t2;
              let l1 = t1[0];
              let r1 = t1[2];
              let lift1 = t1[1][0];
              let reply1 = t1[1][1];
              let $4 = rewrite_effect(l1, other, level, bindings, r1);
              if ($4 instanceof Ok) {
                let r2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let lift2 = $4[0][0][0];
                let reply2 = $4[0][0][1];
                let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else {
              let other = t2;
              let l1 = t1[0];
              let r1 = t1[2];
              let lift1 = t1[1][0];
              let reply1 = t1[1][1];
              let $4 = rewrite_effect(l1, other, level, bindings, r1);
              if ($4 instanceof Ok) {
                let r2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let lift2 = $4[0][0][0];
                let reply2 = $4[0][0][1];
                let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            }
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t2;
            let l1 = t1[0];
            let r1 = t1[2];
            let lift1 = t1[1][0];
            let reply1 = t1[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            let other = t2;
            let l1 = t1[0];
            let r1 = t1[2];
            let lift1 = t1[1][0];
            let reply1 = t1[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          }
        } else if ($1 instanceof Ok) {
          let $2 = $1[0];
          if ($2 instanceof Bound) {
            let t2$1 = $2[0];
            loop$ts = prepend([t1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof Var) {
            let other = t1;
            let level$1 = $2.level;
            let i = t2.key;
            let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
            if ($3 instanceof Ok) {
              let bindings$1 = $3[0];
              let bindings$2 = insert(bindings$1, i, new Bound(other));
              loop$ts = ts$1;
              loop$level = level$1;
              loop$bindings = bindings$2;
            } else {
              return $3;
            }
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t2;
            let l1 = t1[0];
            let r1 = t1[2];
            let lift1 = t1[1][0];
            let reply1 = t1[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else {
            let other = t2;
            let l1 = t1[0];
            let r1 = t1[2];
            let lift1 = t1[1][0];
            let reply1 = t1[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          }
        } else if (t2 instanceof RowExtend) {
          let other = t1;
          let l1 = t2[0];
          let field1 = t2[1];
          let rest1 = t2[2];
          let $2 = rewrite_row(l1, other, level, bindings, rest1);
          if ($2 instanceof Ok) {
            let field2 = $2[0][0];
            let rest2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else if (t2 instanceof EffectExtend) {
          let other = t2;
          let l1 = t1[0];
          let r1 = t1[2];
          let lift1 = t1[1][0];
          let reply1 = t1[1][1];
          let $2 = rewrite_effect(l1, other, level, bindings, r1);
          if ($2 instanceof Ok) {
            let r2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let lift2 = $2[0][0][0];
            let reply2 = $2[0][0][1];
            let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else {
          let other = t2;
          let l1 = t1[0];
          let r1 = t1[2];
          let lift1 = t1[1][0];
          let reply1 = t1[1][1];
          let $2 = rewrite_effect(l1, other, level, bindings, r1);
          if ($2 instanceof Ok) {
            let r2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let lift2 = $2[0][0][0];
            let reply2 = $2[0][0][1];
            let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        }
      } else if (t1 instanceof Never) {
        if ($ instanceof Ok) {
          let $2 = $[0];
          if ($2 instanceof Bound) {
            let t1$1 = $2[0];
            loop$ts = prepend([t1$1, t2], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if ($1 instanceof Ok) {
            let $3 = $1[0];
            if ($3 instanceof Bound) {
              let t2$1 = $3[0];
              loop$ts = prepend([t1, t2$1], ts$1);
              loop$level = level;
              loop$bindings = bindings;
            } else if (t2 instanceof Var) {
              let other = t1;
              let level$1 = $3.level;
              let i = t2.key;
              let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
              if ($4 instanceof Ok) {
                let bindings$1 = $4[0];
                let bindings$2 = insert(bindings$1, i, new Bound(other));
                loop$ts = ts$1;
                loop$level = level$1;
                loop$bindings = bindings$2;
              } else {
                return $4;
              }
            } else if (t2 instanceof RowExtend) {
              let other = t1;
              let l1 = t2[0];
              let field1 = t2[1];
              let rest1 = t2[2];
              let $4 = rewrite_row(l1, other, level, bindings, rest1);
              if ($4 instanceof Ok) {
                let field2 = $4[0][0];
                let rest2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else if (t2 instanceof EffectExtend) {
              let other = t1;
              let l1 = t2[0];
              let r1 = t2[2];
              let lift1 = t2[1][0];
              let reply1 = t2[1][1];
              let $4 = rewrite_effect(l1, other, level, bindings, r1);
              if ($4 instanceof Ok) {
                let r2 = $4[0][1];
                let bindings$1 = $4[0][2];
                let lift2 = $4[0][0][0];
                let reply2 = $4[0][0][1];
                let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
                loop$ts = ts$2;
                loop$level = level;
                loop$bindings = bindings$1;
              } else {
                return $4;
              }
            } else if (t2 instanceof Never) {
              loop$ts = ts$1;
              loop$level = level;
              loop$bindings = bindings;
            } else {
              return new Error2(new TypeMismatch(t1, t2));
            }
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof Never) {
            loop$ts = ts$1;
            loop$level = level;
            loop$bindings = bindings;
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if ($1 instanceof Ok) {
          let $2 = $1[0];
          if ($2 instanceof Bound) {
            let t2$1 = $2[0];
            loop$ts = prepend([t1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof Var) {
            let other = t1;
            let level$1 = $2.level;
            let i = t2.key;
            let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
            if ($3 instanceof Ok) {
              let bindings$1 = $3[0];
              let bindings$2 = insert(bindings$1, i, new Bound(other));
              loop$ts = ts$1;
              loop$level = level$1;
              loop$bindings = bindings$2;
            } else {
              return $3;
            }
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $3 = rewrite_row(l1, other, level, bindings, rest1);
            if ($3 instanceof Ok) {
              let field2 = $3[0][0];
              let rest2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $3 = rewrite_effect(l1, other, level, bindings, r1);
            if ($3 instanceof Ok) {
              let r2 = $3[0][1];
              let bindings$1 = $3[0][2];
              let lift2 = $3[0][0][0];
              let reply2 = $3[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $3;
            }
          } else if (t2 instanceof Never) {
            loop$ts = ts$1;
            loop$level = level;
            loop$bindings = bindings;
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if (t2 instanceof RowExtend) {
          let other = t1;
          let l1 = t2[0];
          let field1 = t2[1];
          let rest1 = t2[2];
          let $2 = rewrite_row(l1, other, level, bindings, rest1);
          if ($2 instanceof Ok) {
            let field2 = $2[0][0];
            let rest2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else if (t2 instanceof EffectExtend) {
          let other = t1;
          let l1 = t2[0];
          let r1 = t2[2];
          let lift1 = t2[1][0];
          let reply1 = t2[1][1];
          let $2 = rewrite_effect(l1, other, level, bindings, r1);
          if ($2 instanceof Ok) {
            let r2 = $2[0][1];
            let bindings$1 = $2[0][2];
            let lift2 = $2[0][0][0];
            let reply2 = $2[0][0][1];
            let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $2;
          }
        } else if (t2 instanceof Never) {
          loop$ts = ts$1;
          loop$level = level;
          loop$bindings = bindings;
        } else {
          return new Error2(new TypeMismatch(t1, t2));
        }
      } else if ($ instanceof Ok) {
        let $2 = $[0];
        if ($2 instanceof Bound) {
          let t1$1 = $2[0];
          loop$ts = prepend([t1$1, t2], ts$1);
          loop$level = level;
          loop$bindings = bindings;
        } else if ($1 instanceof Ok) {
          let $3 = $1[0];
          if ($3 instanceof Bound) {
            let t2$1 = $3[0];
            loop$ts = prepend([t1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else if (t2 instanceof Var) {
            let other = t1;
            let level$1 = $3.level;
            let i = t2.key;
            let $4 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
            if ($4 instanceof Ok) {
              let bindings$1 = $4[0];
              let bindings$2 = insert(bindings$1, i, new Bound(other));
              loop$ts = ts$1;
              loop$level = level$1;
              loop$bindings = bindings$2;
            } else {
              return $4;
            }
          } else if (t2 instanceof RowExtend) {
            let other = t1;
            let l1 = t2[0];
            let field1 = t2[1];
            let rest1 = t2[2];
            let $4 = rewrite_row(l1, other, level, bindings, rest1);
            if ($4 instanceof Ok) {
              let field2 = $4[0][0];
              let rest2 = $4[0][1];
              let bindings$1 = $4[0][2];
              let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $4;
            }
          } else if (t2 instanceof EffectExtend) {
            let other = t1;
            let l1 = t2[0];
            let r1 = t2[2];
            let lift1 = t2[1][0];
            let reply1 = t2[1][1];
            let $4 = rewrite_effect(l1, other, level, bindings, r1);
            if ($4 instanceof Ok) {
              let r2 = $4[0][1];
              let bindings$1 = $4[0][2];
              let lift2 = $4[0][0][0];
              let reply2 = $4[0][0][1];
              let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
              loop$ts = ts$2;
              loop$level = level;
              loop$bindings = bindings$1;
            } else {
              return $4;
            }
          } else if (t2 instanceof Promise2) {
            let t1$1 = t1[0];
            let t2$1 = t2[0];
            loop$ts = prepend([t1$1, t2$1], ts$1);
            loop$level = level;
            loop$bindings = bindings;
          } else {
            return new Error2(new TypeMismatch(t1, t2));
          }
        } else if (t2 instanceof RowExtend) {
          let other = t1;
          let l1 = t2[0];
          let field1 = t2[1];
          let rest1 = t2[2];
          let $3 = rewrite_row(l1, other, level, bindings, rest1);
          if ($3 instanceof Ok) {
            let field2 = $3[0][0];
            let rest2 = $3[0][1];
            let bindings$1 = $3[0][2];
            let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $3;
          }
        } else if (t2 instanceof EffectExtend) {
          let other = t1;
          let l1 = t2[0];
          let r1 = t2[2];
          let lift1 = t2[1][0];
          let reply1 = t2[1][1];
          let $3 = rewrite_effect(l1, other, level, bindings, r1);
          if ($3 instanceof Ok) {
            let r2 = $3[0][1];
            let bindings$1 = $3[0][2];
            let lift2 = $3[0][0][0];
            let reply2 = $3[0][0][1];
            let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $3;
          }
        } else if (t2 instanceof Promise2) {
          let t1$1 = t1[0];
          let t2$1 = t2[0];
          loop$ts = prepend([t1$1, t2$1], ts$1);
          loop$level = level;
          loop$bindings = bindings;
        } else {
          return new Error2(new TypeMismatch(t1, t2));
        }
      } else if ($1 instanceof Ok) {
        let $2 = $1[0];
        if ($2 instanceof Bound) {
          let t2$1 = $2[0];
          loop$ts = prepend([t1, t2$1], ts$1);
          loop$level = level;
          loop$bindings = bindings;
        } else if (t2 instanceof Var) {
          let other = t1;
          let level$1 = $2.level;
          let i = t2.key;
          let $3 = do_occurs_and_levels(i, level$1, prepend(other, List$Empty$const), bindings);
          if ($3 instanceof Ok) {
            let bindings$1 = $3[0];
            let bindings$2 = insert(bindings$1, i, new Bound(other));
            loop$ts = ts$1;
            loop$level = level$1;
            loop$bindings = bindings$2;
          } else {
            return $3;
          }
        } else if (t2 instanceof RowExtend) {
          let other = t1;
          let l1 = t2[0];
          let field1 = t2[1];
          let rest1 = t2[2];
          let $3 = rewrite_row(l1, other, level, bindings, rest1);
          if ($3 instanceof Ok) {
            let field2 = $3[0][0];
            let rest2 = $3[0][1];
            let bindings$1 = $3[0][2];
            let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $3;
          }
        } else if (t2 instanceof EffectExtend) {
          let other = t1;
          let l1 = t2[0];
          let r1 = t2[2];
          let lift1 = t2[1][0];
          let reply1 = t2[1][1];
          let $3 = rewrite_effect(l1, other, level, bindings, r1);
          if ($3 instanceof Ok) {
            let r2 = $3[0][1];
            let bindings$1 = $3[0][2];
            let lift2 = $3[0][0][0];
            let reply2 = $3[0][0][1];
            let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
            loop$ts = ts$2;
            loop$level = level;
            loop$bindings = bindings$1;
          } else {
            return $3;
          }
        } else if (t2 instanceof Promise2) {
          let t1$1 = t1[0];
          let t2$1 = t2[0];
          loop$ts = prepend([t1$1, t2$1], ts$1);
          loop$level = level;
          loop$bindings = bindings;
        } else {
          return new Error2(new TypeMismatch(t1, t2));
        }
      } else if (t2 instanceof RowExtend) {
        let other = t1;
        let l1 = t2[0];
        let field1 = t2[1];
        let rest1 = t2[2];
        let $2 = rewrite_row(l1, other, level, bindings, rest1);
        if ($2 instanceof Ok) {
          let field2 = $2[0][0];
          let rest2 = $2[0][1];
          let bindings$1 = $2[0][2];
          let ts$2 = prepend([field1, field2], prepend([rest1, rest2], ts$1));
          loop$ts = ts$2;
          loop$level = level;
          loop$bindings = bindings$1;
        } else {
          return $2;
        }
      } else if (t2 instanceof EffectExtend) {
        let other = t1;
        let l1 = t2[0];
        let r1 = t2[2];
        let lift1 = t2[1][0];
        let reply1 = t2[1][1];
        let $2 = rewrite_effect(l1, other, level, bindings, r1);
        if ($2 instanceof Ok) {
          let r2 = $2[0][1];
          let bindings$1 = $2[0][2];
          let lift2 = $2[0][0][0];
          let reply2 = $2[0][0][1];
          let ts$2 = prepend([lift1, lift2], prepend([reply1, reply2], prepend([r1, r2], ts$1)));
          loop$ts = ts$2;
          loop$level = level;
          loop$bindings = bindings$1;
        } else {
          return $2;
        }
      } else if (t2 instanceof Promise2) {
        let t1$1 = t1[0];
        let t2$1 = t2[0];
        loop$ts = prepend([t1$1, t2$1], ts$1);
        loop$level = level;
        loop$bindings = bindings;
      } else {
        return new Error2(new TypeMismatch(t1, t2));
      }
    }
  }
}
function unify(t1, t2, level, bindings) {
  let $ = do_unify(prepend([t1, t2], List$Empty$const), level, bindings);
  if ($ instanceof Error2) {
    let $1 = $[0];
    if ($1 instanceof TypeMismatch && $1[0] instanceof Var && $1[1] instanceof Var) {
      return new Error2(new TypeMismatch(resolve(t1, bindings), resolve(t2, bindings)));
    } else {
      return $;
    }
  } else {
    return $;
  }
}

// build/dev/javascript/eyg_analysis/eyg/analysis/inference/levels_j/contextual.mjs
var FILEPATH7 = "src/eyg/analysis/inference/levels_j/contextual.gleam";

class Context extends CustomType {
  constructor(env, eff, level, bindings, expected_type) {
    super();
    this.env = env;
    this.eff = eff;
    this.level = level;
    this.bindings = bindings;
    this.expected_type = expected_type;
  }
}
class Analysis extends CustomType {
  constructor(bindings, tree, original) {
    super();
    this.bindings = bindings;
    this.tree = tree;
    this.original = original;
  }
}
class Done extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Lookup extends CustomType {
  constructor(reference2, resume) {
    super();
    this.reference = reference2;
    this.resume = resume;
  }
}
function pure() {
  let bindings = make();
  return new Context(List$Empty$const, Type$Empty$const, 1, bindings, Option$None$const);
}
function check_expected_type(analysis, expected, level) {
  let bindings = analysis.bindings;
  let tree = analysis.tree;
  let expression;
  let result2;
  let type_$1;
  let eff;
  let env;
  expression = tree[0];
  result2 = tree[1][0];
  type_$1 = tree[1][1];
  eff = tree[1][2];
  env = tree[1][3];
  let $ = unify(type_$1, expected, level, bindings);
  if ($ instanceof Ok) {
    let bindings$1 = $[0];
    return new Analysis(bindings$1, analysis.tree, analysis.original);
  } else {
    let reason = $[0];
    let _block;
    if (result2 instanceof Ok) {
      _block = new Error2(reason);
    } else {
      _block = result2;
    }
    let result$1 = _block;
    let tree$1 = [expression, [result$1, type_$1, eff, env]];
    return new Analysis(analysis.bindings, tree$1, analysis.original);
  }
}
function open_effect(eff, level, bindings) {
  if (eff instanceof Empty3) {
    return mono(level, bindings);
  } else if (eff instanceof EffectExtend) {
    let label = eff[0];
    let type_$1 = eff[1];
    let eff$1 = eff[2];
    let $ = open_effect(eff$1, level, bindings);
    let eff$2 = $[0];
    let bindings$1 = $[1];
    return [new EffectExtend(label, type_$1, eff$2), bindings$1];
  } else {
    let other = eff;
    return [other, bindings];
  }
}
function open(type_, level, bindings) {
  if (type_ instanceof Fun) {
    let args = type_[0];
    let eff = type_[1];
    let ret = type_[2];
    let $ = open_effect(eff, level, bindings);
    let eff$1 = $[0];
    let bindings$1 = $[1];
    let $1 = open(ret, level, bindings$1);
    let ret$1 = $1[0];
    let bindings$2 = $1[1];
    return [new Fun(args, eff$1, ret$1), bindings$2];
  } else {
    let other = type_;
    return [other, bindings];
  }
}
function prim(scheme, env, eff, level, bindings, exp2) {
  let $ = instantiate(scheme, level, bindings);
  let type_$1 = $[0];
  let bindings$1 = $[1];
  let $1 = open(type_$1, level, bindings$1);
  let t = $1[0];
  let bindings$2 = $1[1];
  let meta = [new Ok(undefined), type_$1, Type$Empty$const, env];
  return new Done([bindings$2, t, eff, [exp2, meta]]);
}
function lookup_ref(reference2, env, eff, level, bindings) {
  return new Lookup(reference2, (result2) => {
    if (result2 instanceof Ok) {
      let poly = result2[0];
      return prim(poly, env, eff, level, bindings, new Reference(reference2));
    } else {
      let $ = mono(level, bindings);
      let type_$1 = $[0];
      let bindings$1 = $[1];
      let meta = [
        new Error2(new MissingReference(reference2)),
        type_$1,
        Type$Empty$const,
        env
      ];
      return new Done([bindings$1, type_$1, eff, [new Reference(reference2), meta]]);
    }
  });
}
function pure2(arg1, arg2, ret) {
  return new Fun(arg1, Type$Empty$const, new Fun(arg2, Type$Empty$const, ret));
}
function q(i) {
  return new Var([true, i]);
}
function pure1(arg1, ret) {
  return new Fun(arg1, Type$Empty$const, ret);
}
function pure3(arg1, arg2, arg3, ret) {
  return new Fun(arg1, Type$Empty$const, new Fun(arg2, Type$Empty$const, new Fun(arg3, Type$Empty$const, ret)));
}
function fix() {
  let self = new Fun(q(0), q(1), q(2));
  return new Fun(new Fun(self, Type$Empty$const, self), Type$Empty$const, self);
}
function builtins() {
  return toList([
    ["equal", pure2(q(0), q(0), boolean)],
    ["fix", fix()],
    ["never", pure1(Type$Never$const, q(1))],
    [
      "int_compare",
      (() => {
        let return$2 = union2(prepend(["Lt", unit], prepend(["Eq", unit], prepend(["Gt", unit], List$Empty$const))));
        return pure2(Type$Integer$const, Type$Integer$const, return$2);
      })()
    ],
    [
      "int_add",
      pure2(Type$Integer$const, Type$Integer$const, Type$Integer$const)
    ],
    [
      "int_subtract",
      pure2(Type$Integer$const, Type$Integer$const, Type$Integer$const)
    ],
    [
      "int_multiply",
      pure2(Type$Integer$const, Type$Integer$const, Type$Integer$const)
    ],
    [
      "int_divide",
      pure2(Type$Integer$const, Type$Integer$const, result(Type$Integer$const, unit))
    ],
    ["int_absolute", pure1(Type$Integer$const, Type$Integer$const)],
    [
      "int_parse",
      pure1(Type$String$const, result(Type$Integer$const, unit))
    ],
    ["int_to_string", pure1(Type$Integer$const, Type$String$const)],
    [
      "string_append",
      pure2(Type$String$const, Type$String$const, Type$String$const)
    ],
    [
      "string_split",
      (() => {
        let return$2 = record(prepend(["head", Type$String$const], prepend(["tail", new List2(Type$String$const)], List$Empty$const)));
        return pure2(Type$String$const, Type$String$const, return$2);
      })()
    ],
    [
      "string_split_once",
      (() => {
        let return$2 = record(prepend(["pre", Type$String$const], prepend(["post", Type$String$const], List$Empty$const)));
        return pure2(Type$String$const, Type$String$const, result(return$2, unit));
      })()
    ],
    [
      "string_replace",
      pure3(Type$String$const, Type$String$const, Type$String$const, Type$String$const)
    ],
    ["string_uppercase", pure1(Type$String$const, Type$String$const)],
    ["string_lowercase", pure1(Type$String$const, Type$String$const)],
    [
      "string_starts_with",
      pure2(Type$String$const, Type$String$const, boolean)
    ],
    [
      "string_ends_with",
      pure2(Type$String$const, Type$String$const, boolean)
    ],
    ["string_length", pure1(Type$String$const, Type$Integer$const)],
    ["string_to_binary", pure1(Type$String$const, Type$Binary$const)],
    [
      "string_from_binary",
      pure1(Type$Binary$const, result(Type$String$const, unit))
    ],
    [
      "binary_from_integers",
      pure1(new List2(Type$Integer$const), Type$Binary$const)
    ],
    ["binary_size", pure1(Type$Binary$const, Type$Integer$const)],
    [
      "binary_concat",
      pure2(Type$Binary$const, Type$Binary$const, Type$Binary$const)
    ],
    [
      "binary_compare",
      (() => {
        let return$2 = union2(prepend(["Lt", unit], prepend(["Eq", unit], prepend(["Gt", unit], List$Empty$const))));
        return pure2(Type$Binary$const, Type$Binary$const, return$2);
      })()
    ],
    [
      "binary_fold",
      (() => {
        let acc = q(1);
        let eff = q(2);
        let reducer = new Fun(Type$Integer$const, eff, new Fun(acc, eff, acc));
        return pure2(Type$Binary$const, acc, new Fun(reducer, eff, acc));
      })()
    ],
    [
      "list_pop",
      (() => {
        let return$2 = record(prepend(["head", q(0)], prepend(["tail", new List2(q(0))], List$Empty$const)));
        return pure1(new List2(q(0)), result(return$2, unit));
      })()
    ],
    [
      "list_fold",
      (() => {
        let el = q(0);
        let acc = q(1);
        let eff = q(2);
        let reducer = new Fun(el, eff, new Fun(acc, eff, acc));
        return pure2(new List2(el), acc, new Fun(reducer, eff, acc));
      })()
    ]
  ]);
}
function builtin(name) {
  return key_find(builtins(), name);
}
function handle(label) {
  let lift = q(0);
  let reply = q(1);
  let tail = q(2);
  let return$2 = q(3);
  let kont = new Fun(reply, tail, return$2);
  let handler = new Fun(lift, Type$Empty$const, new Fun(kont, tail, return$2));
  let exec = new Fun(new Record(Type$Empty$const), new EffectExtend(label, [lift, reply], tail), return$2);
  return new Fun(handler, Type$Empty$const, new Fun(exec, tail, return$2));
}
function perform(l) {
  return new Fun(q(0), new EffectExtend(l, [q(0), q(1)], Type$Empty$const), q(1));
}
function nocases() {
  return pure1(new Union(Type$Empty$const), q(0));
}
function case_(label) {
  let inner = q(0);
  let eff = q(1);
  let return$2 = q(2);
  let tail = q(3);
  let input = new Union(new RowExtend(label, inner, tail));
  let branch = new Fun(inner, eff, return$2);
  let otherwise = new Fun(new Union(tail), eff, return$2);
  let exec = new Fun(input, eff, return$2);
  return pure2(branch, otherwise, exec);
}
function tag(l) {
  return pure1(q(0), new Union(new RowExtend(l, q(0), q(1))));
}
function select(l) {
  return pure1(new Record(new RowExtend(l, q(0), q(1))), q(0));
}
function overwrite(l) {
  return pure2(q(0), new Record(new RowExtend(l, q(1), q(2))), new Record(new RowExtend(l, q(0), q(2))));
}
function extend(l) {
  return pure2(q(0), new Record(q(1)), new Record(new RowExtend(l, q(0), q(1))));
}
function cons() {
  return pure2(q(0), new List2(q(0)), new List2(q(0)));
}
function bind(step, f) {
  if (step instanceof Done) {
    let value = step[0];
    return f(value);
  } else {
    let reference2 = step.reference;
    let resume = step.resume;
    return new Lookup(reference2, (answer) => {
      return bind(resume(answer), f);
    });
  }
}
function ftv(loop$type_) {
  while (true) {
    let type_ = loop$type_;
    if (type_ instanceof Var) {
      let x = type_.key;
      return from_list2(prepend(x, List$Empty$const));
    } else if (type_ instanceof Fun) {
      let arg = type_[0];
      let eff = type_[1];
      let ret = type_[2];
      return union(ftv(arg), union(ftv(eff), ftv(ret)));
    } else if (type_ instanceof Binary2) {
      return new$2();
    } else if (type_ instanceof Integer2) {
      return new$2();
    } else if (type_ instanceof String3) {
      return new$2();
    } else if (type_ instanceof List2) {
      let el = type_[0];
      loop$type_ = el;
    } else if (type_ instanceof Record) {
      let rows2 = type_[0];
      loop$type_ = rows2;
    } else if (type_ instanceof Union) {
      let inner = type_[0];
      loop$type_ = inner;
    } else if (type_ instanceof Empty3) {
      return new$2();
    } else if (type_ instanceof RowExtend) {
      let field2 = type_[1];
      let tail = type_[2];
      return union(ftv(field2), ftv(tail));
    } else if (type_ instanceof EffectExtend) {
      let tail = type_[2];
      let lift = type_[1][0];
      let reply = type_[1][1];
      return union(ftv(lift), union(ftv(reply), ftv(tail)));
    } else if (type_ instanceof Never) {
      return new$2();
    } else {
      let inner = type_[0];
      loop$type_ = inner;
    }
  }
}
function eff_tail(eff) {
  if (eff instanceof Var) {
    let x = eff.key;
    return [new Ok(x), Type$Empty$const];
  } else if (eff instanceof EffectExtend) {
    let l = eff[0];
    let f = eff[1];
    let tail = eff[2];
    let $ = eff_tail(tail);
    let result2 = $[0];
    let tail$1 = $[1];
    return [result2, new EffectExtend(l, f, tail$1)];
  } else {
    return [new Error2(undefined), eff];
  }
}
function close_eff(arg, eff, ret, level, bindings) {
  let $ = eff_tail(eff);
  let last2 = $[0];
  let mapped = $[1];
  if (last2 instanceof Ok) {
    let i = last2[0];
    let $1 = get(bindings, i);
    let l;
    if ($1 instanceof Ok) {
      let $2 = $1[0];
      if ($2 instanceof Unbound) {
        l = $2.level;
      } else {
        throw makeError("let_assert", FILEPATH7, "eyg/analysis/inference/levels_j/contextual", 257, "close_eff", "Pattern match failed, no pattern matched the value.", {
          value: $1,
          start: 6997,
          end: 7054,
          pattern_start: 7008,
          pattern_end: 7030
        });
      }
    } else {
      throw makeError("let_assert", FILEPATH7, "eyg/analysis/inference/levels_j/contextual", 257, "close_eff", "Pattern match failed, no pattern matched the value.", {
        value: $1,
        start: 6997,
        end: 7054,
        pattern_start: 7008,
        pattern_end: 7030
      });
    }
    let $3 = !contains2(union(ftv(arg), ftv(ret)), i) && l > level;
    if ($3) {
      return mapped;
    } else {
      return eff;
    }
  } else {
    return eff;
  }
}
function close(type_, level, bindings) {
  let $ = resolve(type_, bindings);
  if ($ instanceof Fun) {
    let arg = $[0];
    let eff = $[1];
    let ret = $[2];
    let eff$1 = close_eff(arg, eff, ret, level, bindings);
    return new Fun(arg, eff$1, close(ret, level, bindings));
  } else {
    return type_;
  }
}
function do_infer(source, env, eff, level, bindings) {
  let exp2 = source[0];
  if (exp2 instanceof Variable) {
    let x = exp2.label;
    let $ = key_find(env, x);
    if ($ instanceof Ok) {
      let scheme = $[0];
      let $1 = instantiate(scheme, level, bindings);
      let type_$1 = $1[0];
      let bindings$1 = $1[1];
      let $2 = open(type_$1, level, bindings$1);
      let type_$2 = $2[0];
      let bindings$2 = $2[1];
      let meta = [new Ok(undefined), type_$2, Type$Empty$const, env];
      return new Done([bindings$2, type_$2, eff, [new Variable(x), meta]]);
    } else {
      let $1 = mono(level, bindings);
      let type_$1 = $1[0];
      let bindings$1 = $1[1];
      let meta = [
        new Error2(new MissingVariable(x)),
        type_$1,
        Type$Empty$const,
        env
      ];
      return new Done([bindings$1, type_$1, eff, [new Variable(x), meta]]);
    }
  } else if (exp2 instanceof Lambda) {
    let x = exp2.label;
    let body = exp2.body;
    let $ = mono(level, bindings);
    let type_x = $[0];
    let bindings$1 = $[1];
    let i;
    if (type_x instanceof Var) {
      i = type_x.key;
    } else {
      throw makeError("let_assert", FILEPATH7, "eyg/analysis/inference/levels_j/contextual", 316, "do_infer", "Pattern match failed, no pattern matched the value.", {
        value: type_x,
        start: 8645,
        end: 8673,
        pattern_start: 8656,
        pattern_end: 8664
      });
    }
    let scheme_x = new Var([false, i]);
    let level$1 = level + 1;
    let $1 = mono(level$1, bindings$1);
    let type_eff = $1[0];
    let bindings$2 = $1[1];
    return bind(do_infer(body, prepend([x, scheme_x], env), type_eff, level$1, bindings$2), (_use0) => {
      let bindings$3 = _use0[0];
      let type_r = _use0[1];
      let type_eff$1 = _use0[2];
      let inner = _use0[3];
      let type_$1 = new Fun(type_x, type_eff$1, type_r);
      let level$2 = level$1 - 1;
      let record2 = close(type_$1, level$2, bindings$3);
      let meta = [new Ok(undefined), record2, Type$Empty$const, env];
      return new Done([bindings$3, type_$1, eff, [new Lambda(x, inner), meta]]);
    });
  } else if (exp2 instanceof Apply) {
    let fun = exp2.func;
    let arg = exp2.argument;
    let level$1 = level + 1;
    return bind(do_infer(fun, env, eff, level$1, bindings), (_use0) => {
      let bindings$1 = _use0[0];
      let ty_fun = _use0[1];
      let eff$1 = _use0[2];
      let fun$1 = _use0[3];
      return bind(do_infer(arg, env, eff$1, level$1, bindings$1), (_use02) => {
        let bindings$2 = _use02[0];
        let ty_arg = _use02[1];
        let eff$2 = _use02[2];
        let arg$1 = _use02[3];
        let $ = mono(level$1, bindings$2);
        let ty_ret = $[0];
        let bindings$3 = $[1];
        let $1 = mono(level$1, bindings$3);
        let test_eff = $1[0];
        let bindings$4 = $1[1];
        let _block;
        let $3 = unify(new Fun(ty_arg, test_eff, ty_ret), ty_fun, level$1, bindings$4);
        if ($3 instanceof Ok) {
          let bindings$52 = $3[0];
          _block = [bindings$52, new Ok(undefined)];
        } else {
          let reason = $3[0];
          _block = [bindings$4, new Error2(reason)];
        }
        let $2 = _block;
        let bindings$5 = $2[0];
        let result2 = $2[1];
        let level$2 = level$1 - 1;
        let $4 = eff_tail(resolve(test_eff, bindings$5));
        let last2 = $4[0];
        let mapped = $4[1];
        let _block$1;
        if (last2 instanceof Ok) {
          let i = last2[0];
          let $52 = get(bindings$5, i);
          let binding;
          if ($52 instanceof Ok) {
            binding = $52[0];
          } else {
            throw makeError("let_assert", FILEPATH7, "eyg/analysis/inference/levels_j/contextual", 372, "do_infer", "Pattern match failed, no pattern matched the value.", {
              value: $52,
              start: 10479,
              end: 10525,
              pattern_start: 10490,
              pattern_end: 10501
            });
          }
          let level$3 = level$2 - 1;
          if (binding instanceof Unbound) {
            let l = binding.level;
            if (l > level$3) {
              _block$1 = mapped;
            } else {
              _block$1 = test_eff;
            }
          } else {
            _block$1 = test_eff;
          }
        } else {
          _block$1 = test_eff;
        }
        let raised = _block$1;
        let _block$2;
        let $6 = unify(test_eff, eff$2, level$2, bindings$5);
        if ($6 instanceof Ok) {
          let bindings$62 = $6[0];
          _block$2 = [bindings$62, result2];
        } else {
          let reason = $6[0];
          _block$2 = [
            bindings$5,
            (() => {
              if (result2 instanceof Ok) {
                return new Error2(reason);
              } else {
                return result2;
              }
            })()
          ];
        }
        let $5 = _block$2;
        let bindings$6 = $5[0];
        let result$1 = $5[1];
        let record2 = close(ty_ret, level$2, bindings$6);
        let meta = [result$1, record2, raised, env];
        return new Done([bindings$6, ty_ret, eff$2, [new Apply(fun$1, arg$1), meta]]);
      });
    });
  } else if (exp2 instanceof Let) {
    let label = exp2.label;
    let value = exp2.definition;
    let then$2 = exp2.body;
    let level$1 = level + 1;
    return bind(do_infer(value, env, eff, level$1, bindings), (_use0) => {
      let bindings$1 = _use0[0];
      let ty_value = _use0[1];
      let eff$1 = _use0[2];
      let value$1 = _use0[3];
      let level$2 = level$1 - 1;
      let sch_value = gen(close(ty_value, level$2, bindings$1), level$2, bindings$1);
      return bind(do_infer(then$2, prepend([label, sch_value], env), eff$1, level$2, bindings$1), (_use02) => {
        let bindings$2 = _use02[0];
        let ty_then = _use02[1];
        let eff$2 = _use02[2];
        let then$1 = _use02[3];
        let meta = [new Ok(undefined), ty_then, Type$Empty$const, env];
        return new Done([
          bindings$2,
          ty_then,
          eff$2,
          [new Let(label, value$1, then$1), meta]
        ]);
      });
    });
  } else if (exp2 instanceof Binary) {
    let value = exp2.value;
    return prim(Type$Binary$const, env, eff, level, bindings, new Binary(value));
  } else if (exp2 instanceof Integer) {
    let value = exp2.value;
    return prim(Type$Integer$const, env, eff, level, bindings, new Integer(value));
  } else if (exp2 instanceof String2) {
    let value = exp2.value;
    return prim(Type$String$const, env, eff, level, bindings, new String2(value));
  } else if (exp2 instanceof Tail) {
    return prim(new List2(q(0)), env, eff, level, bindings, Expression$Tail$const);
  } else if (exp2 instanceof Cons) {
    return prim(cons(), env, eff, level, bindings, Expression$Cons$const);
  } else if (exp2 instanceof Vacant) {
    let $ = mono(level, bindings);
    let type_$1 = $[0];
    let bindings$1 = $[1];
    let meta = [
      new Error2(Reason$Todo$const),
      type_$1,
      Type$Empty$const,
      env
    ];
    return new Done([bindings$1, type_$1, eff, [Expression$Vacant$const, meta]]);
  } else if (exp2 instanceof Empty2) {
    return prim(new Record(Type$Empty$const), env, eff, level, bindings, Expression$Empty$const);
  } else if (exp2 instanceof Extend) {
    let label = exp2.label;
    return prim(extend(label), env, eff, level, bindings, new Extend(label));
  } else if (exp2 instanceof Select) {
    let label = exp2.label;
    return prim(select(label), env, eff, level, bindings, new Select(label));
  } else if (exp2 instanceof Overwrite) {
    let label = exp2.label;
    return prim(overwrite(label), env, eff, level, bindings, new Overwrite(label));
  } else if (exp2 instanceof Tag) {
    let label = exp2.label;
    return prim(tag(label), env, eff, level, bindings, new Tag(label));
  } else if (exp2 instanceof Case) {
    let label = exp2.label;
    return prim(case_(label), env, eff, level, bindings, new Case(label));
  } else if (exp2 instanceof NoCases) {
    return prim(nocases(), env, eff, level, bindings, Expression$NoCases$const);
  } else if (exp2 instanceof Perform) {
    let label = exp2.label;
    return prim(perform(label), env, eff, level, bindings, new Perform(label));
  } else if (exp2 instanceof Handle) {
    let label = exp2.label;
    return prim(handle(label), env, eff, level, bindings, new Handle(label));
  } else if (exp2 instanceof Builtin) {
    let id = exp2.identifier;
    let $ = builtin(id);
    if ($ instanceof Ok) {
      let poly = $[0];
      return prim(poly, env, eff, level, bindings, new Builtin(id));
    } else {
      let $1 = mono(level, bindings);
      let type_$1 = $1[0];
      let bindings$1 = $1[1];
      let meta = [
        new Error2(new MissingBuiltin(id)),
        type_$1,
        Type$Empty$const,
        env
      ];
      return new Done([bindings$1, type_$1, eff, [new Builtin(id), meta]]);
    }
  } else {
    let reference2 = exp2.reference;
    return lookup_ref(reference2, env, eff, level, bindings);
  }
}
function check(context, source) {
  let env = context.env;
  let eff = context.eff;
  let level = context.level;
  let bindings = context.bindings;
  let expected_type = context.expected_type;
  return bind(do_infer(source, env, eff, level, bindings), (_use0) => {
    let bindings$1 = _use0[0];
    let tree = _use0[3];
    let analysis = new Analysis(bindings$1, tree, source);
    return new Done((() => {
      if (expected_type instanceof Some) {
        let expected = expected_type[0];
        return check_expected_type(analysis, expected, level);
      } else {
        return analysis;
      }
    })());
  });
}
function loop_with_references(loop$step, loop$refs) {
  while (true) {
    let step = loop$step;
    let refs = loop$refs;
    if (step instanceof Done) {
      let analysis = step[0];
      return analysis;
    } else {
      let reference2 = step.reference;
      let resume = step.resume;
      let _block;
      if (reference2 instanceof Content) {
        let cid = reference2.cid;
        _block = get(refs, cid);
      } else if (reference2 instanceof Pinned) {
        let cid = reference2.release.module;
        _block = get(refs, cid);
      } else {
        _block = new Error2(undefined);
      }
      let result2 = _block;
      loop$step = resume(result2);
      loop$refs = refs;
    }
  }
}
function check_with_references(context, refs, source) {
  return loop_with_references(check(context, source), refs);
}
function poly_type(inference) {
  let bindings = inference.bindings;
  let acc = inference.tree;
  let type_$1;
  type_$1 = acc[1][1];
  let mono2 = resolve(type_$1, bindings);
  return gen(mono2, 0, bindings);
}
// build/dev/javascript/eyg_interpreter/eyg/interpreter/value.mjs
class Binary3 extends CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}
class Integer3 extends CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}
class String4 extends CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}
class LinkedList extends CustomType {
  constructor(elements) {
    super();
    this.elements = elements;
  }
}
class Record2 extends CustomType {
  constructor(fields) {
    super();
    this.fields = fields;
  }
}
class Tagged extends CustomType {
  constructor(label, value) {
    super();
    this.label = label;
    this.value = value;
  }
}
class Closure extends CustomType {
  constructor(param, body, env) {
    super();
    this.param = param;
    this.body = body;
    this.env = env;
  }
}
class Partial extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class Cons2 extends CustomType {
}
var Switch$Cons$const = new Cons2;
class Extend2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Overwrite2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Select2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Tag2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Match extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class NoCases2 extends CustomType {
}
var Switch$NoCases$const = new NoCases2;
class Perform2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Handle2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Resume extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Builtin2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
function unit2() {
  return new Record2(make());
}
function true$() {
  return new Tagged("True", unit2());
}
function false$() {
  return new Tagged("False", unit2());
}
function bool2(in$) {
  if (in$) {
    return true$();
  } else {
    return false$();
  }
}
function ok(value) {
  return new Tagged("Ok", value);
}
function error(reason) {
  return new Tagged("Error", reason);
}
function some(value) {
  return new Tagged("Some", value);
}
function none() {
  return new Tagged("None", unit2());
}

// build/dev/javascript/eyg_interpreter/eyg/interpreter/break.mjs
class NotAFunction extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class UndefinedVariable extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class UndefinedBuiltin extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class UndefinedReference extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Vacant2 extends CustomType {
}
var Reason$Vacant$const = new Vacant2;
class NoMatch extends CustomType {
  constructor(term) {
    super();
    this.term = term;
  }
}
class UnhandledEffect extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class IncorrectTerm extends CustomType {
  constructor(expected, got) {
    super();
    this.expected = expected;
    this.got = got;
  }
}
class MissingField extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Unrepresentable extends CustomType {
  constructor(builtin2, args) {
    super();
    this.builtin = builtin2;
    this.args = args;
  }
}

// build/dev/javascript/eyg_ir/eyg/ir/integer_ffi.mjs
function isSafeInteger(value) {
  return Number.isSafeInteger(value);
}

// build/dev/javascript/eyg_interpreter/eyg/interpreter/cast.mjs
function map5(f, then$2) {
  return (raw) => {
    return map4(f(raw), then$2);
  };
}
function as_integer(value) {
  if (value instanceof Integer3) {
    let value$1 = value.value;
    return new Ok(value$1);
  } else {
    return new Error2(new IncorrectTerm("Integer", value));
  }
}
function as_string(value) {
  if (value instanceof String4) {
    let value$1 = value.value;
    return new Ok(value$1);
  } else {
    return new Error2(new IncorrectTerm("String", value));
  }
}
function as_binary(value) {
  if (value instanceof Binary3) {
    let value$1 = value.value;
    return new Ok(value$1);
  } else {
    return new Error2(new IncorrectTerm("Binary", value));
  }
}
function as_list(value) {
  if (value instanceof LinkedList) {
    let elements = value.elements;
    return new Ok(elements);
  } else {
    return new Error2(new IncorrectTerm("List", value));
  }
}
function as_list_of(value, decoder) {
  if (value instanceof LinkedList) {
    let elements = value.elements;
    return try_map(elements, decoder);
  } else {
    return new Error2(new IncorrectTerm("List", value));
  }
}
function as_record(value) {
  if (value instanceof Record2) {
    let fields = value.fields;
    return new Ok(fields);
  } else {
    return new Error2(new IncorrectTerm("Record", value));
  }
}
function as_unit(value, is) {
  return try$(as_record(value), (fields) => {
    let $ = size(fields);
    if ($ === 0) {
      return new Ok(is);
    } else {
      return new Error2(new MissingField("actually to many fields"));
    }
  });
}
function field2(key, inner, value) {
  return try$(as_record(value), (fields) => {
    let $ = get(fields, key);
    if ($ instanceof Ok) {
      let value$1 = $[0];
      return inner(value$1);
    } else {
      return new Error2(new MissingField(key));
    }
  });
}
function as_tagged(value) {
  if (value instanceof Tagged) {
    let label = value.label;
    let inner = value.value;
    return new Ok([label, inner]);
  } else {
    return new Error2(new IncorrectTerm("Tagged", value));
  }
}
function as_varient(value, decoders) {
  return try$(as_tagged(value), (_use0) => {
    let tag2 = _use0[0];
    let inner = _use0[1];
    let $ = key_find(decoders, tag2);
    if ($ instanceof Ok) {
      let decoder = $[0];
      return decoder(inner);
    } else {
      return new Error2(new IncorrectTerm("Variant better error needed", value));
    }
  });
}
function as_option(value, decoder) {
  return as_varient(value, prepend([
    "Some",
    (inner) => {
      return try$(decoder(inner), (inner2) => {
        return new Ok(new Some(inner2));
      });
    }
  ], prepend(["None", (_capture) => {
    return as_unit(_capture, Option$None$const);
  }], List$Empty$const)));
}

// build/dev/javascript/eyg_interpreter/eyg/interpreter/state.mjs
class E extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class V extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Loop extends CustomType {
  constructor($0, $1, $2) {
    super();
    this[0] = $0;
    this[1] = $1;
    this[2] = $2;
  }
}
class Break extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Env extends CustomType {
  constructor(scope, builtins2) {
    super();
    this.scope = scope;
    this.builtins = builtins2;
  }
}
class Arity1 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Arity2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Arity3 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Arity4 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Stack extends CustomType {
  constructor($0, $1, $2) {
    super();
    this[0] = $0;
    this[1] = $1;
    this[2] = $2;
  }
}
class Empty4 extends CustomType {
}
var Stack$Empty$const = new Empty4;
class Arg extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class Apply2 extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class Assign extends CustomType {
  constructor($0, $1, $2) {
    super();
    this[0] = $0;
    this[1] = $1;
    this[2] = $2;
  }
}
class CallWith extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class Delimit extends CustomType {
  constructor($0, $1, $2, $3) {
    super();
    this[0] = $0;
    this[1] = $1;
    this[2] = $2;
    this[3] = $3;
  }
}
class Trace extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
function call_builtin(key, applied, meta, env, kont) {
  let $ = get(env.builtins, key);
  if ($ instanceof Ok) {
    let func = $[0];
    if (applied instanceof Empty) {
      return new Ok([new V(new Partial(new Builtin2(key), applied)), env, kont]);
    } else {
      let $1 = applied.tail;
      if ($1 instanceof Empty) {
        if (func instanceof Arity1) {
          let x = applied.head;
          let impl = func[0];
          return impl(x, meta, env, kont);
        } else {
          return new Ok([new V(new Partial(new Builtin2(key), applied)), env, kont]);
        }
      } else {
        let $2 = $1.tail;
        if ($2 instanceof Empty) {
          if (func instanceof Arity2) {
            let x = applied.head;
            let y = $1.head;
            let impl = func[0];
            return impl(x, y, meta, env, kont);
          } else {
            return new Ok([new V(new Partial(new Builtin2(key), applied)), env, kont]);
          }
        } else {
          let $3 = $2.tail;
          if ($3 instanceof Empty) {
            if (func instanceof Arity3) {
              let x = applied.head;
              let y = $1.head;
              let z = $2.head;
              let impl = func[0];
              return impl(x, y, z, meta, env, kont);
            } else {
              return new Ok([new V(new Partial(new Builtin2(key), applied)), env, kont]);
            }
          } else if ($3.tail instanceof Empty && func instanceof Arity4) {
            let x = applied.head;
            let y = $1.head;
            let z = $2.head;
            let a = $3.head;
            let impl = func[0];
            return impl(x, y, z, a, meta, env, kont);
          } else {
            return new Ok([new V(new Partial(new Builtin2(key), applied)), env, kont]);
          }
        }
      }
    }
  } else {
    return new Error2(new UndefinedBuiltin(key));
  }
}
function move(loop$delimited, loop$acc) {
  while (true) {
    let delimited = loop$delimited;
    let acc = loop$acc;
    if (delimited instanceof Empty) {
      return acc;
    } else {
      let rest = delimited.tail;
      let step$1 = delimited.head[0];
      let meta = delimited.head[1];
      loop$delimited = rest;
      loop$acc = new Stack(step$1, meta, acc);
    }
  }
}
function do_perform(loop$label, loop$arg, loop$i_env, loop$k, loop$acc) {
  while (true) {
    let label = loop$label;
    let arg = loop$arg;
    let i_env = loop$i_env;
    let k = loop$k;
    let acc = loop$acc;
    if (k instanceof Stack) {
      let $ = k[0];
      if ($ instanceof Delimit) {
        let l = $[0];
        if (l === label) {
          let meta = k[1];
          let rest = k[2];
          let h = $[1];
          let e = $[2];
          let shallow = $[3];
          let _block;
          if (shallow) {
            _block = acc;
          } else {
            _block = prepend([new Delimit(label, h, e, false), meta], acc);
          }
          let acc$1 = _block;
          let resume = new Partial(new Resume([acc$1, i_env]), List$Empty$const);
          let k$1 = new Stack(new CallWith(arg, e), meta, new Stack(new CallWith(resume, e), meta, rest));
          return new Ok([new V(h), e, k$1]);
        } else {
          let kontinue = $;
          let meta$1 = k[1];
          let rest$1 = k[2];
          loop$label = label;
          loop$arg = arg;
          loop$i_env = i_env;
          loop$k = rest$1;
          loop$acc = prepend([kontinue, meta$1], acc);
        }
      } else {
        let kontinue = $;
        let meta = k[1];
        let rest = k[2];
        loop$label = label;
        loop$arg = arg;
        loop$i_env = i_env;
        loop$k = rest;
        loop$acc = prepend([kontinue, meta], acc);
      }
    } else {
      return new Error2(new UnhandledEffect(label, arg));
    }
  }
}
function perform2(label, arg, i_env, k) {
  return do_perform(label, arg, i_env, k, List$Empty$const);
}
function deep(label, handle2, exec, meta, env, k) {
  let k$1 = new Stack(new Delimit(label, handle2, env, false), meta, k);
  return call(exec, unit2(), meta, env, k$1);
}
function call(f, arg, meta, env, k) {
  if (f instanceof Closure) {
    let param = f.param;
    let body = f.body;
    let captured = f.env;
    let k$1 = new Stack(new Trace(arg, env), meta, k);
    let env$1 = new Env(prepend([param, arg], captured), env.builtins);
    return new Ok([new E(body), env$1, k$1]);
  } else if (f instanceof Partial) {
    let switch$ = f[0];
    let applied = f[1];
    if (applied instanceof Empty) {
      if (switch$ instanceof Select2) {
        let label = switch$[0];
        return try$(as_record(arg), (fields) => {
          return try$((() => {
            let _pipe = get(fields, label);
            return replace_error(_pipe, new MissingField(label));
          })(), (value) => {
            return new Ok([new V(value), env, k]);
          });
        });
      } else if (switch$ instanceof Tag2) {
        let label = switch$[0];
        return new Ok([new V(new Tagged(label, arg)), env, k]);
      } else if (switch$ instanceof NoCases2) {
        return new Error2(new NoMatch(arg));
      } else if (switch$ instanceof Perform2) {
        let label = switch$[0];
        return perform2(label, arg, env, k);
      } else if (switch$ instanceof Resume) {
        let popped = switch$[0][0];
        let captured = switch$[0][1];
        let k$1 = new Stack(new Trace(arg, env), meta, k);
        return new Ok([new V(arg), captured, move(popped, k$1)]);
      } else if (switch$ instanceof Builtin2) {
        let applied$1 = applied;
        let key = switch$[0];
        return call_builtin(key, append3(applied$1, prepend(arg, List$Empty$const)), meta, env, k);
      } else {
        let switch$1 = switch$;
        let applied$1 = append3(applied, prepend(arg, List$Empty$const));
        return new Ok([new V(new Partial(switch$1, applied$1)), env, k]);
      }
    } else {
      let $ = applied.tail;
      if ($ instanceof Empty) {
        if (switch$ instanceof Cons2) {
          let item = applied.head;
          return try$(as_list(arg), (elements) => {
            return new Ok([new V(new LinkedList(prepend(item, elements))), env, k]);
          });
        } else if (switch$ instanceof Extend2) {
          let value = applied.head;
          let label = switch$[0];
          return try$(as_record(arg), (fields) => {
            let fields$1 = insert(fields, label, value);
            return new Ok([new V(new Record2(fields$1)), env, k]);
          });
        } else if (switch$ instanceof Overwrite2) {
          let value = applied.head;
          let label = switch$[0];
          return try$(as_record(arg), (fields) => {
            return try$((() => {
              let _pipe = get(fields, label);
              return replace_error(_pipe, new MissingField(label));
            })(), (_) => {
              let fields$1 = insert(fields, label, value);
              return new Ok([new V(new Record2(fields$1)), env, k]);
            });
          });
        } else if (switch$ instanceof Handle2) {
          let handler = applied.head;
          let label = switch$[0];
          return deep(label, handler, arg, meta, env, k);
        } else if (switch$ instanceof Builtin2) {
          let applied$1 = applied;
          let key = switch$[0];
          return call_builtin(key, append3(applied$1, prepend(arg, List$Empty$const)), meta, env, k);
        } else {
          let switch$1 = switch$;
          let applied$1 = append3(applied, prepend(arg, List$Empty$const));
          return new Ok([new V(new Partial(switch$1, applied$1)), env, k]);
        }
      } else if ($.tail instanceof Empty) {
        if (switch$ instanceof Match) {
          let branch = applied.head;
          let otherwise = $.head;
          let label = switch$[0];
          return try$(as_tagged(arg), (_use0) => {
            let l = _use0[0];
            let inner = _use0[1];
            let $1 = l === label;
            if ($1) {
              return call(branch, inner, meta, env, k);
            } else {
              return call(otherwise, arg, meta, env, k);
            }
          });
        } else if (switch$ instanceof Builtin2) {
          let applied$1 = applied;
          let key = switch$[0];
          return call_builtin(key, append3(applied$1, prepend(arg, List$Empty$const)), meta, env, k);
        } else {
          let switch$1 = switch$;
          let applied$1 = append3(applied, prepend(arg, List$Empty$const));
          return new Ok([new V(new Partial(switch$1, applied$1)), env, k]);
        }
      } else if (switch$ instanceof Builtin2) {
        let applied$1 = applied;
        let key = switch$[0];
        return call_builtin(key, append3(applied$1, prepend(arg, List$Empty$const)), meta, env, k);
      } else {
        let switch$1 = switch$;
        let applied$1 = append3(applied, prepend(arg, List$Empty$const));
        return new Ok([new V(new Partial(switch$1, applied$1)), env, k]);
      }
    }
  } else {
    let term = f;
    return new Error2(new NotAFunction(term));
  }
}
function apply(value, env, k, meta, rest) {
  let _block;
  if (k instanceof Arg) {
    let arg = k[0];
    let env$1 = k[1];
    _block = new Ok([new E(arg), env$1, new Stack(new Apply2(value, env$1), meta, rest)]);
  } else if (k instanceof Apply2) {
    let f = k[0];
    let env$1 = k[1];
    _block = call(f, value, meta, env$1, rest);
  } else if (k instanceof Assign) {
    let label = k[0];
    let then$2 = k[1];
    let env$1 = k[2];
    let env$2 = new Env(prepend([label, value], env$1.scope), env$1.builtins);
    _block = new Ok([new E(then$2), env$2, rest]);
  } else if (k instanceof CallWith) {
    let arg = k[0];
    let env$1 = k[1];
    _block = call(value, arg, meta, env$1, rest);
  } else if (k instanceof Delimit) {
    let env$1 = k[2];
    _block = new Ok([new V(value), env$1, rest]);
  } else {
    let env$1 = k[1];
    _block = new Ok([new V(value), env$1, rest]);
  }
  let _pipe = _block;
  return map_error(_pipe, (reason) => {
    return [reason, meta, env, rest];
  });
}
function try$2(return$2) {
  if (return$2 instanceof Ok) {
    let c = return$2[0][0];
    let e = return$2[0][1];
    let k = return$2[0][2];
    return new Loop(c, e, k);
  } else {
    let info = return$2[0];
    return new Break(new Error2(info));
  }
}
function eval$(exp2, env, k) {
  let exp$1 = exp2[0];
  let meta = exp2[1];
  let value = (value2) => {
    return new Ok([new V(value2), env, k]);
  };
  let _block;
  if (exp$1 instanceof Variable) {
    let x = exp$1.label;
    let $ = key_find(env.scope, x);
    if ($ instanceof Ok) {
      let term = $[0];
      _block = new Ok([new V(term), env, k]);
    } else {
      _block = new Error2(new UndefinedVariable(x));
    }
  } else if (exp$1 instanceof Lambda) {
    let param = exp$1.label;
    let body = exp$1.body;
    _block = new Ok([new V(new Closure(param, body, env.scope)), env, k]);
  } else if (exp$1 instanceof Apply) {
    let f = exp$1.func;
    let arg = exp$1.argument;
    _block = new Ok([new E(f), env, new Stack(new Arg(arg, env), meta, k)]);
  } else if (exp$1 instanceof Let) {
    let var$ = exp$1.label;
    let value$1 = exp$1.definition;
    let then$2 = exp$1.body;
    _block = new Ok([new E(value$1), env, new Stack(new Assign(var$, then$2, env), meta, k)]);
  } else if (exp$1 instanceof Binary) {
    let data = exp$1.value;
    _block = value(new Binary3(data));
  } else if (exp$1 instanceof Integer) {
    let data = exp$1.value;
    _block = value(new Integer3(data));
  } else if (exp$1 instanceof String2) {
    let data = exp$1.value;
    _block = value(new String4(data));
  } else if (exp$1 instanceof Tail) {
    _block = value(new LinkedList(List$Empty$const));
  } else if (exp$1 instanceof Cons) {
    _block = value(new Partial(Switch$Cons$const, List$Empty$const));
  } else if (exp$1 instanceof Vacant) {
    _block = new Error2(Reason$Vacant$const);
  } else if (exp$1 instanceof Empty2) {
    _block = value(unit2());
  } else if (exp$1 instanceof Extend) {
    let label = exp$1.label;
    _block = value(new Partial(new Extend2(label), List$Empty$const));
  } else if (exp$1 instanceof Select) {
    let label = exp$1.label;
    _block = value(new Partial(new Select2(label), List$Empty$const));
  } else if (exp$1 instanceof Overwrite) {
    let label = exp$1.label;
    _block = value(new Partial(new Overwrite2(label), List$Empty$const));
  } else if (exp$1 instanceof Tag) {
    let label = exp$1.label;
    _block = value(new Partial(new Tag2(label), List$Empty$const));
  } else if (exp$1 instanceof Case) {
    let label = exp$1.label;
    _block = value(new Partial(new Match(label), List$Empty$const));
  } else if (exp$1 instanceof NoCases) {
    _block = value(new Partial(Switch$NoCases$const, List$Empty$const));
  } else if (exp$1 instanceof Perform) {
    let label = exp$1.label;
    _block = value(new Partial(new Perform2(label), List$Empty$const));
  } else if (exp$1 instanceof Handle) {
    let label = exp$1.label;
    _block = value(new Partial(new Handle2(label), List$Empty$const));
  } else if (exp$1 instanceof Builtin) {
    let identifier = exp$1.identifier;
    let $ = get(env.builtins, identifier);
    if ($ instanceof Ok) {
      _block = value(new Partial(new Builtin2(identifier), List$Empty$const));
    } else {
      _block = new Error2(new UndefinedBuiltin(identifier));
    }
  } else {
    let reference2 = exp$1.reference;
    _block = new Error2(new UndefinedReference(reference2));
  }
  let _pipe = _block;
  return map_error(_pipe, (reason) => {
    return [reason, meta, env, k];
  });
}
function step(c, env, k) {
  if (c instanceof E) {
    let k$1 = k;
    let exp2 = c[0];
    return try$2(eval$(exp2, env, k$1));
  } else if (k instanceof Stack) {
    let value = c[0];
    let k$1 = k[0];
    let meta = k[1];
    let rest = k[2];
    return try$2(apply(value, env, k$1, meta, rest));
  } else {
    let value = c[0];
    return new Break(new Ok(value));
  }
}

// build/dev/javascript/eyg_interpreter/eyg/interpreter/builtin.mjs
var FILEPATH8 = "src/eyg/interpreter/builtin.gleam";
var list_fold = /* @__PURE__ */ new Arity3(do_list_fold);
var list_pop = /* @__PURE__ */ new Arity1(do_list_pop);
var binary_fold = /* @__PURE__ */ new Arity3(do_binary_fold);
var binary_compare = /* @__PURE__ */ new Arity2(do_binary_compare);
var binary_concat = /* @__PURE__ */ new Arity2(do_binary_concat);
var binary_size = /* @__PURE__ */ new Arity1(do_binary_size);
var binary_from_integers = /* @__PURE__ */ new Arity1(do_binary_from_integers);
var string_from_binary = /* @__PURE__ */ new Arity1(do_string_from_binary);
var string_to_binary = /* @__PURE__ */ new Arity1(do_string_to_binary);
var string_length2 = /* @__PURE__ */ new Arity1(do_string_length);
var string_ends_with = /* @__PURE__ */ new Arity2(do_string_ends_with);
var string_starts_with = /* @__PURE__ */ new Arity2(do_string_starts_with);
var string_lowercase = /* @__PURE__ */ new Arity1(do_string_lowercase);
var string_uppercase = /* @__PURE__ */ new Arity1(do_string_uppercase);
var string_replace2 = /* @__PURE__ */ new Arity3(do_string_replace);
var string_split_once = /* @__PURE__ */ new Arity2(do_string_split_once);
var string_split = /* @__PURE__ */ new Arity2(do_string_split);
var string_append = /* @__PURE__ */ new Arity2(do_string_append);
var int_to_string = /* @__PURE__ */ new Arity1(do_int_to_string);
var int_parse = /* @__PURE__ */ new Arity1(do_int_parse);
var absolute = /* @__PURE__ */ new Arity1(do_absolute);
var divide = /* @__PURE__ */ new Arity2(do_divide);
var multiply = /* @__PURE__ */ new Arity2(do_multiply);
var subtract = /* @__PURE__ */ new Arity2(do_subtract);
var add2 = /* @__PURE__ */ new Arity2(do_add);
var int_compare = /* @__PURE__ */ new Arity2(do_int_compare);
var never = /* @__PURE__ */ new Arity1(do_never);
var fixed = /* @__PURE__ */ new Arity2(do_fixed);
var fix2 = /* @__PURE__ */ new Arity1(do_fix);
var equal = /* @__PURE__ */ new Arity2(do_equal);
function do_equal(left, right, _, env, k) {
  let _block;
  let $ = isEqual(left, right);
  if ($) {
    _block = true$();
  } else {
    _block = false$();
  }
  let value = _block;
  return new Ok([new V(value), env, k]);
}
function do_fix(builder, meta, env, k) {
  return call(builder, new Partial(new Builtin2("fixed"), prepend(builder, List$Empty$const)), meta, env, k);
}
function do_fixed(builder, arg, meta, env, k) {
  return call(builder, new Partial(new Builtin2("fixed"), prepend(builder, List$Empty$const)), meta, env, new Stack(new CallWith(arg, env), meta, k));
}
function do_never(arg, _, _1, _2) {
  return new Error2(new IncorrectTerm("Never", arg));
}
function do_int_compare(left, right, _, env, k) {
  return try$(as_integer(left), (left2) => {
    return try$(as_integer(right), (right2) => {
      let _block;
      let $ = compare(left2, right2);
      if ($ instanceof Lt) {
        _block = new Tagged("Lt", unit2());
      } else if ($ instanceof Eq) {
        _block = new Tagged("Eq", unit2());
      } else {
        _block = new Tagged("Gt", unit2());
      }
      let return$2 = _block;
      return new Ok([new V(return$2), env, k]);
    });
  });
}
function do_add(left_value, right_value, _, env, k) {
  return try$(as_integer(left_value), (left) => {
    return try$(as_integer(right_value), (right) => {
      let return$2 = left + right;
      let $ = isSafeInteger(return$2);
      if ($) {
        return new Ok([new V(new Integer3(return$2)), env, k]);
      } else {
        return new Error2(new Unrepresentable("int_add", prepend(left_value, prepend(right_value, List$Empty$const))));
      }
    });
  });
}
function do_subtract(left_value, right_value, _, env, k) {
  return try$(as_integer(left_value), (left) => {
    return try$(as_integer(right_value), (right) => {
      let return$2 = left - right;
      let $ = isSafeInteger(return$2);
      if ($) {
        return new Ok([new V(new Integer3(return$2)), env, k]);
      } else {
        return new Error2(new Unrepresentable("int_subtract", prepend(left_value, prepend(right_value, List$Empty$const))));
      }
    });
  });
}
function do_multiply(left_value, right_value, _, env, k) {
  return try$(as_integer(left_value), (left) => {
    return try$(as_integer(right_value), (right) => {
      let return$2 = left * right;
      let $ = isSafeInteger(return$2);
      if ($) {
        return new Ok([new V(new Integer3(return$2)), env, k]);
      } else {
        return new Error2(new Unrepresentable("int_multiply", prepend(left_value, prepend(right_value, List$Empty$const))));
      }
    });
  });
}
function do_divide(left, right, _, env, k) {
  return try$(as_integer(left), (left2) => {
    return try$(as_integer(right), (right2) => {
      let _block;
      if (right2 === 0) {
        _block = error(unit2());
      } else {
        _block = ok(new Integer3(divideInt(left2, right2)));
      }
      let value = _block;
      return new Ok([new V(value), env, k]);
    });
  });
}
function do_absolute(x, _, env, k) {
  return try$(as_integer(x), (x2) => {
    return new Ok([new V(new Integer3(absolute_value(x2))), env, k]);
  });
}
function do_int_parse(raw_value, _, env, k) {
  return try$(as_string(raw_value), (raw) => {
    let $ = parse_int(raw);
    if ($ instanceof Ok) {
      let i = $[0];
      let $1 = isSafeInteger(i);
      if ($1) {
        return new Ok([new V(ok(new Integer3(i))), env, k]);
      } else {
        return new Error2(new Unrepresentable("int_parse", prepend(raw_value, List$Empty$const)));
      }
    } else {
      return new Ok([new V(error(unit2())), env, k]);
    }
  });
}
function do_int_to_string(x, _, env, k) {
  return try$(as_integer(x), (x2) => {
    return new Ok([new V(new String4(to_string(x2))), env, k]);
  });
}
function do_string_append(left, right, _, env, k) {
  return try$(as_string(left), (left2) => {
    return try$(as_string(right), (right2) => {
      return new Ok([new V(new String4(append(left2, right2))), env, k]);
    });
  });
}
function do_string_split(s, pattern, _, env, k) {
  return try$(as_string(s), (s2) => {
    return try$(as_string(pattern), (pattern2) => {
      let _block;
      let $1 = split2(s2, pattern2);
      if ($1 instanceof Empty) {
        _block = ["", List$Empty$const];
      } else {
        let first2 = $1.head;
        let parts2 = $1.tail;
        _block = [first2, parts2];
      }
      let $ = _block;
      let first = $[0];
      let parts = $[1];
      let parts$1 = new LinkedList(map2(parts, (var0) => {
        return new String4(var0);
      }));
      let value = new Record2(from_list(prepend(["head", new String4(first)], prepend(["tail", parts$1], List$Empty$const))));
      return new Ok([new V(value), env, k]);
    });
  });
}
function do_string_split_once(s, pattern, _, env, k) {
  return try$(as_string(s), (s2) => {
    return try$(as_string(pattern), (pattern2) => {
      let _block;
      if (pattern2 === "") {
        _block = new Ok(["", s2]);
      } else {
        _block = split_once(s2, pattern2);
      }
      let split4 = _block;
      let _block$1;
      if (split4 instanceof Ok) {
        let pre = split4[0][0];
        let post = split4[0][1];
        let record2 = new Record2(from_list(prepend(["pre", new String4(pre)], prepend(["post", new String4(post)], List$Empty$const))));
        _block$1 = ok(record2);
      } else {
        _block$1 = error(unit2());
      }
      let value = _block$1;
      return new Ok([new V(value), env, k]);
    });
  });
}
function do_string_replace(in$, from2, to, _, env, k) {
  return try$(as_string(in$), (in$2) => {
    return try$(as_string(from2), (from3) => {
      return try$(as_string(to), (to2) => {
        let _block;
        if (from3 === "") {
          if (in$2 === "") {
            _block = to2;
          } else {
            _block = to2 + join(graphemes(in$2), to2) + to2;
          }
        } else {
          _block = replace(in$2, from3, to2);
        }
        let replaced = _block;
        return new Ok([new V(new String4(replaced)), env, k]);
      });
    });
  });
}
function do_string_uppercase(value, _, env, k) {
  return try$(as_string(value), (value2) => {
    return new Ok([new V(new String4(uppercase(value2))), env, k]);
  });
}
function do_string_lowercase(value, _, env, k) {
  return try$(as_string(value), (value2) => {
    return new Ok([new V(new String4(lowercase(value2))), env, k]);
  });
}
function bool3(value) {
  if (value) {
    return true$();
  } else {
    return false$();
  }
}
function do_string_starts_with(value, t, _, env, k) {
  return try$(as_string(value), (value2) => {
    return try$(as_string(t), (t2) => {
      return new Ok([new V(bool3(starts_with(value2, t2))), env, k]);
    });
  });
}
function do_string_ends_with(value, t, _, env, k) {
  return try$(as_string(value), (value2) => {
    return try$(as_string(t), (t2) => {
      return new Ok([new V(bool3(ends_with(value2, t2))), env, k]);
    });
  });
}
function do_string_length(value, _, env, k) {
  return try$(as_string(value), (value2) => {
    return new Ok([new V(new Integer3(string_length(value2))), env, k]);
  });
}
function do_string_to_binary(in$, _, env, k) {
  return try$(as_string(in$), (in$2) => {
    return new Ok([new V(new Binary3(bit_array_from_string(in$2))), env, k]);
  });
}
function do_string_from_binary(in$, _, env, k) {
  return try$(as_binary(in$), (in$2) => {
    let _block;
    let $ = bit_array_to_string(in$2);
    if ($ instanceof Ok) {
      let bytes = $[0];
      _block = ok(new String4(bytes));
    } else {
      _block = error(unit2());
    }
    let value = _block;
    return new Ok([new V(value), env, k]);
  });
}
function do_list_pop(term, _, env, k) {
  return try$(as_list(term), (elements) => {
    let _block;
    if (elements instanceof Empty) {
      _block = error(unit2());
    } else {
      let head = elements.head;
      let tail = elements.tail;
      _block = ok(new Record2(from_list(prepend(["head", head], prepend(["tail", new LinkedList(tail)], List$Empty$const)))));
    }
    let return$2 = _block;
    return new Ok([new V(return$2), env, k]);
  });
}
function do_list_fold(list3, state, func, meta, env, k) {
  return try$(as_list(list3), (elements) => {
    if (elements instanceof Empty) {
      return new Ok([new V(state), env, k]);
    } else {
      let element = elements.head;
      let rest = elements.tail;
      return call(func, element, meta, env, new Stack(new CallWith(state, env), meta, new Stack(new Apply2(new Partial(new Builtin2("list_fold"), prepend(new LinkedList(rest), List$Empty$const)), env), meta, new Stack(new CallWith(func, env), meta, k))));
    }
  });
}
function do_binary_from_integers(term, _, env, k) {
  return try$(as_list(term), (parts) => {
    let content = fold2(reverse(parts), toBitArray([]), (acc, el) => {
      let i;
      if (el instanceof Integer3) {
        i = el.value;
      } else {
        throw makeError("let_assert", FILEPATH8, "eyg/interpreter/builtin", 328, "do_binary_from_integers", "Pattern match failed, no pattern matched the value.", {
          value: el,
          start: 9377,
          end: 9405,
          pattern_start: 9388,
          pattern_end: 9400
        });
      }
      return toBitArray([i, acc]);
    });
    return new Ok([new V(new Binary3(content)), env, k]);
  });
}
function do_binary_size(term, _, env, k) {
  return try$(as_binary(term), (bytes) => {
    return new Ok([new V(new Integer3(bit_array_byte_size(bytes))), env, k]);
  });
}
function do_binary_concat(left, right, _, env, k) {
  return try$(as_binary(left), (left2) => {
    return try$(as_binary(right), (right2) => {
      return new Ok([
        new V(new Binary3(append2(left2, right2))),
        env,
        k
      ]);
    });
  });
}
function do_binary_compare(left, right, _, env, k) {
  return try$(as_binary(left), (left2) => {
    return try$(as_binary(right), (right2) => {
      let _block;
      let $ = compare3(left2, right2);
      if ($ instanceof Lt) {
        _block = new Tagged("Lt", unit2());
      } else if ($ instanceof Eq) {
        _block = new Tagged("Eq", unit2());
      } else {
        _block = new Tagged("Gt", unit2());
      }
      let return$2 = _block;
      return new Ok([new V(return$2), env, k]);
    });
  });
}
function do_binary_fold(bytes, state, func, meta, env, k) {
  return try$(as_binary(bytes), (bytes2) => {
    if (bytes2.bitSize === 0) {
      return new Ok([new V(state), env, k]);
    } else if (bytes2.bitSize >= 8 && bytes2.bitSize % 8 === 0) {
      let byte = bytes2.byteAt(0);
      let rest = bitArraySlice(bytes2, 8);
      return call(func, new Integer3(byte), meta, env, new Stack(new CallWith(state, env), meta, new Stack(new Apply2(new Partial(new Builtin2("binary_fold"), prepend(new Binary3(rest), List$Empty$const)), env), meta, new Stack(new CallWith(func, env), meta, k))));
    } else {
      throw makeError("panic", FILEPATH8, "eyg/interpreter/builtin", 388, "do_binary_fold", "assume full bytes", {});
    }
  });
}
function all() {
  let _pipe = make();
  let _pipe$1 = insert(_pipe, "equal", equal);
  let _pipe$2 = insert(_pipe$1, "fix", fix2);
  let _pipe$3 = insert(_pipe$2, "fixed", fixed);
  let _pipe$4 = insert(_pipe$3, "never", never);
  let _pipe$5 = insert(_pipe$4, "int_compare", int_compare);
  let _pipe$6 = insert(_pipe$5, "int_add", add2);
  let _pipe$7 = insert(_pipe$6, "int_subtract", subtract);
  let _pipe$8 = insert(_pipe$7, "int_multiply", multiply);
  let _pipe$9 = insert(_pipe$8, "int_divide", divide);
  let _pipe$10 = insert(_pipe$9, "int_absolute", absolute);
  let _pipe$11 = insert(_pipe$10, "int_parse", int_parse);
  let _pipe$12 = insert(_pipe$11, "int_to_string", int_to_string);
  let _pipe$13 = insert(_pipe$12, "string_append", string_append);
  let _pipe$14 = insert(_pipe$13, "string_split", string_split);
  let _pipe$15 = insert(_pipe$14, "string_split_once", string_split_once);
  let _pipe$16 = insert(_pipe$15, "string_replace", string_replace2);
  let _pipe$17 = insert(_pipe$16, "string_uppercase", string_uppercase);
  let _pipe$18 = insert(_pipe$17, "string_lowercase", string_lowercase);
  let _pipe$19 = insert(_pipe$18, "string_starts_with", string_starts_with);
  let _pipe$20 = insert(_pipe$19, "string_ends_with", string_ends_with);
  let _pipe$21 = insert(_pipe$20, "string_length", string_length2);
  let _pipe$22 = insert(_pipe$21, "string_to_binary", string_to_binary);
  let _pipe$23 = insert(_pipe$22, "string_from_binary", string_from_binary);
  let _pipe$24 = insert(_pipe$23, "binary_from_integers", binary_from_integers);
  let _pipe$25 = insert(_pipe$24, "binary_size", binary_size);
  let _pipe$26 = insert(_pipe$25, "binary_concat", binary_concat);
  let _pipe$27 = insert(_pipe$26, "binary_compare", binary_compare);
  let _pipe$28 = insert(_pipe$27, "binary_fold", binary_fold);
  let _pipe$29 = insert(_pipe$28, "list_pop", list_pop);
  return insert(_pipe$29, "list_fold", list_fold);
}
function default$(scope) {
  return new Env(scope, all());
}

// build/dev/javascript/eyg_interpreter/eyg/interpreter/expression.mjs
function loop(loop$next) {
  while (true) {
    let next = loop$next;
    if (next instanceof Loop) {
      let c = next[0];
      let e = next[1];
      let k = next[2];
      loop$next = step(c, e, k);
    } else {
      let result2 = next[0];
      return result2;
    }
  }
}
function resume(value, env, k) {
  return loop(step(new V(value), env, k));
}
function execute(exp2, scope) {
  return loop(step(new E(exp2), default$(scope), Stack$Empty$const));
}
function call2(f, args) {
  let env = default$(List$Empty$const);
  let k = fold_right(args, Stack$Empty$const, (k2, arg) => {
    let value = arg[0];
    let meta = arg[1];
    return new Stack(new CallWith(value, env), meta, k2);
  });
  return loop(step(new V(f), env, k));
}
// build/dev/javascript/gleam_json/gleam_json_ffi.mjs
function json_to_string(json) {
  return JSON.stringify(json);
}
function object(entries) {
  return Object.fromEntries(entries);
}
function identity2(x) {
  return x;
}
function decode4(string3) {
  try {
    const result2 = JSON.parse(string3);
    return Result$Ok(result2);
  } catch (err) {
    return Result$Error(getJsonDecodeError(err, string3));
  }
}
function getJsonDecodeError(stdErr, json) {
  if (isUnexpectedEndOfInput(stdErr))
    return DecodeError$UnexpectedEndOfInput();
  return toUnexpectedByteError(stdErr, json);
}
function isUnexpectedEndOfInput(err) {
  const unexpectedEndOfInputRegex = /((unexpected (end|eof))|(end of data)|(unterminated string)|(json( parse error|\.parse)\: expected '(\:|\}|\])'))/i;
  return unexpectedEndOfInputRegex.test(err.message);
}
function toUnexpectedByteError(err, json) {
  let converters = [
    v8UnexpectedByteError,
    oldV8UnexpectedByteError,
    jsCoreUnexpectedByteError,
    spidermonkeyUnexpectedByteError
  ];
  for (let converter of converters) {
    let result2 = converter(err, json);
    if (result2)
      return result2;
  }
  return DecodeError$UnexpectedByte("");
}
function v8UnexpectedByteError(err) {
  const regex = /unexpected token '(.)', ".+" is not valid JSON/i;
  const match = regex.exec(err.message);
  if (!match)
    return null;
  const byte = toHex(match[1]);
  return DecodeError$UnexpectedByte(byte);
}
function oldV8UnexpectedByteError(err) {
  const regex = /unexpected token (.) in JSON at position (\d+)/i;
  const match = regex.exec(err.message);
  if (!match)
    return null;
  const byte = toHex(match[1]);
  return DecodeError$UnexpectedByte(byte);
}
function spidermonkeyUnexpectedByteError(err, json) {
  const regex = /(unexpected character|expected .*) at line (\d+) column (\d+)/i;
  const match = regex.exec(err.message);
  if (!match)
    return null;
  const line = Number(match[2]);
  const column = Number(match[3]);
  const position = getPositionFromMultiline(line, column, json);
  const byte = toHex(json[position]);
  return DecodeError$UnexpectedByte(byte);
}
function jsCoreUnexpectedByteError(err) {
  const regex = /unexpected (identifier|token) "(.)"/i;
  const match = regex.exec(err.message);
  if (!match)
    return null;
  const byte = toHex(match[2]);
  return DecodeError$UnexpectedByte(byte);
}
function toHex(char2) {
  return "0x" + char2.charCodeAt(0).toString(16).toUpperCase();
}
function getPositionFromMultiline(line, column, string3) {
  if (line === 1)
    return column - 1;
  let currentLn = 1;
  let position = 0;
  string3.split("").find((char2, idx) => {
    if (char2 === `
`)
      currentLn += 1;
    if (currentLn === line) {
      position = idx + column;
      return true;
    }
    return false;
  });
  return position;
}

// build/dev/javascript/gleam_json/gleam/json.mjs
class UnexpectedEndOfInput extends CustomType {
}
var DecodeError$UnexpectedEndOfInput$const = new UnexpectedEndOfInput;
var DecodeError$UnexpectedEndOfInput = () => DecodeError$UnexpectedEndOfInput$const;
class UnexpectedByte extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
var DecodeError$UnexpectedByte = ($0) => new UnexpectedByte($0);
class UnableToDecode extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
function do_parse(json, decoder) {
  return try$(decode4(json), (dynamic_value) => {
    let _pipe = run(dynamic_value, decoder);
    return map_error(_pipe, (var0) => {
      return new UnableToDecode(var0);
    });
  });
}
function parse(json, decoder) {
  return do_parse(json, decoder);
}
function decode_to_dynamic(json) {
  let $ = bit_array_to_string(json);
  if ($ instanceof Ok) {
    let string$1 = $[0];
    return decode4(string$1);
  } else {
    return new Error2(new UnexpectedByte(""));
  }
}
function parse_bits(json, decoder) {
  return try$(decode_to_dynamic(json), (dynamic_value) => {
    let _pipe = run(dynamic_value, decoder);
    return map_error(_pipe, (var0) => {
      return new UnableToDecode(var0);
    });
  });
}
function to_string3(json) {
  return json_to_string(json);
}
function string3(input) {
  return identity2(input);
}
function int3(input) {
  return identity2(input);
}
function object2(entries) {
  return object(entries);
}

// build/dev/javascript/gleam_stdlib/gleam/uri.mjs
class Uri extends CustomType {
  constructor(scheme, userinfo, host, port, path, query, fragment) {
    super();
    this.scheme = scheme;
    this.userinfo = userinfo;
    this.host = host;
    this.port = port;
    this.path = path;
    this.query = query;
    this.fragment = fragment;
  }
}
function to_string4(uri) {
  let _block;
  let $ = uri.scheme;
  if ($ instanceof Some) {
    let scheme = $[0];
    _block = scheme + ":";
  } else {
    _block = "";
  }
  let out = _block;
  let _block$1;
  let $1 = uri.host;
  if ($1 instanceof Some) {
    let host = $1[0];
    let out$12 = out + "//";
    let _block$22;
    let $22 = uri.userinfo;
    if ($22 instanceof Some) {
      let userinfo = $22[0];
      _block$22 = out$12 + userinfo + "@";
    } else {
      _block$22 = out$12;
    }
    let out$22 = _block$22;
    let out$32 = out$22 + host;
    let _block$32;
    let $32 = uri.port;
    if ($32 instanceof Some) {
      let port = $32[0];
      _block$32 = out$32 + ":" + to_string(port);
    } else {
      _block$32 = out$32;
    }
    let out$4 = _block$32;
    let _block$4;
    let $4 = uri.path;
    if ($4 === "") {
      _block$4 = out$4;
    } else if ($4.charCodeAt(0) === 47) {
      _block$4 = out$4 + uri.path;
    } else {
      _block$4 = out$4 + "/" + uri.path;
    }
    let out$5 = _block$4;
    _block$1 = out$5;
  } else {
    _block$1 = out + uri.path;
  }
  let out$1 = _block$1;
  let _block$2;
  let $2 = uri.query;
  if ($2 instanceof Some) {
    let query = $2[0];
    _block$2 = out$1 + "?" + query;
  } else {
    _block$2 = out$1;
  }
  let out$2 = _block$2;
  let _block$3;
  let $3 = uri.fragment;
  if ($3 instanceof Some) {
    let fragment = $3[0];
    _block$3 = out$2 + "#" + fragment;
  } else {
    _block$3 = out$2;
  }
  let out$3 = _block$3;
  return out$3;
}
// build/dev/javascript/gleam_http/gleam/http.mjs
class Get extends CustomType {
}
var Method$Get$const = new Get;
class Post extends CustomType {
}
var Method$Post$const = new Post;
class Patch extends CustomType {
}
var Method$Patch$const = new Patch;
class Put extends CustomType {
}
var Method$Put$const = new Put;
class Delete extends CustomType {
}
var Method$Delete$const = new Delete;
class Head extends CustomType {
}
var Method$Head$const = new Head;
class Options extends CustomType {
}
var Method$Options$const = new Options;
class Trace2 extends CustomType {
}
var Method$Trace$const = new Trace2;
class Connect extends CustomType {
}
var Method$Connect$const = new Connect;
class Other extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Http extends CustomType {
}
var Scheme$Http$const = new Http;
class Https extends CustomType {
}
var Scheme$Https$const = new Https;
function method_to_string(method) {
  if (method instanceof Get) {
    return "GET";
  } else if (method instanceof Post) {
    return "POST";
  } else if (method instanceof Patch) {
    return "PATCH";
  } else if (method instanceof Put) {
    return "PUT";
  } else if (method instanceof Delete) {
    return "DELETE";
  } else if (method instanceof Head) {
    return "HEAD";
  } else if (method instanceof Options) {
    return "OPTIONS";
  } else if (method instanceof Trace2) {
    return "TRACE";
  } else if (method instanceof Connect) {
    return "CONNECT";
  } else {
    let method$1 = method[0];
    return method$1;
  }
}
function scheme_to_string(scheme) {
  if (scheme instanceof Http) {
    return "http";
  } else {
    return "https";
  }
}

// build/dev/javascript/gleam_http/gleam/http/cookie.mjs
class Lax extends CustomType {
}
var SameSitePolicy$Lax$const = new Lax;
class Strict extends CustomType {
}
var SameSitePolicy$Strict$const = new Strict;
class None2 extends CustomType {
}
var SameSitePolicy$None$const = new None2;

// build/dev/javascript/gleam_http/gleam/http/request.mjs
class Request extends CustomType {
  constructor(method, headers, body, scheme, host, port, path, query) {
    super();
    this.method = method;
    this.headers = headers;
    this.body = body;
    this.scheme = scheme;
    this.host = host;
    this.port = port;
    this.path = path;
    this.query = query;
  }
}
function to_uri(request) {
  return new Uri(new Some(scheme_to_string(request.scheme)), Option$None$const, new Some(request.host), request.port, request.path, request.query, Option$None$const);
}

// build/dev/javascript/gleam_http/gleam/http/response.mjs
class Response extends CustomType {
  constructor(status, headers, body) {
    super();
    this.status = status;
    this.headers = headers;
    this.body = body;
  }
}
var Response$Response = (status, headers, body) => new Response(status, headers, body);
function set_body(response, body) {
  return new Response(response.status, response.headers, body);
}
function map7(response, transform) {
  let _pipe = response.body;
  let _pipe$1 = transform(_pipe);
  return ((_capture) => {
    return set_body(response, _capture);
  })(_pipe$1);
}

// build/dev/javascript/midas/midas/effect.mjs
class Sha1 extends CustomType {
}
var HashAlgorithm$Sha1$const = new Sha1;
class Sha2562 extends CustomType {
}
var HashAlgorithm$Sha256$const = new Sha2562;
class Sha384 extends CustomType {
}
var HashAlgorithm$Sha384$const = new Sha384;
class Sha512 extends CustomType {
}
var HashAlgorithm$Sha512$const = new Sha512;
class CanEncrypt extends CustomType {
}
var KeyUsage$CanEncrypt$const = new CanEncrypt;
class CanDecrypt extends CustomType {
}
var KeyUsage$CanDecrypt$const = new CanDecrypt;
class CanSign extends CustomType {
}
var KeyUsage$CanSign$const = new CanSign;
class CanVerify extends CustomType {
}
var KeyUsage$CanVerify$const = new CanVerify;
class CanDeriveKey extends CustomType {
}
var KeyUsage$CanDeriveKey$const = new CanDeriveKey;
class CanDeriveBits extends CustomType {
}
var KeyUsage$CanDeriveBits$const = new CanDeriveBits;
class CanWrapKey extends CustomType {
}
var KeyUsage$CanWrapKey$const = new CanWrapKey;
class CanUnwrapKey extends CustomType {
}
var KeyUsage$CanUnwrapKey$const = new CanUnwrapKey;
class NetworkError extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class UnableToReadBody extends CustomType {
}
var FetchError$UnableToReadBody$const = new UnableToReadBody;
class NotImplemented extends CustomType {
}
var FetchError$NotImplemented$const = new NotImplemented;
// build/dev/javascript/ogre/ogre/origin.mjs
class Origin extends CustomType {
  constructor(scheme, host, port) {
    super();
    this.scheme = scheme;
    this.host = host;
    this.port = port;
  }
}
function https(host) {
  return new Origin(Scheme$Https$const, host, Option$None$const);
}
// build/dev/javascript/dag_json/dag_json.mjs
var string4 = string3;
var int4 = int3;
function code2() {
  return 297;
}
function encode4(node) {
  let _pipe = node;
  let _pipe$1 = to_string3(_pipe);
  return bit_array_from_string(_pipe$1);
}
function binary(bytes) {
  let encoded = base64_encode(bytes, false);
  return object2(prepend([
    "/",
    object2(prepend(["bytes", string3(encoded)], List$Empty$const))
  ], List$Empty$const));
}
function cid(cid2) {
  return object2(prepend(["/", string3(to_string2(cid2))], List$Empty$const));
}
function object3(entries) {
  let _pipe = sort(entries, (a, b) => {
    let key_a = a[0];
    let key_b = b[0];
    return compare3(bit_array_from_string(key_a), bit_array_from_string(key_b));
  });
  return object2(_pipe);
}
function decode_bytes() {
  return field("/", field("bytes", string2, (encoded) => {
    let $ = base64_decode2(encoded);
    if ($ instanceof Ok) {
      let bytes = $[0];
      return success(bytes);
    } else {
      return failure(toBitArray([]), "Invalid base64");
    }
  }), (bytes) => {
    return success(bytes);
  });
}
function decode_cid() {
  return field("/", string2, (cid2) => {
    let $ = from_string(cid2);
    if ($ instanceof Ok) {
      let cid$1 = $[0][0];
      return success(cid$1);
    } else {
      let reason = $[0];
      return failure(new Cid(0, new Multihash(Algorithm$Sha256$const, toBitArray([]))), reason);
    }
  });
}
// build/dev/javascript/untethered/untethered/ledger/schema.mjs
class ArchivedEntry extends CustomType {
  constructor(cursor, cid2, payload, entity, sequence, previous, type_) {
    super();
    this.cursor = cursor;
    this.cid = cid2;
    this.payload = payload;
    this.entity = entity;
    this.sequence = sequence;
    this.previous = previous;
    this.type_ = type_;
  }
}
class PullParameters extends CustomType {
  constructor(since, limit, entities) {
    super();
    this.since = since;
    this.limit = limit;
    this.entities = entities;
  }
}
class PullResponse extends CustomType {
  constructor(entries) {
    super();
    this.entries = entries;
  }
}
function archived_entry_decoder() {
  return field("cursor", int2, (cursor) => {
    return field("cid", decode_cid(), (cid2) => {
      return field("payload", string2, (payload) => {
        return field("entity", decode_cid(), (entity) => {
          return field("sequence", int2, (sequence) => {
            return optional_field("previous", Option$None$const, map3(decode_cid(), (var0) => {
              return new Some(var0);
            }), (previous) => {
              return field("type", string2, (type_) => {
                return success(new ArchivedEntry(cursor, cid2, payload, entity, sequence, previous, type_));
              });
            });
          });
        });
      });
    });
  });
}
function pull_parameters_to_query(parameters) {
  let since = parameters.since;
  let limit = parameters.limit;
  let entities = parameters.entities;
  let _pipe = prepend((() => {
    if (since === 0) {
      return List$Empty$const;
    } else {
      let n = since;
      return prepend(["since", to_string(n)], List$Empty$const);
    }
  })(), prepend((() => {
    if (limit === 1000) {
      return List$Empty$const;
    } else {
      let n = limit;
      return prepend(["limit", to_string(n)], List$Empty$const);
    }
  })(), prepend((() => {
    if (entities instanceof Empty) {
      return entities;
    } else {
      return prepend(["entities", join(entities, ",")], List$Empty$const);
    }
  })(), List$Empty$const)));
  return flatten(_pipe);
}
function pull_response_decoder() {
  return field("entries", list2(archived_entry_decoder()), (entries) => {
    return success(new PullResponse(entries));
  });
}
// build/dev/javascript/gbor/gbor.mjs
class CBNull extends CustomType {
}
var CBOR$CBNull$const = new CBNull;
class CBUndefined extends CustomType {
}
var CBOR$CBUndefined$const = new CBUndefined;
// build/dev/javascript/ieee_float/ieee_float.mjs
class NaN2 extends CustomType {
}
var IEEEFloat$NaN$const = new NaN2;

class Positive extends CustomType {
}
var Sign$Positive$const = new Positive;

class Negative extends CustomType {
}
var Sign$Negative$const = new Negative;

// build/dev/javascript/gbor/gbor/decode.mjs
class ReservedError extends CustomType {
}
var CborDecodeError$ReservedError$const = new ReservedError;
class UnassignedError extends CustomType {
}
var CborDecodeError$UnassignedError$const = new UnassignedError;

// build/dev/javascript/eyg_ir/eyg/ir/dag_json.mjs
function label_decoder(for$, meta) {
  return field("l", string2, (label) => {
    return success([for$(label), meta]);
  });
}
function decoder(meta) {
  return field("0", string2, (switch$) => {
    if (switch$ === "v") {
      return label_decoder((var0) => {
        return new Variable(var0);
      }, meta);
    } else if (switch$ === "f") {
      return field("l", string2, (label) => {
        return field("b", decoder(meta), (body) => {
          return success([new Lambda(label, body), meta]);
        });
      });
    } else if (switch$ === "a") {
      return field("f", decoder(meta), (function$) => {
        return field("a", decoder(meta), (argument) => {
          return success([new Apply(function$, argument), meta]);
        });
      });
    } else if (switch$ === "l") {
      return field("l", string2, (label) => {
        return field("v", decoder(meta), (value) => {
          return field("t", decoder(meta), (then$2) => {
            return success([new Let(label, value, then$2), meta]);
          });
        });
      });
    } else if (switch$ === "x") {
      return field("v", decode_bytes(), (bytes) => {
        return success([new Binary(bytes), meta]);
      });
    } else if (switch$ === "i") {
      return field("v", int2, (value) => {
        let $ = isSafeInteger(value);
        if ($) {
          return success([new Integer(value), meta]);
        } else {
          return failure([Expression$Vacant$const, meta], "an exactly representable integer");
        }
      });
    } else if (switch$ === "s") {
      return field("v", string2, (value) => {
        return success([new String2(value), meta]);
      });
    } else if (switch$ === "ta") {
      return success([Expression$Tail$const, meta]);
    } else if (switch$ === "c") {
      return success([Expression$Cons$const, meta]);
    } else if (switch$ === "z") {
      return success([Expression$Vacant$const, meta]);
    } else if (switch$ === "u") {
      return success([Expression$Empty$const, meta]);
    } else if (switch$ === "e") {
      return label_decoder((var0) => {
        return new Extend(var0);
      }, meta);
    } else if (switch$ === "g") {
      return label_decoder((var0) => {
        return new Select(var0);
      }, meta);
    } else if (switch$ === "o") {
      return label_decoder((var0) => {
        return new Overwrite(var0);
      }, meta);
    } else if (switch$ === "t") {
      return label_decoder((var0) => {
        return new Tag(var0);
      }, meta);
    } else if (switch$ === "m") {
      return label_decoder((var0) => {
        return new Case(var0);
      }, meta);
    } else if (switch$ === "n") {
      return success([Expression$NoCases$const, meta]);
    } else if (switch$ === "p") {
      return label_decoder((var0) => {
        return new Perform(var0);
      }, meta);
    } else if (switch$ === "h") {
      return label_decoder((var0) => {
        return new Handle(var0);
      }, meta);
    } else if (switch$ === "b") {
      return label_decoder((var0) => {
        return new Builtin(var0);
      }, meta);
    } else if (switch$ === "#") {
      return field("l", decode_cid(), (cid2) => {
        return success([new Reference(new Content(cid2)), meta]);
      });
    } else if (switch$ === "@") {
      return field("p", string2, (package$) => {
        return optional_field("r", Option$None$const, map3(int2, (var0) => {
          return new Some(var0);
        }), (version) => {
          return optional_field("l", Option$None$const, map3(decode_cid(), (var0) => {
            return new Some(var0);
          }), (module) => {
            if (version instanceof Some) {
              if (module instanceof Some) {
                let version$1 = version[0];
                let module$1 = module[0];
                return success([
                  new Reference(new Pinned(new Release(package$, version$1, module$1))),
                  meta
                ]);
              } else {
                let version$1 = version[0];
                return success([
                  new Reference(new Version(package$, version$1)),
                  meta
                ]);
              }
            } else if (module instanceof Some) {
              return failure([Expression$Vacant$const, meta], "a version when a module CID is present");
            } else {
              return success([new Reference(new Package(package$)), meta]);
            }
          });
        });
      });
    } else if (switch$ === ".") {
      return field("i", string2, (location) => {
        return success([new Reference(new Relative(location)), meta]);
      });
    } else {
      return failure([Expression$Vacant$const, meta], "valid node key");
    }
  });
}
function node(name, attributes) {
  return object3(prepend(["0", string4(name)], attributes));
}
function label(value) {
  return ["l", string4(value)];
}
function to_data_model(tree) {
  let exp2 = tree[0];
  if (exp2 instanceof Variable) {
    let x = exp2.label;
    return node("v", prepend(label(x), List$Empty$const));
  } else if (exp2 instanceof Lambda) {
    let x = exp2.label;
    let body = exp2.body;
    return node("f", prepend(label(x), prepend(["b", to_data_model(body)], List$Empty$const)));
  } else if (exp2 instanceof Apply) {
    let func = exp2.func;
    let arg = exp2.argument;
    return node("a", prepend(["f", to_data_model(func)], prepend(["a", to_data_model(arg)], List$Empty$const)));
  } else if (exp2 instanceof Let) {
    let x = exp2.label;
    let value = exp2.definition;
    let then$2 = exp2.body;
    let _pipe = prepend(label(x), prepend(["v", to_data_model(value)], prepend(["t", to_data_model(then$2)], List$Empty$const)));
    return ((_capture) => {
      return node("l", _capture);
    })(_pipe);
  } else if (exp2 instanceof Binary) {
    let b = exp2.value;
    return node("x", prepend(["v", binary(b)], List$Empty$const));
  } else if (exp2 instanceof Integer) {
    let i = exp2.value;
    return node("i", prepend(["v", int4(i)], List$Empty$const));
  } else if (exp2 instanceof String2) {
    let s = exp2.value;
    return node("s", prepend(["v", string4(s)], List$Empty$const));
  } else if (exp2 instanceof Tail) {
    return node("ta", List$Empty$const);
  } else if (exp2 instanceof Cons) {
    return node("c", List$Empty$const);
  } else if (exp2 instanceof Vacant) {
    return node("z", List$Empty$const);
  } else if (exp2 instanceof Empty2) {
    return node("u", List$Empty$const);
  } else if (exp2 instanceof Extend) {
    let x = exp2.label;
    return node("e", prepend(label(x), List$Empty$const));
  } else if (exp2 instanceof Select) {
    let x = exp2.label;
    return node("g", prepend(label(x), List$Empty$const));
  } else if (exp2 instanceof Overwrite) {
    let x = exp2.label;
    return node("o", prepend(label(x), List$Empty$const));
  } else if (exp2 instanceof Tag) {
    let x = exp2.label;
    return node("t", prepend(label(x), List$Empty$const));
  } else if (exp2 instanceof Case) {
    let x = exp2.label;
    return node("m", prepend(label(x), List$Empty$const));
  } else if (exp2 instanceof NoCases) {
    return node("n", List$Empty$const);
  } else if (exp2 instanceof Perform) {
    let x = exp2.label;
    return node("p", prepend(label(x), List$Empty$const));
  } else if (exp2 instanceof Handle) {
    let x = exp2.label;
    return node("h", prepend(label(x), List$Empty$const));
  } else if (exp2 instanceof Builtin) {
    let x = exp2.identifier;
    return node("b", prepend(label(x), List$Empty$const));
  } else {
    let reference2 = exp2.reference;
    if (reference2 instanceof Content) {
      let identifier = reference2.cid;
      return node("#", prepend(["l", cid(identifier)], List$Empty$const));
    } else if (reference2 instanceof Package) {
      let package$ = reference2.package;
      return node("@", prepend(["p", string4(package$)], List$Empty$const));
    } else if (reference2 instanceof Version) {
      let package$ = reference2.package;
      let version = reference2.version;
      return node("@", prepend(["p", string4(package$)], prepend(["r", int4(version)], List$Empty$const)));
    } else if (reference2 instanceof Pinned) {
      let package$ = reference2.release.package;
      let version = reference2.release.version;
      let module = reference2.release.module;
      return node("@", prepend(["p", string4(package$)], prepend(["r", int4(version)], prepend(["l", cid(module)], List$Empty$const))));
    } else {
      let location = reference2.location;
      return node(".", prepend(["i", string4(location)], List$Empty$const));
    }
  }
}
function to_block(data) {
  return encode4(to_data_model(data));
}

// build/dev/javascript/eyg_ir/eyg/ir/cid.mjs
function from_block(bytes, hash_sha256) {
  return then$(hash_sha256(bytes), (digest) => {
    let multihash = new Multihash(Algorithm$Sha256$const, digest);
    return return$(new Cid(code2(), multihash));
  });
}
function from_tree(source, hash_sha256) {
  let bytes = to_block(source);
  return from_block(bytes, hash_sha256);
}

// build/dev/javascript/ogre/ogre/operation.mjs
class Operation extends CustomType {
  constructor(method, path, query, headers, body) {
    super();
    this.method = method;
    this.path = path;
    this.query = query;
    this.headers = headers;
    this.body = body;
  }
}
function default$2(method, path) {
  return new Operation(method, path, Option$None$const, List$Empty$const, toBitArray([]));
}
function get2(path) {
  return default$2(Method$Get$const, path);
}
function set_query(operation, query) {
  let _block;
  let _pipe = map2(query, (pair) => {
    let key = pair[0];
    let value = pair[1];
    return percent_encode(key) + "=" + percent_encode(value);
  });
  let _pipe$1 = join(_pipe, "&");
  _block = new Some(_pipe$1);
  let query$1 = _block;
  return new Operation(operation.method, operation.path, query$1, operation.headers, operation.body);
}
function set_body2(req, body) {
  return new Operation(req.method, req.path, req.query, req.headers, body);
}
function to_request(operation, origin) {
  return new Request(operation.method, operation.headers, operation.body, origin.scheme, origin.host, origin.port, operation.path, operation.query);
}

// build/dev/javascript/untethered/untethered/ledger/client.mjs
class UnexpectedStatus extends CustomType {
  constructor(status) {
    super();
    this.status = status;
  }
}
class UnableToDecode2 extends CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
function describe_failure(failure2) {
  if (failure2 instanceof UnexpectedStatus) {
    let status = failure2.status;
    return "Unexpected status: " + to_string(status);
  } else if (failure2 instanceof UnableToDecode2) {
    let reason = failure2.reason;
    return "Decode error: " + inspect2(reason);
  } else {
    let reason = failure2.reason;
    return "Network error: " + reason;
  }
}
function pull_request(path, parameters) {
  let _pipe = get2(path);
  let _pipe$1 = set_query(_pipe, pull_parameters_to_query(parameters));
  return set_body2(_pipe$1, toBitArray([]));
}

// build/dev/javascript/untethered/untethered/substrate.mjs
class Entry extends CustomType {
  constructor(sequence, previous, signatory, key, content) {
    super();
    this.sequence = sequence;
    this.previous = previous;
    this.signatory = signatory;
    this.key = key;
    this.content = content;
  }
}
function delegated_decoder(content_decoder) {
  return field("sequence", int2, (sequence) => {
    return field("previous", optional(decode_cid()), (previous) => {
      return field("signatory", decode_cid(), (signatory) => {
        return field("key", string2, (key) => {
          return field("type", string2, (type_) => {
            return field("content", content_decoder(type_), (content) => {
              return success(new Entry(sequence, previous, signatory, key, content));
            });
          });
        });
      });
    });
  });
}

// build/dev/javascript/untethered/untethered/decoder_set.mjs
class DecoderSet extends CustomType {
  constructor(decoders, zero) {
    super();
    this.decoders = decoders;
    this.zero = zero;
  }
}
function to_decoder(set, type_) {
  let decoders = set.decoders;
  let zero = set.zero;
  let $ = key_find(decoders, type_);
  if ($ instanceof Ok) {
    let decoder2 = $[0];
    return decoder2;
  } else {
    return failure(zero, "unknown type");
  }
}
// build/dev/javascript/eyg_hub/eyg/hub/publisher.mjs
class Release2 extends CustomType {
  constructor(package$, version, module) {
    super();
    this.package = package$;
    this.version = version;
    this.module = module;
  }
}
function release_decoder() {
  return field("package", string2, (package$) => {
    return field("version", int2, (version) => {
      return field("module", decode_cid(), (module) => {
        return success(new Release2(package$, version, module));
      });
    });
  });
}
function event_decoder() {
  let set = new DecoderSet(prepend(["release", release_decoder()], List$Empty$const), new Release2("", 0, new Cid(code2(), new Multihash(Algorithm$Sha256$const, toBitArray([])))));
  return (_capture) => {
    return to_decoder(set, _capture);
  };
}
function decoder2() {
  return delegated_decoder(event_decoder());
}

// build/dev/javascript/eyg_hub/eyg/hub/schema.mjs
var pull_response_decoder2 = pull_response_decoder;

// build/dev/javascript/eyg_hub/eyg/hub/signatory.mjs
class Admin extends CustomType {
}
var Policy$Admin$const = new Admin;

// build/dev/javascript/eyg_hub/eyg/hub/client.mjs
function fetch_module_operation(cid2) {
  let _pipe = get2("/modules/" + to_string2(cid2));
  return set_body2(_pipe, toBitArray([]));
}
function fetch_module_request(cid2, origin) {
  let _pipe = fetch_module_operation(cid2);
  return to_request(_pipe, origin);
}
function fetch_module_response(response) {
  let status = response.status;
  let body = response.body;
  if (status === 200) {
    let $ = parse_bits(body, decoder(undefined));
    if ($ instanceof Ok) {
      let response$1 = $[0];
      return new Ok(new Some(response$1));
    } else {
      let reason = $[0];
      return new Error2(new UnableToDecode2(reason));
    }
  } else if (status === 204) {
    return new Ok(Option$None$const);
  } else {
    return new Error2(new UnexpectedStatus(status));
  }
}
function fetch_module(cid2, origin, fetch2, hash) {
  let request = fetch_module_request(cid2, origin);
  return then$(fetch2(request), (result2) => {
    if (result2 instanceof Ok) {
      let response = result2[0];
      let $ = fetch_module_response(response);
      if ($ instanceof Ok) {
        let $1 = $[0];
        if ($1 instanceof Some) {
          let source = $1[0];
          return then$(from_tree(source, (_capture) => {
            return hash(HashAlgorithm$Sha256$const, _capture);
          }), (actual) => {
            let $2 = isEqual(actual, cid2);
            if ($2) {
              return return$(new Ok(source));
            } else {
              return return$(new Error2("hub returned module with the wrong cid."));
            }
          });
        } else {
          return return$(new Error2("no module"));
        }
      } else {
        return return$(new Error2("bad module lookup"));
      }
    } else {
      let reason = result2[0];
      return return$(new Error2(inspect2(reason)));
    }
  });
}
function pull_packages_operation(parameters) {
  return pull_request("/packages/pull", parameters);
}
function pull_packages_request(parameters, origin) {
  let _pipe = pull_packages_operation(parameters);
  return to_request(_pipe, origin);
}
function pull_packages_response(response) {
  let status = response.status;
  let body = response.body;
  if (status === 200) {
    let $ = parse_bits(body, pull_response_decoder2());
    if ($ instanceof Ok) {
      return $;
    } else {
      let reason = $[0];
      return new Error2(new UnableToDecode2(reason));
    }
  } else {
    return new Error2(new UnexpectedStatus(status));
  }
}
function pull_packages(parameters, origin, fetch2) {
  let request = pull_packages_request(parameters, origin);
  return then$(fetch2(request), (result2) => {
    let _block;
    if (result2 instanceof Ok) {
      let response = result2[0];
      let $ = pull_packages_response(response);
      if ($ instanceof Ok) {
        let entries = $[0].entries;
        _block = new Ok(entries);
      } else {
        let reason = $[0];
        _block = new Error2(describe_failure(reason));
      }
    } else {
      let reason = result2[0];
      _block = new Error2(inspect2(reason));
    }
    let result$1 = _block;
    return return$(result$1);
  });
}

// build/dev/javascript/eyg_hub/eyg/hub/cache.mjs
var FILEPATH9 = "src/eyg/hub/cache.gleam";

class Module extends CustomType {
  constructor(value, type_) {
    super();
    this.value = value;
    this.type_ = type_;
  }
}
class NotRequested extends CustomType {
}
var FetchStatus$NotRequested$const = new NotRequested;
class Requested extends CustomType {
}
var FetchStatus$Requested$const = new Requested;
class Failed extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Invalid extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class DependsOn extends CustomType {
  constructor(dep, env, k, source) {
    super();
    this.dep = dep;
    this.env = env;
    this.k = k;
    this.source = source;
  }
}
class Content2 extends CustomType {
  constructor(cid2) {
    super();
    this.cid = cid2;
  }
}
class Pinned2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class ReadyToPull extends CustomType {
}
var CursorStatus$ReadyToPull$const = new ReadyToPull;
class Pulling extends CustomType {
}
var CursorStatus$Pulling$const = new Pulling;
class Pulled extends CustomType {
}
var CursorStatus$Pulled$const = new Pulled;
class PullFailed extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class FetchModule extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class PullPackages extends CustomType {
  constructor(offset) {
    super();
    this.offset = offset;
  }
}
class FetchModuleCompleted extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class PullPackagesCompleted extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Available extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Unknown extends CustomType {
}
var Resource$Unknown$const = new Unknown;
class Unavailable extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Cache extends CustomType {
  constructor(modules, fetching_modules, releases, packages, cursor, cursor_status) {
    super();
    this.modules = modules;
    this.fetching_modules = fetching_modules;
    this.releases = releases;
    this.packages = packages;
    this.cursor = cursor;
    this.cursor_status = cursor_status;
  }
}
class Entry2 extends CustomType {
  constructor(version, module, cursor, sequence, cid2) {
    super();
    this.version = version;
    this.module = module;
    this.cursor = cursor;
    this.sequence = sequence;
    this.cid = cid2;
  }
}
function empty() {
  return new Cache(make(), make(), make(), make(), 0, CursorStatus$Pulled$const);
}
function module(cache, cid2) {
  let modules = cache.modules;
  let fetching_modules = cache.fetching_modules;
  let $ = get(modules, cid2);
  let $1 = get(fetching_modules, cid2);
  if ($ instanceof Ok) {
    let module$1 = $[0];
    return new Available(module$1);
  } else if ($1 instanceof Ok) {
    let $2 = $1[0];
    if ($2 instanceof NotRequested) {
      return Resource$Unknown$const;
    } else if ($2 instanceof Requested) {
      return Resource$Unknown$const;
    } else if ($2 instanceof Failed) {
      return Resource$Unknown$const;
    } else if ($2 instanceof Invalid) {
      let reason = $2[0];
      return new Unavailable(reason);
    } else {
      return Resource$Unknown$const;
    }
  } else {
    return Resource$Unknown$const;
  }
}
function release(cache, release2) {
  let package$1 = release2.package;
  let version = release2.version;
  let module$1 = release2.module;
  let $ = version > 0;
  if ($) {
    let $1 = get(cache.releases, [package$1, version]);
    if ($1 instanceof Ok) {
      let cid2 = $1[0];
      if (isEqual(cid2, module$1)) {
        return new Available(module$1);
      } else {
        return new Unavailable(undefined);
      }
    } else {
      return Resource$Unknown$const;
    }
  } else {
    return new Unavailable(undefined);
  }
}
function unbound_release(cache, package$, version) {
  return get(cache.releases, [package$, version]);
}
function package$(cache, package$2) {
  return get(cache.packages, package$2);
}
function types(context) {
  let modules = context.modules;
  return map(modules, (_, module2) => {
    return module2.type_;
  });
}
function set_status(cache, cid2, status) {
  let fetching_modules = insert(cache.fetching_modules, cid2, status);
  return new Cache(cache.modules, fetching_modules, cache.releases, cache.packages, cache.cursor, cache.cursor_status);
}
function fetch2(loop$cache, loop$cid) {
  while (true) {
    let cache = loop$cache;
    let cid2 = loop$cid;
    let modules = cache.modules;
    let fetching_modules = cache.fetching_modules;
    let $ = get(modules, cid2);
    let $1 = get(fetching_modules, cid2);
    if ($1 instanceof Ok) {
      let $2 = $1[0];
      if ($2 instanceof NotRequested) {
        return cache;
      } else if ($2 instanceof Requested) {
        return cache;
      } else if ($2 instanceof Failed) {
        return set_status(cache, cid2, FetchStatus$NotRequested$const);
      } else if ($2 instanceof Invalid) {
        return cache;
      } else {
        let $3 = $2.dep;
        if ($3 instanceof Content2) {
          let dep = $3.cid;
          loop$cache = cache;
          loop$cid = dep;
        } else {
          return cache;
        }
      }
    } else if ($ instanceof Ok) {
      return cache;
    } else {
      return set_status(cache, cid2, FetchStatus$NotRequested$const);
    }
  }
}
function pull(cache) {
  let cursor_status = cache.cursor_status;
  let _block;
  if (cursor_status instanceof ReadyToPull) {
    _block = cursor_status;
  } else if (cursor_status instanceof Pulling) {
    _block = cursor_status;
  } else if (cursor_status instanceof Pulled) {
    _block = CursorStatus$ReadyToPull$const;
  } else {
    _block = CursorStatus$ReadyToPull$const;
  }
  let cursor_status$1 = _block;
  return new Cache(cache.modules, cache.fetching_modules, cache.releases, cache.packages, cache.cursor, cursor_status$1);
}
function flush(cache) {
  let fetching_modules = cache.fetching_modules;
  let cursor = cache.cursor;
  let cursor_status = cache.cursor_status;
  let $ = fold(fetching_modules, [make(), List$Empty$const], (acc, cid2, status) => {
    let updated = acc[0];
    let cids = acc[1];
    if (status instanceof NotRequested) {
      return [
        insert(updated, cid2, FetchStatus$Requested$const),
        prepend(new FetchModule(cid2), cids)
      ];
    } else {
      return [insert(updated, cid2, status), cids];
    }
  });
  let fetching_modules$1 = $[0];
  let effects = $[1];
  let _block;
  if (cursor_status instanceof ReadyToPull) {
    _block = [
      CursorStatus$Pulling$const,
      prepend(new PullPackages(cursor), effects)
    ];
  } else if (cursor_status instanceof Pulling) {
    _block = [CursorStatus$Pulling$const, effects];
  } else if (cursor_status instanceof Pulled) {
    _block = [CursorStatus$Pulled$const, effects];
  } else {
    let reason = cursor_status[0];
    _block = [new PullFailed(reason), effects];
  }
  let $1 = _block;
  let cursor_status$1 = $1[0];
  let effects$1 = $1[1];
  return [
    new Cache(cache.modules, fetching_modules$1, cache.releases, cache.packages, cache.cursor, cursor_status$1),
    effects$1
  ];
}
function compute(action, origin, fetch3, hash) {
  if (action instanceof FetchModule) {
    let cid2 = action[0];
    return then$(fetch_module(cid2, origin, fetch3, hash), (result2) => {
      return return$(new FetchModuleCompleted(cid2, result2));
    });
  } else {
    let offset = action.offset;
    return then$(pull_packages(new PullParameters(offset, 1000, List$Empty$const), origin, fetch3), (result2) => {
      return return$(new PullPackagesCompleted(result2));
    });
  }
}
function loop2(loop$return, loop$cache, loop$resume) {
  while (true) {
    let return$2 = loop$return;
    let cache = loop$cache;
    let resume2 = loop$resume;
    if (return$2 instanceof Error2) {
      let $ = return$2[0][0];
      if ($ instanceof UndefinedReference) {
        let $1 = $[0];
        if ($1 instanceof Content) {
          let env = return$2[0][2];
          let k = return$2[0][3];
          let cid2 = $1.cid;
          let $2 = get(cache.modules, cid2);
          if ($2 instanceof Ok) {
            let value = $2[0].value;
            loop$return = resume2(value, env, k);
            loop$cache = cache;
            loop$resume = resume2;
          } else {
            return [return$2, fetch2(cache, cid2)];
          }
        } else if ($1 instanceof Pinned) {
          let env = return$2[0][2];
          let k = return$2[0][3];
          let release$1 = $1.release;
          let package$1 = release$1.package;
          let version = release$1.version;
          let module$1 = release$1.module;
          let $2 = get(cache.releases, [package$1, version]);
          if ($2 instanceof Ok) {
            let cid2 = $2[0];
            if (isEqual(cid2, module$1)) {
              let $3 = get(cache.modules, cid2);
              if ($3 instanceof Ok) {
                let value = $3[0].value;
                loop$return = resume2(value, env, k);
                loop$cache = cache;
                loop$resume = resume2;
              } else {
                return [return$2, fetch2(cache, cid2)];
              }
            } else {
              return [return$2, cache];
            }
          } else if (version > 0) {
            return [return$2, pull(cache)];
          } else {
            return [return$2, cache];
          }
        } else {
          return [return$2, cache];
        }
      } else {
        return [return$2, cache];
      }
    } else {
      return [return$2, cache];
    }
  }
}
function handle_return(cache, cid2, source, return$2) {
  let $ = loop2(return$2, cache, resume);
  let return$1 = $[0];
  let cache$1 = $[1];
  if (return$1 instanceof Ok) {
    let value = return$1[0];
    let fetching_modules = delete$(cache$1.fetching_modules, cid2);
    let _block;
    let _pipe = pure();
    let _pipe$1 = check_with_references(_pipe, types(cache$1), source);
    _block = poly_type(_pipe$1);
    let type_ = _block;
    let new$5 = new Module(value, type_);
    let modules = insert(cache$1.modules, cid2, new$5);
    let cache$2 = new Cache(modules, fetching_modules, cache$1.releases, cache$1.packages, cache$1.cursor, cache$1.cursor_status);
    return [cache$2, prepend([cid2, new Ok(value)], List$Empty$const)];
  } else {
    let $1 = return$1[0][0];
    if ($1 instanceof UndefinedReference) {
      let $2 = $1[0];
      if ($2 instanceof Content) {
        let env = return$1[0][2];
        let k = return$1[0][3];
        let dep = $2.cid;
        let $3 = get(cache$1.fetching_modules, dep);
        if ($3 instanceof Ok) {
          let $4 = $3[0];
          if ($4 instanceof Invalid) {
            let reason = $4[0];
            let cache$2 = set_status(cache$1, cid2, new Invalid(reason));
            return [
              cache$2,
              prepend([cid2, new Error2(reason)], List$Empty$const)
            ];
          } else {
            let status = new DependsOn(new Content2(dep), env, k, source);
            let cache$2 = set_status(cache$1, cid2, status);
            return [cache$2, List$Empty$const];
          }
        } else {
          let status = new DependsOn(new Content2(dep), env, k, source);
          let cache$2 = set_status(cache$1, cid2, status);
          return [cache$2, List$Empty$const];
        }
      } else if ($2 instanceof Pinned) {
        let r = $1;
        let env = return$1[0][2];
        let k = return$1[0][3];
        let release$1 = $2.release;
        let package$1 = release$1.package;
        let version = release$1.version;
        let module$1 = release$1.module;
        let $3 = get(cache$1.releases, [package$1, version]);
        if ($3 instanceof Ok) {
          let dep = $3[0];
          if (!isEqual(dep, module$1)) {
            let cache$2 = set_status(cache$1, cid2, new Invalid(r));
            return [
              cache$2,
              prepend([cid2, new Error2(r)], List$Empty$const)
            ];
          } else {
            let dep$1 = $3[0];
            let $4 = get(cache$1.fetching_modules, dep$1);
            if ($4 instanceof Ok) {
              let $5 = $4[0];
              if ($5 instanceof Invalid) {
                let reason = $5[0];
                let cache$3 = set_status(cache$1, cid2, new Invalid(reason));
                return [
                  cache$3,
                  prepend([cid2, new Error2(reason)], List$Empty$const)
                ];
              } else {
                let status = new DependsOn(new Content2(dep$1), env, k, source);
                return [set_status(cache$1, cid2, status), List$Empty$const];
              }
            } else {
              let status = new DependsOn(new Content2(dep$1), env, k, source);
              return [set_status(cache$1, cid2, status), List$Empty$const];
            }
          }
        } else {
          let status = new DependsOn(new Pinned2(release$1), env, k, source);
          let cache$2 = set_status(cache$1, cid2, status);
          return [cache$2, List$Empty$const];
        }
      } else {
        let reason = $1;
        let cache$2 = set_status(cache$1, cid2, new Invalid(reason));
        return [
          cache$2,
          prepend([cid2, new Error2(reason)], List$Empty$const)
        ];
      }
    } else {
      let reason = $1;
      let cache$2 = set_status(cache$1, cid2, new Invalid(reason));
      return [cache$2, prepend([cid2, new Error2(reason)], List$Empty$const)];
    }
  }
}
function blocked_by(fetching_modules, resolved_cid) {
  return fold(fetching_modules, List$Empty$const, (resumable, module2, status) => {
    if (status instanceof DependsOn) {
      let $ = status.dep;
      if ($ instanceof Content2) {
        let dep = $.cid;
        if (isEqual(dep, resolved_cid)) {
          let env = status.env;
          let k = status.k;
          let source = status.source;
          return prepend([module2, env, k, source], resumable);
        } else {
          return resumable;
        }
      } else {
        return resumable;
      }
    } else {
      return resumable;
    }
  });
}
function cascade(loop$cache, loop$queue, loop$done) {
  while (true) {
    let cache = loop$cache;
    let queue = loop$queue;
    let done = loop$done;
    if (queue instanceof Empty) {
      return [cache, done];
    } else {
      let rest_queue = queue.tail;
      let resolved_cid = queue.head[0];
      let result2 = queue.head[1];
      let to_resume = blocked_by(cache.fetching_modules, resolved_cid);
      let $ = fold2(to_resume, [cache, rest_queue], (acc, item) => {
        let cache$12 = acc[0];
        let q2 = acc[1];
        let cid2 = item[0];
        let env = item[1];
        let k = item[2];
        let source = item[3];
        if (result2 instanceof Ok) {
          let value = result2[0];
          let return$2 = resume(value, env, k);
          let $1 = handle_return(cache$12, cid2, source, return$2);
          let cache$2 = $1[0];
          let new$5 = $1[1];
          return [cache$2, append3(new$5, q2)];
        } else {
          let reason = result2[0];
          let cache$2 = set_status(cache$12, cid2, new Invalid(reason));
          return [cache$2, prepend([cid2, new Error2(reason)], q2)];
        }
      });
      let cache$1 = $[0];
      let remaining = $[1];
      loop$cache = cache$1;
      loop$queue = remaining;
      loop$done = prepend([resolved_cid, result2], done);
    }
  }
}
function pulled(cache, cursor, release2) {
  let p = release2.package;
  let v = release2.version;
  let m = release2.module;
  let $ = fold(cache.fetching_modules, [List$Empty$const, List$Empty$const], (acc, module2, status) => {
    let resumable = acc[0];
    let invalid2 = acc[1];
    if (status instanceof DependsOn) {
      let $12 = status.dep;
      if ($12 instanceof Pinned2) {
        let dep = $12[0];
        if (dep.package === p && dep.version === v && isEqual(dep.module, m)) {
          let env = status.env;
          let k = status.k;
          let source = status.source;
          return [prepend([module2, env, k, source], resumable), invalid2];
        } else {
          let dep$1 = $12[0];
          if (dep$1.package === p && dep$1.version === v) {
            let reason = new UndefinedReference(new Pinned(dep$1));
            return [
              resumable,
              prepend([module2, new Error2(reason)], invalid2)
            ];
          } else {
            return [resumable, invalid2];
          }
        }
      } else {
        return [resumable, invalid2];
      }
    } else {
      return [resumable, invalid2];
    }
  });
  let unblocked = $[0];
  let invalid = $[1];
  let cache$1 = fold2(invalid, cache, (cache2, reason) => {
    let module$1;
    let reason$1;
    let $12 = reason[1];
    if ($12 instanceof Error2) {
      module$1 = reason[0];
      reason$1 = $12[0];
    } else {
      throw makeError("let_assert", FILEPATH9, "eyg/hub/cache", 521, "pulled", "Pattern match failed, no pattern matched the value.", {
        value: reason,
        start: 16855,
        end: 16899,
        pattern_start: 16866,
        pattern_end: 16890
      });
    }
    return set_status(cache2, module$1, new Invalid(reason$1));
  });
  let releases = insert(cache$1.releases, [p, v], m);
  let cache$2 = new Cache(cache$1.modules, cache$1.fetching_modules, releases, cache$1.packages, cursor, cache$1.cursor_status);
  let $1 = get(cache$2.modules, m);
  if ($1 instanceof Ok) {
    let value = $1[0].value;
    let $2 = fold2(unblocked, [cache$2, List$Empty$const], (acc, unblocked2) => {
      let cache$32 = acc[0];
      let queue = acc[1];
      let module$1 = unblocked2[0];
      let env = unblocked2[1];
      let k = unblocked2[2];
      let source = unblocked2[3];
      let return$2 = resume(value, env, k);
      let $3 = handle_return(cache$32, module$1, source, return$2);
      let cache$4 = $3[0];
      let new$5 = $3[1];
      return [cache$4, append3(new$5, queue)];
    });
    let cache$3 = $2[0];
    let resolved = $2[1];
    return cascade(cache$3, append3(resolved, invalid), List$Empty$const);
  } else {
    let _block;
    if (unblocked instanceof Empty) {
      _block = cache$2;
    } else {
      _block = fetch2(cache$2, m);
    }
    let cache$3 = _block;
    let cache$4 = fold2(unblocked, cache$3, (cache2, unblocked2) => {
      let module$1 = unblocked2[0];
      let env = unblocked2[1];
      let k = unblocked2[2];
      let source = unblocked2[3];
      return set_status(cache2, module$1, new DependsOn(new Content2(m), env, k, source));
    });
    return cascade(cache$4, invalid, List$Empty$const);
  }
}
function record_latest(cache, release2, entry) {
  let package$1 = release2.package;
  let version = release2.version;
  let module$1 = release2.module;
  let cursor = entry.cursor;
  let cid2 = entry.cid;
  let sequence = entry.sequence;
  let _block;
  let $ = get(cache.packages, package$1);
  if ($ instanceof Ok) {
    let seen = $[0].cursor;
    if (seen >= cursor) {
      _block = cache.packages;
    } else {
      _block = insert(cache.packages, package$1, new Entry2(version, module$1, cursor, sequence, cid2));
    }
  } else {
    _block = insert(cache.packages, package$1, new Entry2(version, module$1, cursor, sequence, cid2));
  }
  let packages = _block;
  return new Cache(cache.modules, cache.fetching_modules, cache.releases, packages, cache.cursor, cache.cursor_status);
}
function pull_packages_completed(cache, result2) {
  if (result2 instanceof Ok) {
    let entries = result2[0];
    let _block;
    if (entries instanceof Empty) {
      _block = CursorStatus$Pulled$const;
    } else {
      _block = CursorStatus$ReadyToPull$const;
    }
    let cursor_status = _block;
    let $ = fold2(entries, [cache, List$Empty$const], (acc, entry) => {
      let cache$12 = acc[0];
      let done2 = acc[1];
      let $1 = parse(entry.payload, decoder2());
      if ($1 instanceof Ok) {
        let payload = $1[0];
        let $2 = payload.content;
        let package$1 = $2.package;
        let version = $2.version;
        let module$1 = $2.module;
        let release$1 = new Release(package$1, version, module$1);
        let cache$2 = record_latest(cache$12, release$1, entry);
        let $3 = pulled(cache$2, entry.cursor, release$1);
        let cache$3 = $3[0];
        let new$5 = $3[1];
        return [cache$3, append3(done2, new$5)];
      } else {
        return [
          new Cache(cache$12.modules, cache$12.fetching_modules, cache$12.releases, cache$12.packages, entry.cursor, cache$12.cursor_status),
          done2
        ];
      }
    });
    let cache$1 = $[0];
    let done = $[1];
    return [
      new Cache(cache$1.modules, cache$1.fetching_modules, cache$1.releases, cache$1.packages, cache$1.cursor, cursor_status),
      done
    ];
  } else {
    let reason = result2[0];
    return [
      new Cache(cache.modules, cache.fetching_modules, cache.releases, cache.packages, cache.cursor, new PullFailed(reason)),
      List$Empty$const
    ];
  }
}
function with_module(cache, cid2, source) {
  let return$2 = execute(source, List$Empty$const);
  let $ = handle_return(cache, cid2, source, return$2);
  let cache$1 = $[0];
  let new$5 = $[1];
  return cascade(cache$1, new$5, List$Empty$const);
}
function fetch_module_completed(cache, cid2, result2) {
  if (result2 instanceof Ok) {
    let source = result2[0];
    return with_module(cache, cid2, source);
  } else {
    let reason = result2[0];
    let cache$1 = set_status(cache, cid2, new Failed(reason));
    return [cache$1, List$Empty$const];
  }
}
function update(cache, message, map_meta) {
  if (message instanceof FetchModuleCompleted) {
    let cid2 = message[0];
    let result2 = message[1];
    let result$1 = map4(result2, (_capture) => {
      return map_annotation(_capture, map_meta);
    });
    return fetch_module_completed(cache, cid2, result$1);
  } else {
    let result2 = message[0];
    return pull_packages_completed(cache, result2);
  }
}

// build/dev/javascript/eyg_interpreter/eyg/interpreter/block.mjs
function loop3(loop$c, loop$env, loop$k) {
  while (true) {
    let c = loop$c;
    let env = loop$env;
    let k = loop$k;
    if (c instanceof E && k instanceof Empty4 && c[0][0] instanceof Vacant) {
      return new Ok([Option$None$const, env.scope]);
    } else {
      let $ = step(c, env, k);
      if ($ instanceof Loop) {
        let c$1 = $[0];
        let env$1 = $[1];
        let k$1 = $[2];
        loop$c = c$1;
        loop$env = env$1;
        loop$k = k$1;
      } else {
        let $1 = $[0];
        if ($1 instanceof Ok) {
          let value = $1[0];
          return new Ok([new Some(value), env.scope]);
        } else {
          let reason = $1[0];
          return new Error2(reason);
        }
      }
    }
  }
}
function execute2(exp2, scope) {
  return loop3(new E(exp2), default$(scope), Stack$Empty$const);
}
function resume2(value, env, k) {
  return loop3(new V(value), env, k);
}
// build/dev/javascript/glam/glam/doc.mjs
class Line extends CustomType {
  constructor(size2) {
    super();
    this.size = size2;
  }
}

class Concat extends CustomType {
  constructor(docs) {
    super();
    this.docs = docs;
  }
}

class Text2 extends CustomType {
  constructor(text, length3) {
    super();
    this.text = text;
    this.length = length3;
  }
}

class Nest extends CustomType {
  constructor(doc, indentation) {
    super();
    this.doc = doc;
    this.indentation = indentation;
  }
}

class ForceBreak extends CustomType {
  constructor(doc) {
    super();
    this.doc = doc;
  }
}

class Break2 extends CustomType {
  constructor(unbroken, broken) {
    super();
    this.unbroken = unbroken;
    this.broken = broken;
  }
}

class FlexBreak extends CustomType {
  constructor(unbroken, broken) {
    super();
    this.unbroken = unbroken;
    this.broken = broken;
  }
}

class Group extends CustomType {
  constructor(doc) {
    super();
    this.doc = doc;
  }
}

class Broken extends CustomType {
}
var Mode$Broken$const = new Broken;

class ForceBroken extends CustomType {
}
var Mode$ForceBroken$const = new ForceBroken;

class Unbroken extends CustomType {
}
var Mode$Unbroken$const = new Unbroken;
var soft_break = /* @__PURE__ */ new Break2("", "");
var space = /* @__PURE__ */ new Break2(" ", "");
function append5(first, second) {
  if (first instanceof Concat) {
    let docs = first.docs;
    return new Concat(append3(docs, prepend(second, List$Empty$const)));
  } else {
    return new Concat(prepend(first, prepend(second, List$Empty$const)));
  }
}
function concat4(docs) {
  return new Concat(docs);
}
function break$(unbroken, broken) {
  return new Break2(unbroken, broken);
}
function join3(docs, separator) {
  return concat4(intersperse(docs, separator));
}
function from_string2(string5) {
  return new Text2(string5, string_length(string5));
}
function group2(doc) {
  return new Group(doc);
}
function nest(doc, indentation) {
  return new Nest(doc, indentation);
}
function fits(loop$docs, loop$max_width, loop$current_width) {
  while (true) {
    let docs = loop$docs;
    let max_width = loop$max_width;
    let current_width = loop$current_width;
    if (current_width > max_width) {
      return false;
    } else if (docs instanceof Empty) {
      return true;
    } else {
      let rest = docs.tail;
      let indent = docs.head[0];
      let mode = docs.head[1];
      let doc = docs.head[2];
      if (doc instanceof Line) {
        return true;
      } else if (doc instanceof Concat) {
        let docs$1 = doc.docs;
        let _pipe = map2(docs$1, (doc2) => {
          return [indent, mode, doc2];
        });
        let _pipe$1 = append3(_pipe, rest);
        loop$docs = _pipe$1;
        loop$max_width = max_width;
        loop$current_width = current_width;
      } else if (doc instanceof Text2) {
        let length3 = doc.length;
        loop$docs = rest;
        loop$max_width = max_width;
        loop$current_width = current_width + length3;
      } else if (doc instanceof Nest) {
        let doc$1 = doc.doc;
        let i = doc.indentation;
        let _pipe = prepend([indent + i, mode, doc$1], rest);
        loop$docs = _pipe;
        loop$max_width = max_width;
        loop$current_width = current_width;
      } else if (doc instanceof ForceBreak) {
        return false;
      } else if (doc instanceof Break2) {
        let unbroken = doc.unbroken;
        if (mode instanceof Broken) {
          return true;
        } else if (mode instanceof ForceBroken) {
          return true;
        } else {
          loop$docs = rest;
          loop$max_width = max_width;
          loop$current_width = current_width + string_length(unbroken);
        }
      } else if (doc instanceof FlexBreak) {
        let unbroken = doc.unbroken;
        if (mode instanceof Broken) {
          return true;
        } else if (mode instanceof ForceBroken) {
          return true;
        } else {
          loop$docs = rest;
          loop$max_width = max_width;
          loop$current_width = current_width + string_length(unbroken);
        }
      } else {
        let doc$1 = doc.doc;
        loop$docs = prepend([indent, mode, doc$1], rest);
        loop$max_width = max_width;
        loop$current_width = current_width;
      }
    }
  }
}
function indentation(size2) {
  return repeat(" ", size2);
}
function do_to_string(loop$acc, loop$max_width, loop$current_width, loop$docs) {
  while (true) {
    let acc = loop$acc;
    let max_width = loop$max_width;
    let current_width = loop$current_width;
    let docs = loop$docs;
    if (docs instanceof Empty) {
      return acc;
    } else {
      let rest = docs.tail;
      let indent = docs.head[0];
      let mode = docs.head[1];
      let doc = docs.head[2];
      if (doc instanceof Line) {
        let size2 = doc.size;
        let _pipe = acc + repeat(`
`, size2) + indentation(indent);
        loop$acc = _pipe;
        loop$max_width = max_width;
        loop$current_width = indent;
        loop$docs = rest;
      } else if (doc instanceof Concat) {
        let docs$1 = doc.docs;
        let _block;
        let _pipe = map2(docs$1, (doc2) => {
          return [indent, mode, doc2];
        });
        _block = append3(_pipe, rest);
        let docs$2 = _block;
        loop$acc = acc;
        loop$max_width = max_width;
        loop$current_width = current_width;
        loop$docs = docs$2;
      } else if (doc instanceof Text2) {
        let text = doc.text;
        let length3 = doc.length;
        loop$acc = acc + text;
        loop$max_width = max_width;
        loop$current_width = current_width + length3;
        loop$docs = rest;
      } else if (doc instanceof Nest) {
        let doc$1 = doc.doc;
        let i = doc.indentation;
        let docs$1 = prepend([indent + i, mode, doc$1], rest);
        loop$acc = acc;
        loop$max_width = max_width;
        loop$current_width = current_width;
        loop$docs = docs$1;
      } else if (doc instanceof ForceBreak) {
        let doc$1 = doc.doc;
        let docs$1 = prepend([indent, Mode$ForceBroken$const, doc$1], rest);
        loop$acc = acc;
        loop$max_width = max_width;
        loop$current_width = current_width;
        loop$docs = docs$1;
      } else if (doc instanceof Break2) {
        let unbroken = doc.unbroken;
        let broken = doc.broken;
        if (mode instanceof Broken) {
          let _pipe = acc + broken + `
` + indentation(indent);
          loop$acc = _pipe;
          loop$max_width = max_width;
          loop$current_width = indent;
          loop$docs = rest;
        } else if (mode instanceof ForceBroken) {
          let _pipe = acc + broken + `
` + indentation(indent);
          loop$acc = _pipe;
          loop$max_width = max_width;
          loop$current_width = indent;
          loop$docs = rest;
        } else {
          let new_width = current_width + string_length(unbroken);
          loop$acc = acc + unbroken;
          loop$max_width = max_width;
          loop$current_width = new_width;
          loop$docs = rest;
        }
      } else if (doc instanceof FlexBreak) {
        let unbroken = doc.unbroken;
        let broken = doc.broken;
        let new_unbroken_width = current_width + string_length(unbroken);
        let $ = fits(rest, max_width, new_unbroken_width);
        if ($) {
          let _pipe = acc + unbroken;
          loop$acc = _pipe;
          loop$max_width = max_width;
          loop$current_width = new_unbroken_width;
          loop$docs = rest;
        } else {
          let _pipe = acc + broken + `
` + indentation(indent);
          loop$acc = _pipe;
          loop$max_width = max_width;
          loop$current_width = indent;
          loop$docs = rest;
        }
      } else {
        let doc$1 = doc.doc;
        let fits$1 = fits(prepend([indent, Mode$Unbroken$const, doc$1], List$Empty$const), max_width, current_width);
        let _block;
        if (fits$1) {
          _block = Mode$Unbroken$const;
        } else {
          _block = Mode$Broken$const;
        }
        let new_mode = _block;
        let docs$1 = prepend([indent, new_mode, doc$1], rest);
        loop$acc = acc;
        loop$max_width = max_width;
        loop$current_width = current_width;
        loop$docs = docs$1;
      }
    }
  }
}
function to_string6(doc, limit) {
  return do_to_string("", limit, 0, prepend([0, Mode$Unbroken$const, doc], List$Empty$const));
}

// build/dev/javascript/eyg_interpreter/eyg/interpreter/simple_debug.mjs
var default_width = 80;
var max_depth = 8;
function wrap(open2, inner, close2) {
  let _pipe = concat4(prepend(from_string2(open2), prepend((() => {
    let _pipe2 = soft_break;
    let _pipe$1 = append5(_pipe2, inner);
    return nest(_pipe$1, 2);
  })(), prepend(soft_break, prepend(from_string2(close2), List$Empty$const)))));
  return group2(_pipe);
}
function separated(items, open2, close2) {
  let separator = break$(", ", ",");
  let body = join3(items, separator);
  let _block;
  let _pipe = soft_break;
  let _pipe$1 = append5(_pipe, body);
  _block = nest(_pipe$1, 2);
  let inner = _block;
  let _pipe$2 = concat4(prepend(from_string2(open2), prepend(inner, prepend(break$("", ","), prepend(from_string2(close2), List$Empty$const)))));
  return group2(_pipe$2);
}
function binary_doc(b) {
  let size2 = bit_array_byte_size(b);
  let encoded = base64_encode(b, true);
  return from_string2("Binary(" + to_string(size2) + " bytes): " + encoded);
}
function escape_string(s) {
  let _pipe = s;
  let _pipe$1 = replace(_pipe, "\\", "\\\\");
  let _pipe$2 = replace(_pipe$1, '"', "\\\"");
  let _pipe$3 = replace(_pipe$2, `
`, "\\n");
  let _pipe$4 = replace(_pipe$3, "\r", "\\r");
  return replace(_pipe$4, "\t", "\\t");
}
function partial_doc(func, args, depth) {
  let head = from_string2(inspect2(func));
  if (args instanceof Empty) {
    if (func instanceof Tag2) {
      let label2 = func[0];
      return from_string2(label2);
    } else {
      return wrap("Partial(", head, ")");
    }
  } else {
    let parts = prepend(head, map2(args, (arg) => {
      return to_doc(arg, depth + 1);
    }));
    let _block;
    let _pipe = parts;
    _block = join3(_pipe, concat4(prepend(from_string2(","), prepend(space, List$Empty$const))));
    let inner = _block;
    return wrap("Partial(", inner, ")");
  }
}
function list_doc(items, depth) {
  if (items instanceof Empty) {
    return from_string2("[]");
  } else {
    return separated(map2(items, (item) => {
      return to_doc(item, depth + 1);
    }), "[", "]");
  }
}
function record_doc(fields, depth) {
  let $ = is_empty(fields);
  if ($) {
    return from_string2("{}");
  } else {
    let _block;
    let _pipe = to_list(fields);
    let _pipe$1 = sort(_pipe, (a, b) => {
      return compare2(a[0], b[0]);
    });
    _block = map2(_pipe$1, (pair) => {
      let key = pair[0];
      let value = pair[1];
      let _pipe$2 = from_string2(key + ": ");
      return append5(_pipe$2, to_doc(value, depth + 1));
    });
    let entries = _block;
    return separated(entries, "{", "}");
  }
}
function to_doc(value, depth) {
  let $ = depth >= max_depth;
  if ($) {
    return from_string2("\u2026");
  } else {
    if (value instanceof Binary3) {
      let b = value.value;
      return binary_doc(b);
    } else if (value instanceof Integer3) {
      let i = value.value;
      return from_string2(to_string(i));
    } else if (value instanceof String4) {
      let s = value.value;
      return from_string2('"' + escape_string(s) + '"');
    } else if (value instanceof LinkedList) {
      let items = value.elements;
      return list_doc(items, depth);
    } else if (value instanceof Record2) {
      let fields = value.fields;
      return record_doc(fields, depth);
    } else if (value instanceof Tagged) {
      let label2 = value.label;
      let inner = value.value;
      let _pipe = from_string2(label2);
      return append5(_pipe, wrap("(", to_doc(inner, depth + 1), ")"));
    } else if (value instanceof Closure) {
      let param = value.param;
      return from_string2("fn(" + param + ") { ... }");
    } else {
      let func = value[0];
      let args = value[1];
      return partial_doc(func, args, depth);
    }
  }
}
function render(value, width) {
  let _pipe = value;
  let _pipe$1 = to_doc(_pipe, 0);
  return to_string6(_pipe$1, width);
}
function inspect3(value) {
  return render(value, default_width);
}
function describe(reason) {
  if (reason instanceof NotAFunction) {
    let term = reason[0];
    return "function expected got: " + inspect3(term);
  } else if (reason instanceof UndefinedVariable) {
    let var$ = reason[0];
    return "variable undefined: " + var$;
  } else if (reason instanceof UndefinedBuiltin) {
    let var$ = reason[0];
    return "builtin undefined: !" + var$;
  } else if (reason instanceof UndefinedReference) {
    let $ = reason[0];
    if ($ instanceof Content) {
      let id = $.cid;
      return "reference undefined: #" + to_string2(id);
    } else if ($ instanceof Package) {
      let package$2 = $.package;
      return "package undefined: @" + package$2;
    } else if ($ instanceof Version) {
      let package$2 = $.package;
      let version = $.version;
      return "version undefined: @" + package$2 + ":" + to_string(version);
    } else if ($ instanceof Pinned) {
      let package$2 = $.release.package;
      let version = $.release.version;
      return "release undefined: @" + package$2 + ":" + to_string(version);
    } else {
      let location = $.location;
      return "relative location undefined: " + location;
    }
  } else if (reason instanceof Vacant2) {
    return "tried to run a todo";
  } else if (reason instanceof NoMatch) {
    let term = reason.term;
    return "no cases matched for: " + inspect3(term);
  } else if (reason instanceof UnhandledEffect) {
    let $ = reason[0];
    if ($ === "Abort") {
      let reason$1 = reason[1];
      return "Aborted with reason: " + inspect3(reason$1);
    } else {
      let effect = $;
      let lift = reason[1];
      return "unhandled effect " + effect + "(" + inspect3(lift) + ")";
    }
  } else if (reason instanceof IncorrectTerm) {
    let expected = reason.expected;
    let got = reason.got;
    return "unexpected term, expected: " + expected + " got: " + inspect3(got);
  } else if (reason instanceof MissingField) {
    let field3 = reason[0];
    return "missing record field: " + field3;
  } else {
    return "integer out of range";
  }
}
function hint(reason) {
  if (reason instanceof NotAFunction) {
    return "only functions, builtins, and partially applied operations can be called";
  } else if (reason instanceof UndefinedVariable) {
    return "check the variable name or add a `let` binding before it is used";
  } else if (reason instanceof UndefinedBuiltin) {
    return "check the builtin name against the builtins reference";
  } else if (reason instanceof UndefinedReference) {
    let $ = reason[0];
    if ($ instanceof Content) {
      return "make sure the referenced module is available in the configured package hub";
    } else if ($ instanceof Package) {
      return "publish the release or pin the reference to an available module";
    } else if ($ instanceof Version) {
      return "publish the release or pin the reference to an available module";
    } else if ($ instanceof Pinned) {
      return "publish the release or pin the reference to an available module";
    } else {
      return "run the program from the directory that contains the relative module";
    }
  } else if (reason instanceof Vacant2) {
    return "replace the todo with an expression before running the program";
  } else if (reason instanceof NoMatch) {
    return "add a matching case branch or an otherwise branch for this tag";
  } else if (reason instanceof UnhandledEffect) {
    if (reason[0] === "Abort") {
      return "handle the abort effect or avoid performing it in this runtime";
    } else {
      return "handle this effect or run the program in a runtime that supports it";
    }
  } else if (reason instanceof IncorrectTerm) {
    return "check the value passed to this operation has the expected shape";
  } else if (reason instanceof MissingField) {
    return "check the record contains this field before selecting or overwriting it";
  } else {
    return "on the JavaScript target integers must be within the safe range (-(2^53-1) to 2^53-1)";
  }
}
// build/dev/javascript/gleam_javascript/gleam_javascript_ffi.mjs
class PromiseLayer {
  constructor(promise) {
    this.promise = promise;
  }
  static wrap(value) {
    return value instanceof Promise ? new PromiseLayer(value) : value;
  }
  static unwrap(value) {
    return value instanceof PromiseLayer ? value.promise : value;
  }
}
function resolve2(value) {
  return Promise.resolve(PromiseLayer.wrap(value));
}
function then_await(promise, fn) {
  return promise.then((value) => fn(PromiseLayer.unwrap(value)));
}
function map_promise(promise, fn) {
  return promise.then((value) => PromiseLayer.wrap(fn(PromiseLayer.unwrap(value))));
}
function wait(delay) {
  return new Promise((resolve3) => {
    globalThis.setTimeout(resolve3, delay);
  });
}

// build/dev/javascript/gleam_javascript/gleam/javascript/promise.mjs
function try_await(promise, callback) {
  let _pipe = promise;
  return then_await(_pipe, (result2) => {
    if (result2 instanceof Ok) {
      let a = result2[0];
      return callback(a);
    } else {
      let e = result2[0];
      return resolve2(new Error2(e));
    }
  });
}
// build/dev/javascript/eyg_parser/eyg/parser/location.mjs
function render_line(line_num, line, col, width) {
  let num_str = to_string(line_num);
  let gutter = " " + num_str + " | ";
  let blank_gutter = repeat(" ", string_length(gutter));
  return gutter + line + `
` + blank_gutter + repeat(" ", col) + repeat("^", width);
}
function do_render(loop$lines, loop$start, loop$end, loop$line_num, loop$offset, loop$acc) {
  while (true) {
    let lines = loop$lines;
    let start = loop$start;
    let end = loop$end;
    let line_num = loop$line_num;
    let offset = loop$offset;
    let acc = loop$acc;
    if (lines instanceof Empty) {
      return reverse(acc);
    } else {
      let line = lines.head;
      let rest = lines.tail;
      let line_len = byte_size(line);
      let line_end = offset + line_len;
      let line_starts_inside = start <= line_end && end >= offset;
      let $ = start > line_end;
      if ($) {
        loop$lines = rest;
        loop$start = start;
        loop$end = end;
        loop$line_num = line_num + 1;
        loop$offset = line_end + 1;
        loop$acc = acc;
      } else if (line_starts_inside) {
        let caret_start = max(0, start - offset);
        let caret_end = min(line_len, end - offset);
        let _block;
        let $1 = start === end;
        if ($1) {
          _block = 1;
        } else {
          _block = max(1, caret_end - caret_start);
        }
        let width = _block;
        let rendered = render_line(line_num, line, caret_start, width);
        let acc$1 = prepend(rendered, acc);
        loop$lines = rest;
        loop$start = start;
        loop$end = end;
        loop$line_num = line_num + 1;
        loop$offset = line_end + 1;
        loop$acc = acc$1;
      } else {
        return acc;
      }
    }
  }
}
function source_context(source, span) {
  let start = span[0];
  let end = span[1];
  let end$1 = max(end, start);
  let lines = split2(source, `
`);
  return do_render(lines, start, end$1, 1, 0, List$Empty$const);
}
// build/dev/javascript/kryptos/kryptos_ffi.mjs
import crypto from "crypto";
// build/dev/javascript/gleam_time/gleam/time/duration.mjs
class Nanosecond extends CustomType {
}
var Unit$Nanosecond$const = new Nanosecond;
class Microsecond extends CustomType {
}
var Unit$Microsecond$const = new Microsecond;
class Millisecond extends CustomType {
}
var Unit$Millisecond$const = new Millisecond;
class Second extends CustomType {
}
var Unit$Second$const = new Second;
class Minute extends CustomType {
}
var Unit$Minute$const = new Minute;
class Hour extends CustomType {
}
var Unit$Hour$const = new Hour;
class Day extends CustomType {
}
var Unit$Day$const = new Day;
class Week extends CustomType {
}
var Unit$Week$const = new Week;
class Month extends CustomType {
}
var Unit$Month$const = new Month;
class Year extends CustomType {
}
var Unit$Year$const = new Year;

// build/dev/javascript/gleam_time/gleam_time_ffi.mjs
function system_time() {
  const now = Date.now();
  const milliseconds = now % 1000;
  const nanoseconds = milliseconds * 1e6;
  const seconds = (now - milliseconds) / 1000;
  return [seconds, nanoseconds];
}

// build/dev/javascript/gleam_time/gleam/time/calendar.mjs
class Monday extends CustomType {
}
var DayOfWeek$Monday$const = new Monday;
class Tuesday extends CustomType {
}
var DayOfWeek$Tuesday$const = new Tuesday;
class Wednesday extends CustomType {
}
var DayOfWeek$Wednesday$const = new Wednesday;
class Thursday extends CustomType {
}
var DayOfWeek$Thursday$const = new Thursday;
class Friday extends CustomType {
}
var DayOfWeek$Friday$const = new Friday;
class Saturday extends CustomType {
}
var DayOfWeek$Saturday$const = new Saturday;
class Sunday extends CustomType {
}
var DayOfWeek$Sunday$const = new Sunday;
class January extends CustomType {
}
var Month$January$const = new January;
class February extends CustomType {
}
var Month$February$const = new February;
class March extends CustomType {
}
var Month$March$const = new March;
class April extends CustomType {
}
var Month$April$const = new April;
class May extends CustomType {
}
var Month$May$const = new May;
class June extends CustomType {
}
var Month$June$const = new June;
class July extends CustomType {
}
var Month$July$const = new July;
class August extends CustomType {
}
var Month$August$const = new August;
class September extends CustomType {
}
var Month$September$const = new September;
class October extends CustomType {
}
var Month$October$const = new October;
class November extends CustomType {
}
var Month$November$const = new November;
class December extends CustomType {
}
var Month$December$const = new December;

// build/dev/javascript/gleam_time/gleam/time/timestamp.mjs
class Timestamp extends CustomType {
  constructor(seconds2, nanoseconds2) {
    super();
    this.seconds = seconds2;
    this.nanoseconds = nanoseconds2;
  }
}
function normalise(timestamp) {
  let multiplier = 1e9;
  let nanoseconds2 = remainderInt(timestamp.nanoseconds, multiplier);
  let overflow = timestamp.nanoseconds - nanoseconds2;
  let seconds2 = timestamp.seconds + divideInt(overflow, multiplier);
  let $ = nanoseconds2 >= 0;
  if ($) {
    return new Timestamp(seconds2, nanoseconds2);
  } else {
    return new Timestamp(seconds2 - 1, multiplier + nanoseconds2);
  }
}
function system_time2() {
  let $ = system_time();
  let seconds2 = $[0];
  let nanoseconds2 = $[1];
  return normalise(new Timestamp(seconds2, nanoseconds2));
}
function to_unix_seconds_and_nanoseconds(timestamp) {
  return [timestamp.seconds, timestamp.nanoseconds];
}

// build/dev/javascript/kryptos/kryptos/ec.mjs
class P256 extends CustomType {
}
var Curve$P256$const = new P256;
class P384 extends CustomType {
}
var Curve$P384$const = new P384;
class P521 extends CustomType {
}
var Curve$P521$const = new P521;
class Secp256k1 extends CustomType {
}
var Curve$Secp256k1$const = new Secp256k1;

// build/dev/javascript/kryptos/kryptos/hash.mjs
class Blake2b extends CustomType {
}
var HashAlgorithm$Blake2b$const = new Blake2b;
class Blake2s extends CustomType {
}
var HashAlgorithm$Blake2s$const = new Blake2s;
class Md5 extends CustomType {
}
var HashAlgorithm$Md5$const = new Md5;
class Sha12 extends CustomType {
}
var HashAlgorithm$Sha1$const2 = new Sha12;
class Sha2563 extends CustomType {
}
var HashAlgorithm$Sha256$const2 = new Sha2563;
class Sha3842 extends CustomType {
}
var HashAlgorithm$Sha384$const2 = new Sha3842;
class Sha5122 extends CustomType {
}
var HashAlgorithm$Sha512$const2 = new Sha5122;
class Sha512x224 extends CustomType {
}
var HashAlgorithm$Sha512x224$const = new Sha512x224;
class Sha512x256 extends CustomType {
}
var HashAlgorithm$Sha512x256$const = new Sha512x256;
class Sha3x224 extends CustomType {
}
var HashAlgorithm$Sha3x224$const = new Sha3x224;
class Sha3x256 extends CustomType {
}
var HashAlgorithm$Sha3x256$const = new Sha3x256;
class Sha3x384 extends CustomType {
}
var HashAlgorithm$Sha3x384$const = new Sha3x384;
class Sha3x512 extends CustomType {
}
var HashAlgorithm$Sha3x512$const = new Sha3x512;
// build/dev/javascript/bigi/bigi.mjs
class LittleEndian extends CustomType {
}
var Endianness$LittleEndian$const = new LittleEndian;
class BigEndian extends CustomType {
}
var Endianness$BigEndian$const = new BigEndian;
class Signed extends CustomType {
}
var Signedness$Signed$const = new Signed;
class Unsigned extends CustomType {
}
var Signedness$Unsigned$const = new Unsigned;

// build/dev/javascript/kryptos/kryptos/rsa.mjs
class Pkcs8 extends CustomType {
}
var PrivateKeyFormat$Pkcs8$const = new Pkcs8;
class Pkcs1 extends CustomType {
}
var PrivateKeyFormat$Pkcs1$const = new Pkcs1;
class Spki extends CustomType {
}
var PublicKeyFormat$Spki$const = new Spki;
class RsaPublicKey extends CustomType {
}
var PublicKeyFormat$RsaPublicKey$const = new RsaPublicKey;
class SaltLengthHashLen extends CustomType {
}
var PssSaltLength$SaltLengthHashLen$const = new SaltLengthHashLen;
class SaltLengthMax extends CustomType {
}
var PssSaltLength$SaltLengthMax$const = new SaltLengthMax;
class Pkcs1v15 extends CustomType {
}
var SignPadding$Pkcs1v15$const = new Pkcs1v15;
class EncryptPkcs1v15 extends CustomType {
}
var EncryptPadding$EncryptPkcs1v15$const = new EncryptPkcs1v15;

// build/dev/javascript/kryptos/kryptos/xdh.mjs
class X25519 extends CustomType {
}
var Curve$X25519$const = new X25519;
class X448 extends CustomType {
}
var Curve$X448$const = new X448;

// build/dev/javascript/kryptos/kryptos_ffi.mjs
var KEYWRAP_DEFAULT_IV = Buffer.from([
  166,
  166,
  166,
  166,
  166,
  166,
  166,
  166
]);
function exportPublicKeyDer(key) {
  try {
    const exported = key.export({ format: "der", type: "spki" });
    return Result$Ok(BitArray$BitArray(exported));
  } catch {
    return Result$Error(undefined);
  }
}
var XDH_PRIVATE_DER_PREFIX = {
  x25519: Buffer.from("302e020100300506032b656e04220420", "hex"),
  x448: Buffer.from("3046020100300506032b656f043a0438", "hex")
};
var XDH_PUBLIC_DER_PREFIX = {
  x25519: Buffer.from("302a300506032b656e032100", "hex"),
  x448: Buffer.from("3042300506032b656f033900", "hex")
};
var EDDSA_PRIVATE_DER_PREFIX = {
  ed25519: Buffer.from("302e020100300506032b657004220420", "hex"),
  ed448: Buffer.from("3047020100300506032b6571043b0439", "hex")
};
var EDDSA_PUBLIC_DER_PREFIX = {
  ed25519: Buffer.from("302a300506032b6570032100", "hex"),
  ed448: Buffer.from("3043300506032b6571033a00", "hex")
};
function eddsaCurveName(curve) {
  if (Curve$isEd25519(curve))
    return "ed25519";
  if (Curve$isEd448(curve))
    return "ed448";
  throw new Error(`Unsupported EdDSA curve: ${curve.constructor.name}`);
}
function eddsaGenerateKeyPair(curve) {
  const curveName = eddsaCurveName(curve);
  const { privateKey, publicKey } = crypto.generateKeyPairSync(curveName);
  return [privateKey, publicKey];
}
function eddsaPrivateKeyFromBytes(curve, privateBytes) {
  try {
    const curveName = eddsaCurveName(curve);
    const expectedSize = key_size2(curve);
    if (privateBytes.byteSize !== expectedSize) {
      return Result$Error(undefined);
    }
    const prefix = EDDSA_PRIVATE_DER_PREFIX[curveName];
    const der = BitArray$BitArray$data(append2(BitArray$BitArray(prefix), privateBytes));
    const privateKey = crypto.createPrivateKey({
      key: der,
      format: "der",
      type: "pkcs8"
    });
    const publicKey = crypto.createPublicKey(privateKey);
    return Result$Ok([privateKey, publicKey]);
  } catch {
    return Result$Error(undefined);
  }
}
function eddsaPrivateKeyToBytes(privateKey) {
  const der = privateKey.export({ format: "der", type: "pkcs8" });
  const curveName = privateKey.asymmetricKeyType;
  const prefixLen = EDDSA_PRIVATE_DER_PREFIX[curveName].length;
  return BitArray$BitArray(der.subarray(prefixLen));
}
function eddsaPublicKeyToBytes(publicKey) {
  const der = publicKey.export({ format: "der", type: "spki" });
  const curveName = publicKey.asymmetricKeyType;
  const prefixLen = EDDSA_PUBLIC_DER_PREFIX[curveName].length;
  return BitArray$BitArray(der.subarray(prefixLen));
}
function eddsaSign(privateKey, message) {
  const signature = crypto.sign(null, BitArray$BitArray$data(message), privateKey);
  return BitArray$BitArray(signature);
}

// build/dev/javascript/kryptos/kryptos/eddsa.mjs
class Ed25519 extends CustomType {
}
var Curve$Ed25519$const = new Ed25519;
var Curve$isEd25519 = (value) => value instanceof Ed25519;

class Ed448 extends CustomType {
}
var Curve$Ed448$const = new Ed448;
var Curve$isEd448 = (value) => value instanceof Ed448;
function key_size2(curve) {
  if (curve instanceof Ed25519) {
    return 32;
  } else {
    return 57;
  }
}
// build/dev/javascript/simplifile/simplifile_js.mjs
import fs from "fs";
import path from "path";
import process2 from "process";
function readBits(filepath) {
  return gleamResult(() => {
    const contents = fs.readFileSync(path.normalize(filepath));
    return new BitArray(new Uint8Array(contents));
  });
}
function writeBits(filepath, contents) {
  return gleamResult(() => fs.writeFileSync(path.normalize(filepath), toUint8Array(contents)));
}
function appendBits(filepath, contents) {
  return gleamResult(() => fs.appendFileSync(path.normalize(filepath), toUint8Array(contents)));
}
function toUint8Array(contents) {
  if (contents.bitSize % 8 !== 0) {
    throw new Error2(new Einval);
  }
  let buffer = contents.rawBuffer;
  if (contents.bitOffset !== 0) {
    buffer = new Uint8Array(contents.byteSize);
    for (let i = 0;i < buffer.length; i++) {
      buffer[i] = contents.byteAt(i);
    }
  }
  return buffer;
}
function isDirectory(filepath) {
  try {
    return new Ok(fs.statSync(path.normalize(filepath)).isDirectory());
  } catch (e) {
    if (e.code === "ENOENT") {
      return new Ok(false);
    } else {
      return new Error2(cast_error(e.code));
    }
  }
}
function createDirAll(filepath) {
  return gleamResult(() => {
    fs.mkdirSync(path.normalize(filepath), { recursive: true });
  });
}
function delete_(fileOrDirPath) {
  return gleamResult(() => {
    const isDir = isDirectory(fileOrDirPath);
    if (isDir instanceof Ok && isDir[0] === true) {
      fs.rmSync(path.normalize(fileOrDirPath), { recursive: true });
    } else {
      fs.unlinkSync(path.normalize(fileOrDirPath));
    }
  });
}
function readDirectory(filepath) {
  return gleamResult(() => toList(fs.readdirSync(path.normalize(filepath))));
}
function setPermissionsOctal(filepath, octalNumber) {
  return gleamResult(() => fs.chmodSync(path.normalize(filepath), octalNumber));
}
function currentDirectory() {
  return gleamResult(() => process2.cwd());
}
function fileInfo(filepath) {
  return gleamResult(() => {
    const stat = fs.statSync(path.normalize(filepath));
    return new FileInfo(stat);
  });
}
class FileInfo {
  constructor(stat) {
    this.size = stat.size;
    this.mode = stat.mode;
    this.nlinks = stat.nlink;
    this.inode = stat.ino;
    this.user_id = stat.uid;
    this.group_id = stat.gid;
    this.dev = stat.dev;
    this.atime_seconds = Math.floor(stat.atimeMs / 1000);
    this.mtime_seconds = Math.floor(stat.mtimeMs / 1000);
    this.ctime_seconds = Math.floor(stat.ctimeMs / 1000);
  }
}
function gleamResult(op) {
  try {
    const val = op();
    return new Ok(val);
  } catch (e) {
    return new Error2(cast_error(e.code));
  }
}
function cast_error(error_code) {
  switch (error_code) {
    case "EACCES":
      return new Eacces;
    case "EAGAIN":
      return new Eagain;
    case "EBADF":
      return new Ebadf;
    case "EBADMSG":
      return new Ebadmsg;
    case "EBUSY":
      return new Ebusy;
    case "EDEADLK":
      return new Edeadlk;
    case "EDEADLOCK":
      return new Edeadlock;
    case "EDQUOT":
      return new Edquot;
    case "EEXIST":
      return new Eexist;
    case "EFAULT":
      return new Efault;
    case "EFBIG":
      return new Efbig;
    case "EFTYPE":
      return new Eftype;
    case "EINTR":
      return new Eintr;
    case "EINVAL":
      return new Einval;
    case "EIO":
      return new Eio;
    case "EISDIR":
      return new Eisdir;
    case "ELOOP":
      return new Eloop;
    case "EMFILE":
      return new Emfile;
    case "EMLINK":
      return new Emlink;
    case "EMULTIHOP":
      return new Emultihop;
    case "ENAMETOOLONG":
      return new Enametoolong;
    case "ENFILE":
      return new Enfile;
    case "ENOBUFS":
      return new Enobufs;
    case "ENODEV":
      return new Enodev;
    case "ENOLCK":
      return new Enolck;
    case "ENOLINK":
      return new Enolink;
    case "ENOENT":
      return new Enoent;
    case "ENOMEM":
      return new Enomem;
    case "ENOSPC":
      return new Enospc;
    case "ENOSR":
      return new Enosr;
    case "ENOSTR":
      return new Enostr;
    case "ENOSYS":
      return new Enosys;
    case "ENOBLK":
      return new Enotblk;
    case "ENOTDIR":
      return new Enotdir;
    case "ENOTSUP":
      return new Enotsup;
    case "ENXIO":
      return new Enxio;
    case "EOPNOTSUPP":
      return new Eopnotsupp;
    case "EOVERFLOW":
      return new Eoverflow;
    case "EPERM":
      return new Eperm;
    case "EPIPE":
      return new Epipe;
    case "ERANGE":
      return new Erange;
    case "EROFS":
      return new Erofs;
    case "ESPIPE":
      return new Espipe;
    case "ESRCH":
      return new Esrch;
    case "ESTALE":
      return new Estale;
    case "ETXTBSY":
      return new Etxtbsy;
    case "EXDEV":
      return new Exdev;
    case "NOTUTF8":
      return new NotUtf8;
    default:
      return new Unknown2(error_code);
  }
}

// build/dev/javascript/simplifile/simplifile.mjs
class Eacces extends CustomType {
}
var FileError$Eacces$const = new Eacces;
class Eagain extends CustomType {
}
var FileError$Eagain$const = new Eagain;
class Ebadf extends CustomType {
}
var FileError$Ebadf$const = new Ebadf;
class Ebadmsg extends CustomType {
}
var FileError$Ebadmsg$const = new Ebadmsg;
class Ebusy extends CustomType {
}
var FileError$Ebusy$const = new Ebusy;
class Edeadlk extends CustomType {
}
var FileError$Edeadlk$const = new Edeadlk;
class Edeadlock extends CustomType {
}
var FileError$Edeadlock$const = new Edeadlock;
class Edquot extends CustomType {
}
var FileError$Edquot$const = new Edquot;
class Eexist extends CustomType {
}
var FileError$Eexist$const = new Eexist;
class Efault extends CustomType {
}
var FileError$Efault$const = new Efault;
class Efbig extends CustomType {
}
var FileError$Efbig$const = new Efbig;
class Eftype extends CustomType {
}
var FileError$Eftype$const = new Eftype;
class Eintr extends CustomType {
}
var FileError$Eintr$const = new Eintr;
class Einval extends CustomType {
}
var FileError$Einval$const = new Einval;
class Eio extends CustomType {
}
var FileError$Eio$const = new Eio;
class Eisdir extends CustomType {
}
var FileError$Eisdir$const = new Eisdir;
class Eloop extends CustomType {
}
var FileError$Eloop$const = new Eloop;
class Emfile extends CustomType {
}
var FileError$Emfile$const = new Emfile;
class Emlink extends CustomType {
}
var FileError$Emlink$const = new Emlink;
class Emultihop extends CustomType {
}
var FileError$Emultihop$const = new Emultihop;
class Enametoolong extends CustomType {
}
var FileError$Enametoolong$const = new Enametoolong;
class Enfile extends CustomType {
}
var FileError$Enfile$const = new Enfile;
class Enobufs extends CustomType {
}
var FileError$Enobufs$const = new Enobufs;
class Enodev extends CustomType {
}
var FileError$Enodev$const = new Enodev;
class Enolck extends CustomType {
}
var FileError$Enolck$const = new Enolck;
class Enolink extends CustomType {
}
var FileError$Enolink$const = new Enolink;
class Enoent extends CustomType {
}
var FileError$Enoent$const = new Enoent;
class Enomem extends CustomType {
}
var FileError$Enomem$const = new Enomem;
class Enospc extends CustomType {
}
var FileError$Enospc$const = new Enospc;
class Enosr extends CustomType {
}
var FileError$Enosr$const = new Enosr;
class Enostr extends CustomType {
}
var FileError$Enostr$const = new Enostr;
class Enosys extends CustomType {
}
var FileError$Enosys$const = new Enosys;
class Enotblk extends CustomType {
}
var FileError$Enotblk$const = new Enotblk;
class Enotdir extends CustomType {
}
var FileError$Enotdir$const = new Enotdir;
class Enotsup extends CustomType {
}
var FileError$Enotsup$const = new Enotsup;
class Enxio extends CustomType {
}
var FileError$Enxio$const = new Enxio;
class Eopnotsupp extends CustomType {
}
var FileError$Eopnotsupp$const = new Eopnotsupp;
class Eoverflow extends CustomType {
}
var FileError$Eoverflow$const = new Eoverflow;
class Eperm extends CustomType {
}
var FileError$Eperm$const = new Eperm;
class Epipe extends CustomType {
}
var FileError$Epipe$const = new Epipe;
class Erange extends CustomType {
}
var FileError$Erange$const = new Erange;
class Erofs extends CustomType {
}
var FileError$Erofs$const = new Erofs;
class Espipe extends CustomType {
}
var FileError$Espipe$const = new Espipe;
class Esrch extends CustomType {
}
var FileError$Esrch$const = new Esrch;
class Estale extends CustomType {
}
var FileError$Estale$const = new Estale;
class Etxtbsy extends CustomType {
}
var FileError$Etxtbsy$const = new Etxtbsy;
class Exdev extends CustomType {
}
var FileError$Exdev$const = new Exdev;
class NotUtf8 extends CustomType {
}
var FileError$NotUtf8$const = new NotUtf8;
class Unknown2 extends CustomType {
  constructor(inner) {
    super();
    this.inner = inner;
  }
}
class File extends CustomType {
}
var FileType$File$const = new File;
class Directory extends CustomType {
}
var FileType$Directory$const = new Directory;
class Symlink extends CustomType {
}
var FileType$Symlink$const = new Symlink;
class Other2 extends CustomType {
}
var FileType$Other$const = new Other2;
class Read extends CustomType {
}
var Permission$Read$const = new Read;
class Write extends CustomType {
}
var Permission$Write$const = new Write;
class Execute extends CustomType {
}
var Permission$Execute$const = new Execute;
function describe_error(error2) {
  if (error2 instanceof Eacces) {
    return "Permission denied";
  } else if (error2 instanceof Eagain) {
    return "Resource temporarily unavailable";
  } else if (error2 instanceof Ebadf) {
    return "Bad file descriptor";
  } else if (error2 instanceof Ebadmsg) {
    return "Bad message";
  } else if (error2 instanceof Ebusy) {
    return "Resource busy";
  } else if (error2 instanceof Edeadlk) {
    return "Resource deadlock avoided";
  } else if (error2 instanceof Edeadlock) {
    return "Resource deadlock avoided";
  } else if (error2 instanceof Edquot) {
    return "Disc quota exceeded";
  } else if (error2 instanceof Eexist) {
    return "File exists";
  } else if (error2 instanceof Efault) {
    return "Bad address";
  } else if (error2 instanceof Efbig) {
    return "File too large";
  } else if (error2 instanceof Eftype) {
    return "Inappropriate file type or format";
  } else if (error2 instanceof Eintr) {
    return "Interrupted system call";
  } else if (error2 instanceof Einval) {
    return "Invalid argument";
  } else if (error2 instanceof Eio) {
    return "Input/output error";
  } else if (error2 instanceof Eisdir) {
    return "Is a directory";
  } else if (error2 instanceof Eloop) {
    return "Too many levels of symbolic links";
  } else if (error2 instanceof Emfile) {
    return "Too many open files";
  } else if (error2 instanceof Emlink) {
    return "Too many links";
  } else if (error2 instanceof Emultihop) {
    return "Multihop attempted";
  } else if (error2 instanceof Enametoolong) {
    return "File name too long";
  } else if (error2 instanceof Enfile) {
    return "Too many open files in system";
  } else if (error2 instanceof Enobufs) {
    return "No buffer space available";
  } else if (error2 instanceof Enodev) {
    return "Operation not supported by device";
  } else if (error2 instanceof Enolck) {
    return "No locks available";
  } else if (error2 instanceof Enolink) {
    return "Link has been severed";
  } else if (error2 instanceof Enoent) {
    return "No such file or directory";
  } else if (error2 instanceof Enomem) {
    return "Cannot allocate memory";
  } else if (error2 instanceof Enospc) {
    return "No space left on device";
  } else if (error2 instanceof Enosr) {
    return "No STREAM resources";
  } else if (error2 instanceof Enostr) {
    return "Not a STREAM";
  } else if (error2 instanceof Enosys) {
    return "Function not implemented";
  } else if (error2 instanceof Enotblk) {
    return "Block device required";
  } else if (error2 instanceof Enotdir) {
    return "Not a directory";
  } else if (error2 instanceof Enotsup) {
    return "Operation not supported";
  } else if (error2 instanceof Enxio) {
    return "Device not configured";
  } else if (error2 instanceof Eopnotsupp) {
    return "Operation not supported on socket";
  } else if (error2 instanceof Eoverflow) {
    return "Value too large to be stored in data type";
  } else if (error2 instanceof Eperm) {
    return "Operation not permitted";
  } else if (error2 instanceof Epipe) {
    return "Broken pipe";
  } else if (error2 instanceof Erange) {
    return "Result too large";
  } else if (error2 instanceof Erofs) {
    return "Read-only file system";
  } else if (error2 instanceof Espipe) {
    return "Illegal seek";
  } else if (error2 instanceof Esrch) {
    return "No such process";
  } else if (error2 instanceof Estale) {
    return "Stale NFS file handle";
  } else if (error2 instanceof Etxtbsy) {
    return "Text file busy";
  } else if (error2 instanceof Exdev) {
    return "Cross-device link";
  } else if (error2 instanceof NotUtf8) {
    return "File not UTF-8 encoded";
  } else {
    let inner = error2.inner;
    return "Unknown error: " + inner;
  }
}
function file_info_type(file_info) {
  let $ = bitwise_and(file_info.mode, 61440);
  if ($ === 32768) {
    return FileType$File$const;
  } else if ($ === 16384) {
    return FileType$Directory$const;
  } else if ($ === 40960) {
    return FileType$Symlink$const;
  } else {
    return FileType$Other$const;
  }
}
function read(filepath) {
  let $ = readBits(filepath);
  if ($ instanceof Ok) {
    let bits2 = $[0];
    let $1 = bit_array_to_string(bits2);
    if ($1 instanceof Ok) {
      return $1;
    } else {
      return new Error2(FileError$NotUtf8$const);
    }
  } else {
    return $;
  }
}
function write(filepath, contents) {
  let _pipe = contents;
  let _pipe$1 = bit_array_from_string(_pipe);
  return writeBits(filepath, _pipe$1);
}
function create_directory_all(dirpath) {
  return createDirAll(dirpath + "/");
}
// build/dev/javascript/touch_grass/touch_grass/cryptography/create_key.mjs
class Eddsa extends CustomType {
}
var Algorithm$Eddsa$const = new Eddsa;
class EddsaKey extends CustomType {
  constructor(public_key, private_key) {
    super();
    this.public_key = public_key;
    this.private_key = private_key;
  }
}
var label2 = "CreateKey";
function lift() {
  return union2(prepend(["Eddsa", unit], List$Empty$const));
}
function eddsa_key() {
  return record(prepend(["kty", Type$String$const], prepend(["crv", Type$String$const], prepend(["x", Type$Binary$const], prepend(["d", Type$Binary$const], List$Empty$const)))));
}
function key() {
  return union2(prepend(["Eddsa", eddsa_key()], List$Empty$const));
}
function lower() {
  return result(key(), Type$String$const);
}
function decode6(lift2) {
  return as_varient(lift2, prepend(["Eddsa", (_) => {
    return new Ok(Algorithm$Eddsa$const);
  }], List$Empty$const));
}
function encode_key(key2) {
  let public_key = key2.public_key;
  let private_key = key2.private_key;
  return new Tagged("Eddsa", new Record2(from_list(prepend(["kty", new String4("OKP")], prepend(["crv", new String4("Ed25519")], prepend(["x", new Binary3(public_key)], prepend(["d", new Binary3(private_key)], List$Empty$const)))))));
}
function encode6(result2) {
  if (result2 instanceof Ok) {
    let key$1 = result2[0];
    return ok(encode_key(key$1));
  } else {
    let message = result2[0];
    return error(new String4(message));
  }
}

// build/dev/javascript/touch_grass/touch_grass/cryptography/hash.mjs
class Sha2564 extends CustomType {
}
var Algorithm$Sha256$const2 = new Sha2564;
class Input extends CustomType {
  constructor(algorithm, bytes) {
    super();
    this.algorithm = algorithm;
    this.bytes = bytes;
  }
}
var label3 = "Hash";
function lift2() {
  return record(prepend([
    "algorithm",
    union2(prepend(["SHA256", unit], List$Empty$const))
  ], prepend(["bytes", Type$Binary$const], List$Empty$const)));
}
function lower2() {
  return Type$Binary$const;
}
function decode_algorithm(value) {
  return as_varient(value, prepend([
    "SHA256",
    (_capture) => {
      return as_unit(_capture, Algorithm$Sha256$const2);
    }
  ], List$Empty$const));
}
function decode7(lift3) {
  return try$(field2("algorithm", decode_algorithm, lift3), (algorithm) => {
    return try$(field2("bytes", as_binary, lift3), (bytes) => {
      return new Ok(new Input(algorithm, bytes));
    });
  });
}
function encode7(digest) {
  return new Binary3(digest);
}

// build/dev/javascript/touch_grass/touch_grass/cryptography/sign.mjs
class EddsaSign extends CustomType {
  constructor(private_key, data) {
    super();
    this.private_key = private_key;
    this.data = data;
  }
}
var label4 = "Sign";
function lift3() {
  return record(prepend(["key", key()], prepend(["data", Type$Binary$const], List$Empty$const)));
}
function lower3() {
  return result(Type$Binary$const, Type$String$const);
}
function decode8(lift4) {
  return try$(field2("key", (var0) => {
    return new Ok(var0);
  }, lift4), (key2) => {
    return try$(field2("data", as_binary, lift4), (data) => {
      return as_varient(key2, prepend([
        "Eddsa",
        (keydata) => {
          return try$(field2("d", as_binary, keydata), (d) => {
            return new Ok(new EddsaSign(d, data));
          });
        }
      ], List$Empty$const));
    });
  });
}
function encode8(result2) {
  if (result2 instanceof Ok) {
    let signature = result2[0];
    return ok(new Binary3(signature));
  } else {
    let message = result2[0];
    return error(new String4(message));
  }
}
// build/dev/javascript/julienne/julienne.mjs
var FILEPATH10 = "src/julienne.gleam";

class Boolean2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Null extends CustomType {
}
var Term$Null$const = new Null;
class String5 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Integer4 extends CustomType {
  constructor(integer) {
    super();
    this.integer = integer;
  }
}
class Number2 extends CustomType {
  constructor(sign, integer, decimal, exponent) {
    super();
    this.sign = sign;
    this.integer = integer;
    this.decimal = decimal;
    this.exponent = exponent;
  }
}
class Array2 extends CustomType {
}
var Term$Array$const = new Array2;
class Object2 extends CustomType {
}
var Term$Object$const = new Object2;
class Field extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Positive2 extends CustomType {
}
var Sign$Positive$const2 = new Positive2;
class Negative2 extends CustomType {
}
var Sign$Negative$const2 = new Negative2;
class ArrayItem extends CustomType {
}
var Stack$ArrayItem$const = new ArrayItem;

class ObjectField extends CustomType {
}
var Stack$ObjectField$const = new ObjectField;

class UnexpectedEnd extends CustomType {
}
var Reason$UnexpectedEnd$const = new UnexpectedEnd;
class UnexpectedToken extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class MissingDigits extends CustomType {
}
var Reason$MissingDigits$const = new MissingDigits;
class InvalidString extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
function hex(byte) {
  let b = byte;
  if (b >= 48 && b <= 57) {
    return new Ok(b - 48);
  } else {
    let b$1 = byte;
    if (b$1 >= 65 && b$1 <= 70) {
      return new Ok(b$1 - 65 + 10);
    } else {
      let b$2 = byte;
      if (b$2 >= 97 && b$2 <= 102) {
        return new Ok(b$2 - 97 + 10);
      } else {
        return new Error2(undefined);
      }
    }
  }
}
function four_hex(buffer, original) {
  if (buffer.bitSize >= 8 && buffer.bitSize >= 16 && buffer.bitSize >= 24 && buffer.bitSize >= 32) {
    let a = buffer.byteAt(0);
    let b = buffer.byteAt(1);
    let c = buffer.byteAt(2);
    let d = buffer.byteAt(3);
    let rest = bitArraySlice(buffer, 32);
    let $ = hex(a);
    let $1 = hex(b);
    let $2 = hex(c);
    let $3 = hex(d);
    if ($ instanceof Ok && $1 instanceof Ok && $2 instanceof Ok && $3 instanceof Ok) {
      let av = $[0];
      let bv = $1[0];
      let cv = $2[0];
      let dv = $3[0];
      return new Ok([av * 4096 + bv * 256 + cv * 16 + dv, rest]);
    } else {
      return new Error2(new UnexpectedToken(original));
    }
  } else {
    return new Error2(Reason$UnexpectedEnd$const);
  }
}
function codepoint2(point, original) {
  let $ = utf_codepoint(point);
  if ($ instanceof Ok) {
    return $;
  } else {
    return new Error2(new UnexpectedToken(original));
  }
}
function unicode_escape(rest, buffer) {
  return try$(four_hex(rest, buffer), (_use0) => {
    let n = _use0[0];
    let rest$1 = _use0[1];
    let n$1 = n;
    if (n$1 >= 55296 && n$1 <= 56319) {
      if (rest$1.bitSize >= 16 && rest$1.byteAt(0) === 92 && rest$1.byteAt(1) === 117) {
        let after = bitArraySlice(rest$1, 16);
        return try$(four_hex(after, buffer), (_use02) => {
          let low = _use02[0];
          let rest2 = _use02[1];
          let low$1 = low;
          if (low$1 >= 56320 && low$1 <= 57343) {
            let point = 65536 + (n$1 - 55296) * 1024 + (low$1 - 56320);
            let _pipe = codepoint2(point, buffer);
            return map4(_pipe, (c) => {
              return [c, rest2];
            });
          } else {
            return new Error2(new UnexpectedToken(buffer));
          }
        });
      } else {
        return new Error2(new UnexpectedToken(buffer));
      }
    } else {
      let n$2 = n;
      if (n$2 >= 56320 && n$2 <= 57343) {
        return new Error2(new UnexpectedToken(buffer));
      } else {
        let _pipe = codepoint2(n, buffer);
        return map4(_pipe, (c) => {
          return [c, rest$1];
        });
      }
    }
  });
}
function string5(loop$buffer, loop$acc) {
  while (true) {
    let buffer = loop$buffer;
    let acc = loop$acc;
    if (buffer.bitSize >= 8) {
      if (buffer.byteAt(0) === 34) {
        let rest = bitArraySlice(buffer, 8);
        let bytes = to_bit_array(acc);
        let $ = bit_array_to_string(bytes);
        if ($ instanceof Ok) {
          let value$1 = $[0];
          return new Ok([value$1, rest]);
        } else {
          return new Error2(new InvalidString(bytes));
        }
      } else if (buffer.bitSize >= 16) {
        if (buffer.byteAt(0) === 92 && buffer.byteAt(1) === 34) {
          let rest = bitArraySlice(buffer, 16);
          loop$buffer = rest;
          loop$acc = append4(acc, toBitArray([stringBits('"')]));
        } else if (buffer.byteAt(0) === 92 && buffer.byteAt(1) === 92) {
          let rest = bitArraySlice(buffer, 16);
          loop$buffer = rest;
          loop$acc = append4(acc, toBitArray([stringBits("\\")]));
        } else if (buffer.byteAt(0) === 92 && buffer.byteAt(1) === 47) {
          let rest = bitArraySlice(buffer, 16);
          loop$buffer = rest;
          loop$acc = append4(acc, toBitArray([stringBits("/")]));
        } else if (buffer.byteAt(0) === 92 && buffer.byteAt(1) === 98) {
          let rest = bitArraySlice(buffer, 16);
          loop$buffer = rest;
          loop$acc = append4(acc, toBitArray([8]));
        } else if (buffer.byteAt(0) === 92 && buffer.byteAt(1) === 102) {
          let rest = bitArraySlice(buffer, 16);
          loop$buffer = rest;
          loop$acc = append4(acc, toBitArray([stringBits("\f")]));
        } else if (buffer.byteAt(0) === 92 && buffer.byteAt(1) === 110) {
          let rest = bitArraySlice(buffer, 16);
          loop$buffer = rest;
          loop$acc = append4(acc, toBitArray([stringBits(`
`)]));
        } else if (buffer.byteAt(0) === 92 && buffer.byteAt(1) === 114) {
          let rest = bitArraySlice(buffer, 16);
          loop$buffer = rest;
          loop$acc = append4(acc, toBitArray([stringBits("\r")]));
        } else if (buffer.byteAt(0) === 92 && buffer.byteAt(1) === 116) {
          let rest = bitArraySlice(buffer, 16);
          loop$buffer = rest;
          loop$acc = append4(acc, toBitArray([stringBits("\t")]));
        } else if (buffer.byteAt(0) === 92 && buffer.byteAt(1) === 117) {
          let rest = bitArraySlice(buffer, 16);
          return try$(unicode_escape(rest, buffer), (_use0) => {
            let point = _use0[0];
            let rest$1 = _use0[1];
            return string5(rest$1, append4(acc, toBitArray([codepointBits(point)])));
          });
        } else if (buffer.byteAt(0) === 92) {
          return new Error2(new UnexpectedToken(buffer));
        } else {
          let b = buffer.byteAt(0);
          let rest = bitArraySlice(buffer, 8);
          loop$buffer = rest;
          loop$acc = append4(acc, toBitArray([b]));
        }
      } else if (buffer.byteAt(0) === 92) {
        return new Error2(new UnexpectedToken(buffer));
      } else {
        let b = buffer.byteAt(0);
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$acc = append4(acc, toBitArray([b]));
      }
    } else if (buffer.bitSize === 0) {
      return new Error2(Reason$UnexpectedEnd$const);
    } else {
      return new Error2(new UnexpectedToken(buffer));
    }
  }
}
function digits(loop$buffer, loop$n, loop$size) {
  while (true) {
    let buffer = loop$buffer;
    let n = loop$n;
    let size2 = loop$size;
    if (buffer.bitSize >= 8) {
      if (buffer.byteAt(0) === 49) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$n = n * 10 + 1;
        loop$size = size2 + 1;
      } else if (buffer.byteAt(0) === 50) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$n = n * 10 + 2;
        loop$size = size2 + 1;
      } else if (buffer.byteAt(0) === 51) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$n = n * 10 + 3;
        loop$size = size2 + 1;
      } else if (buffer.byteAt(0) === 52) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$n = n * 10 + 4;
        loop$size = size2 + 1;
      } else if (buffer.byteAt(0) === 53) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$n = n * 10 + 5;
        loop$size = size2 + 1;
      } else if (buffer.byteAt(0) === 54) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$n = n * 10 + 6;
        loop$size = size2 + 1;
      } else if (buffer.byteAt(0) === 55) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$n = n * 10 + 7;
        loop$size = size2 + 1;
      } else if (buffer.byteAt(0) === 56) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$n = n * 10 + 8;
        loop$size = size2 + 1;
      } else if (buffer.byteAt(0) === 57) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$n = n * 10 + 9;
        loop$size = size2 + 1;
      } else if (buffer.byteAt(0) === 48) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$n = n * 10 + 0;
        loop$size = size2 + 1;
      } else {
        return [n, size2, buffer];
      }
    } else {
      return [n, size2, buffer];
    }
  }
}
function separator(loop$buffer, loop$stack, loop$acc) {
  while (true) {
    let buffer = loop$buffer;
    let stack = loop$stack;
    let acc = loop$acc;
    if (buffer.bitSize >= 8) {
      if (buffer.byteAt(0) === 13) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 10) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 32) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 9) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 58) {
        let rest = bitArraySlice(buffer, 8);
        return value(rest, stack, acc);
      } else {
        return new Error2(new UnexpectedToken(buffer));
      }
    } else if (buffer.bitSize === 0) {
      return new Error2(Reason$UnexpectedEnd$const);
    } else {
      return new Error2(new UnexpectedToken(buffer));
    }
  }
}
function key2(loop$buffer, loop$stack, loop$acc) {
  while (true) {
    let buffer = loop$buffer;
    let stack = loop$stack;
    let acc = loop$acc;
    let depth = length2(stack);
    if (buffer.bitSize >= 8) {
      if (buffer.byteAt(0) === 13) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 10) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 32) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 9) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 34) {
        let rest = bitArraySlice(buffer, 8);
        return try$(string5(rest, new$()), (_use0) => {
          let extracted = _use0[0];
          let rest$1 = _use0[1];
          return separator(rest$1, stack, prepend([new Field(extracted), depth], acc));
        });
      } else if (buffer.byteAt(0) === 125) {
        let rest = bitArraySlice(buffer, 8);
        let stack$1;
        if (stack instanceof Empty) {
          throw makeError("let_assert", FILEPATH10, "julienne", 114, "key", "Pattern match failed, no pattern matched the value.", {
            value: stack,
            start: 4076,
            end: 4117,
            pattern_start: 4087,
            pattern_end: 4109
          });
        } else if (stack.head instanceof ObjectField) {
          stack$1 = stack.tail;
        } else {
          throw makeError("let_assert", FILEPATH10, "julienne", 114, "key", "Pattern match failed, no pattern matched the value.", {
            value: stack,
            start: 4076,
            end: 4117,
            pattern_start: 4087,
            pattern_end: 4109
          });
        }
        return continue$(rest, stack$1, acc);
      } else {
        return new Error2(new UnexpectedToken(buffer));
      }
    } else if (buffer.bitSize === 0) {
      return new Error2(Reason$UnexpectedEnd$const);
    } else {
      return new Error2(new UnexpectedToken(buffer));
    }
  }
}
function continue$(loop$buffer, loop$stack, loop$acc) {
  while (true) {
    let buffer = loop$buffer;
    let stack = loop$stack;
    let acc = loop$acc;
    if (buffer.bitSize >= 8) {
      if (buffer.byteAt(0) === 13) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 10) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 32) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 9) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (stack instanceof Empty) {
        return new Ok(reverse(acc));
      } else if (stack.head instanceof ArrayItem) {
        if (buffer.byteAt(0) === 93) {
          let stack$1 = stack.tail;
          let rest = bitArraySlice(buffer, 8);
          loop$buffer = rest;
          loop$stack = stack$1;
          loop$acc = acc;
        } else if (buffer.byteAt(0) === 44) {
          let rest = bitArraySlice(buffer, 8);
          return value(rest, stack, acc);
        } else {
          return new Error2(new UnexpectedToken(buffer));
        }
      } else if (buffer.byteAt(0) === 125) {
        let stack$1 = stack.tail;
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack$1;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 44) {
        let rest = bitArraySlice(buffer, 8);
        return key2(rest, stack, acc);
      } else {
        return new Error2(new UnexpectedToken(buffer));
      }
    } else if (stack instanceof Empty) {
      return new Ok(reverse(acc));
    } else if (buffer.bitSize === 0) {
      return new Error2(Reason$UnexpectedEnd$const);
    } else {
      return new Error2(new UnexpectedToken(buffer));
    }
  }
}
function start_exponent(sign, integer, decimal, rest, stack, acc) {
  let _block;
  if (rest.bitSize >= 8) {
    if (rest.byteAt(0) === 43) {
      let rest$12 = bitArraySlice(rest, 8);
      _block = [Sign$Positive$const2, rest$12];
    } else if (rest.byteAt(0) === 45) {
      let rest$12 = bitArraySlice(rest, 8);
      _block = [Sign$Negative$const2, rest$12];
    } else {
      _block = [Sign$Positive$const2, rest];
    }
  } else {
    _block = [Sign$Positive$const2, rest];
  }
  let $ = _block;
  let exp_sign = $[0];
  let rest$1 = $[1];
  let $1 = digits(rest$1, 0, 0);
  let exponent = $1[0];
  let size2 = $1[1];
  let rest$2 = $1[2];
  if (size2 === 0) {
    return new Error2(Reason$MissingDigits$const);
  } else {
    let _block$1;
    if (exp_sign instanceof Positive2) {
      _block$1 = exponent;
    } else {
      _block$1 = -exponent;
    }
    let exponent$1 = _block$1;
    let term = new Number2(sign, integer, decimal, exponent$1);
    return continue$(rest$2, stack, prepend([term, length2(stack)], acc));
  }
}
function start_decimal(sign, integer, rest, stack, acc) {
  let $ = digits(rest, 0, 0);
  let decimal = $[0];
  let size2 = $[1];
  let rest$1 = $[2];
  if (size2 === 0) {
    return new Error2(Reason$MissingDigits$const);
  } else {
    if (rest$1.bitSize >= 8) {
      if (rest$1.byteAt(0) === 101) {
        let rest$2 = bitArraySlice(rest$1, 8);
        return start_exponent(sign, integer, [decimal, size2], rest$2, stack, acc);
      } else if (rest$1.byteAt(0) === 69) {
        let rest$2 = bitArraySlice(rest$1, 8);
        return start_exponent(sign, integer, [decimal, size2], rest$2, stack, acc);
      } else {
        let term = new Number2(sign, integer, [decimal, size2], 0);
        return continue$(rest$1, stack, prepend([term, length2(stack)], acc));
      }
    } else {
      let term = new Number2(sign, integer, [decimal, size2], 0);
      return continue$(rest$1, stack, prepend([term, length2(stack)], acc));
    }
  }
}
function start_number(sign, first, rest, stack, acc) {
  let $ = digits(rest, first, 1);
  let n = $[0];
  let rest$1 = $[2];
  if (rest$1.bitSize >= 8) {
    if (rest$1.byteAt(0) === 46) {
      let rest$2 = bitArraySlice(rest$1, 8);
      return start_decimal(sign, n, rest$2, stack, acc);
    } else if (rest$1.byteAt(0) === 101) {
      let rest$2 = bitArraySlice(rest$1, 8);
      return start_exponent(sign, n, [0, 0], rest$2, stack, acc);
    } else if (rest$1.byteAt(0) === 69) {
      let rest$2 = bitArraySlice(rest$1, 8);
      return start_exponent(sign, n, [0, 0], rest$2, stack, acc);
    } else {
      let _block;
      if (sign instanceof Positive2) {
        _block = n;
      } else {
        _block = -n;
      }
      let n$1 = _block;
      return continue$(rest$1, stack, prepend([new Integer4(n$1), length2(stack)], acc));
    }
  } else {
    let _block;
    if (sign instanceof Positive2) {
      _block = n;
    } else {
      _block = -n;
    }
    let n$1 = _block;
    return continue$(rest$1, stack, prepend([new Integer4(n$1), length2(stack)], acc));
  }
}
function value(loop$buffer, loop$stack, loop$acc) {
  while (true) {
    let buffer = loop$buffer;
    let stack = loop$stack;
    let acc = loop$acc;
    let depth = length2(stack);
    if (buffer.bitSize >= 8) {
      if (buffer.byteAt(0) === 13) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 10) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 32) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.byteAt(0) === 9) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = stack;
        loop$acc = acc;
      } else if (buffer.bitSize >= 32) {
        if (buffer.byteAt(0) === 116 && buffer.byteAt(1) === 114 && buffer.byteAt(2) === 117 && buffer.byteAt(3) === 101) {
          let rest = bitArraySlice(buffer, 32);
          return continue$(rest, stack, prepend([new Boolean2(true), depth], acc));
        } else if (buffer.bitSize >= 40) {
          if (buffer.byteAt(0) === 102 && buffer.byteAt(1) === 97 && buffer.byteAt(2) === 108 && buffer.byteAt(3) === 115 && buffer.byteAt(4) === 101) {
            let rest = bitArraySlice(buffer, 40);
            return continue$(rest, stack, prepend([new Boolean2(false), depth], acc));
          } else if (buffer.byteAt(0) === 110 && buffer.byteAt(1) === 117 && buffer.byteAt(2) === 108 && buffer.byteAt(3) === 108) {
            let rest = bitArraySlice(buffer, 32);
            return continue$(rest, stack, prepend([Term$Null$const, depth], acc));
          } else if (buffer.byteAt(0) === 91) {
            let rest = bitArraySlice(buffer, 8);
            loop$buffer = rest;
            loop$stack = prepend(Stack$ArrayItem$const, stack);
            loop$acc = prepend([Term$Array$const, depth], acc);
          } else if (buffer.byteAt(0) === 123) {
            let rest = bitArraySlice(buffer, 8);
            let acc$1 = prepend([Term$Object$const, depth], acc);
            let stack$1 = prepend(Stack$ObjectField$const, stack);
            return key2(rest, stack$1, acc$1);
          } else if (stack instanceof Empty) {
            if (buffer.byteAt(0) === 34) {
              let rest = bitArraySlice(buffer, 8);
              return try$(string5(rest, new$()), (_use0) => {
                let extracted = _use0[0];
                let rest$1 = _use0[1];
                return continue$(rest$1, stack, prepend([new String5(extracted), depth], acc));
              });
            } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 46) {
              let rest = bitArraySlice(buffer, 16);
              return start_decimal(Sign$Positive$const2, 0, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 46) {
              let rest = bitArraySlice(buffer, 24);
              return start_decimal(Sign$Negative$const2, 0, rest, stack, acc);
            } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 101) {
              let rest = bitArraySlice(buffer, 16);
              return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
            } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 69) {
              let rest = bitArraySlice(buffer, 16);
              return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 101) {
              let rest = bitArraySlice(buffer, 24);
              return start_exponent(Sign$Negative$const2, 0, [0, 0], rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 69) {
              let rest = bitArraySlice(buffer, 24);
              return start_exponent(Sign$Negative$const2, 0, [0, 0], rest, stack, acc);
            } else if (buffer.byteAt(0) === 48) {
              let rest = bitArraySlice(buffer, 8);
              return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48) {
              let rest = bitArraySlice(buffer, 16);
              return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
            } else if (buffer.byteAt(0) === 49) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 1, rest, stack, acc);
            } else if (buffer.byteAt(0) === 50) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 2, rest, stack, acc);
            } else if (buffer.byteAt(0) === 51) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 3, rest, stack, acc);
            } else if (buffer.byteAt(0) === 52) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 4, rest, stack, acc);
            } else if (buffer.byteAt(0) === 53) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 5, rest, stack, acc);
            } else if (buffer.byteAt(0) === 54) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 6, rest, stack, acc);
            } else if (buffer.byteAt(0) === 55) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 7, rest, stack, acc);
            } else if (buffer.byteAt(0) === 56) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 8, rest, stack, acc);
            } else if (buffer.byteAt(0) === 57) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 9, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 49) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 1, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 50) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 2, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 51) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 3, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 52) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 4, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 53) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 5, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 54) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 6, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 55) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 7, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 56) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 8, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 57) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 9, rest, stack, acc);
            } else {
              return new Error2(new UnexpectedToken(buffer));
            }
          } else if (stack.head instanceof ArrayItem && buffer.byteAt(0) === 93) {
            let stack$1 = stack.tail;
            let rest = bitArraySlice(buffer, 8);
            return continue$(rest, stack$1, acc);
          } else if (buffer.byteAt(0) === 34) {
            let rest = bitArraySlice(buffer, 8);
            return try$(string5(rest, new$()), (_use0) => {
              let extracted = _use0[0];
              let rest$1 = _use0[1];
              return continue$(rest$1, stack, prepend([new String5(extracted), depth], acc));
            });
          } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 46) {
            let rest = bitArraySlice(buffer, 16);
            return start_decimal(Sign$Positive$const2, 0, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 46) {
            let rest = bitArraySlice(buffer, 24);
            return start_decimal(Sign$Negative$const2, 0, rest, stack, acc);
          } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 101) {
            let rest = bitArraySlice(buffer, 16);
            return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 69) {
            let rest = bitArraySlice(buffer, 16);
            return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 101) {
            let rest = bitArraySlice(buffer, 24);
            return start_exponent(Sign$Negative$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 69) {
            let rest = bitArraySlice(buffer, 24);
            return start_exponent(Sign$Negative$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 48) {
            let rest = bitArraySlice(buffer, 8);
            return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48) {
            let rest = bitArraySlice(buffer, 16);
            return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
          } else if (buffer.byteAt(0) === 49) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 1, rest, stack, acc);
          } else if (buffer.byteAt(0) === 50) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 2, rest, stack, acc);
          } else if (buffer.byteAt(0) === 51) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 3, rest, stack, acc);
          } else if (buffer.byteAt(0) === 52) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 4, rest, stack, acc);
          } else if (buffer.byteAt(0) === 53) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 5, rest, stack, acc);
          } else if (buffer.byteAt(0) === 54) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 6, rest, stack, acc);
          } else if (buffer.byteAt(0) === 55) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 7, rest, stack, acc);
          } else if (buffer.byteAt(0) === 56) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 8, rest, stack, acc);
          } else if (buffer.byteAt(0) === 57) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 9, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 49) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 1, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 50) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 2, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 51) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 3, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 52) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 4, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 53) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 5, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 54) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 6, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 55) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 7, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 56) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 8, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 57) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 9, rest, stack, acc);
          } else {
            return new Error2(new UnexpectedToken(buffer));
          }
        } else if (buffer.byteAt(0) === 110 && buffer.byteAt(1) === 117 && buffer.byteAt(2) === 108 && buffer.byteAt(3) === 108) {
          let rest = bitArraySlice(buffer, 32);
          return continue$(rest, stack, prepend([Term$Null$const, depth], acc));
        } else if (buffer.byteAt(0) === 91) {
          let rest = bitArraySlice(buffer, 8);
          loop$buffer = rest;
          loop$stack = prepend(Stack$ArrayItem$const, stack);
          loop$acc = prepend([Term$Array$const, depth], acc);
        } else if (buffer.byteAt(0) === 123) {
          let rest = bitArraySlice(buffer, 8);
          let acc$1 = prepend([Term$Object$const, depth], acc);
          let stack$1 = prepend(Stack$ObjectField$const, stack);
          return key2(rest, stack$1, acc$1);
        } else if (stack instanceof Empty) {
          if (buffer.byteAt(0) === 34) {
            let rest = bitArraySlice(buffer, 8);
            return try$(string5(rest, new$()), (_use0) => {
              let extracted = _use0[0];
              let rest$1 = _use0[1];
              return continue$(rest$1, stack, prepend([new String5(extracted), depth], acc));
            });
          } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 46) {
            let rest = bitArraySlice(buffer, 16);
            return start_decimal(Sign$Positive$const2, 0, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 46) {
            let rest = bitArraySlice(buffer, 24);
            return start_decimal(Sign$Negative$const2, 0, rest, stack, acc);
          } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 101) {
            let rest = bitArraySlice(buffer, 16);
            return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 69) {
            let rest = bitArraySlice(buffer, 16);
            return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 101) {
            let rest = bitArraySlice(buffer, 24);
            return start_exponent(Sign$Negative$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 69) {
            let rest = bitArraySlice(buffer, 24);
            return start_exponent(Sign$Negative$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 48) {
            let rest = bitArraySlice(buffer, 8);
            return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48) {
            let rest = bitArraySlice(buffer, 16);
            return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
          } else if (buffer.byteAt(0) === 49) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 1, rest, stack, acc);
          } else if (buffer.byteAt(0) === 50) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 2, rest, stack, acc);
          } else if (buffer.byteAt(0) === 51) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 3, rest, stack, acc);
          } else if (buffer.byteAt(0) === 52) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 4, rest, stack, acc);
          } else if (buffer.byteAt(0) === 53) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 5, rest, stack, acc);
          } else if (buffer.byteAt(0) === 54) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 6, rest, stack, acc);
          } else if (buffer.byteAt(0) === 55) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 7, rest, stack, acc);
          } else if (buffer.byteAt(0) === 56) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 8, rest, stack, acc);
          } else if (buffer.byteAt(0) === 57) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 9, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 49) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 1, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 50) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 2, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 51) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 3, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 52) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 4, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 53) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 5, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 54) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 6, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 55) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 7, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 56) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 8, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 57) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 9, rest, stack, acc);
          } else {
            return new Error2(new UnexpectedToken(buffer));
          }
        } else if (stack.head instanceof ArrayItem && buffer.byteAt(0) === 93) {
          let stack$1 = stack.tail;
          let rest = bitArraySlice(buffer, 8);
          return continue$(rest, stack$1, acc);
        } else if (buffer.byteAt(0) === 34) {
          let rest = bitArraySlice(buffer, 8);
          return try$(string5(rest, new$()), (_use0) => {
            let extracted = _use0[0];
            let rest$1 = _use0[1];
            return continue$(rest$1, stack, prepend([new String5(extracted), depth], acc));
          });
        } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 46) {
          let rest = bitArraySlice(buffer, 16);
          return start_decimal(Sign$Positive$const2, 0, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 46) {
          let rest = bitArraySlice(buffer, 24);
          return start_decimal(Sign$Negative$const2, 0, rest, stack, acc);
        } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 101) {
          let rest = bitArraySlice(buffer, 16);
          return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
        } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 69) {
          let rest = bitArraySlice(buffer, 16);
          return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 101) {
          let rest = bitArraySlice(buffer, 24);
          return start_exponent(Sign$Negative$const2, 0, [0, 0], rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 69) {
          let rest = bitArraySlice(buffer, 24);
          return start_exponent(Sign$Negative$const2, 0, [0, 0], rest, stack, acc);
        } else if (buffer.byteAt(0) === 48) {
          let rest = bitArraySlice(buffer, 8);
          return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48) {
          let rest = bitArraySlice(buffer, 16);
          return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
        } else if (buffer.byteAt(0) === 49) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 1, rest, stack, acc);
        } else if (buffer.byteAt(0) === 50) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 2, rest, stack, acc);
        } else if (buffer.byteAt(0) === 51) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 3, rest, stack, acc);
        } else if (buffer.byteAt(0) === 52) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 4, rest, stack, acc);
        } else if (buffer.byteAt(0) === 53) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 5, rest, stack, acc);
        } else if (buffer.byteAt(0) === 54) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 6, rest, stack, acc);
        } else if (buffer.byteAt(0) === 55) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 7, rest, stack, acc);
        } else if (buffer.byteAt(0) === 56) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 8, rest, stack, acc);
        } else if (buffer.byteAt(0) === 57) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 9, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 49) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 1, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 50) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 2, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 51) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 3, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 52) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 4, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 53) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 5, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 54) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 6, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 55) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 7, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 56) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 8, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 57) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 9, rest, stack, acc);
        } else {
          return new Error2(new UnexpectedToken(buffer));
        }
      } else if (buffer.byteAt(0) === 91) {
        let rest = bitArraySlice(buffer, 8);
        loop$buffer = rest;
        loop$stack = prepend(Stack$ArrayItem$const, stack);
        loop$acc = prepend([Term$Array$const, depth], acc);
      } else if (buffer.byteAt(0) === 123) {
        let rest = bitArraySlice(buffer, 8);
        let acc$1 = prepend([Term$Object$const, depth], acc);
        let stack$1 = prepend(Stack$ObjectField$const, stack);
        return key2(rest, stack$1, acc$1);
      } else if (stack instanceof Empty) {
        if (buffer.byteAt(0) === 34) {
          let rest = bitArraySlice(buffer, 8);
          return try$(string5(rest, new$()), (_use0) => {
            let extracted = _use0[0];
            let rest$1 = _use0[1];
            return continue$(rest$1, stack, prepend([new String5(extracted), depth], acc));
          });
        } else if (buffer.bitSize >= 16) {
          if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 46) {
            let rest = bitArraySlice(buffer, 16);
            return start_decimal(Sign$Positive$const2, 0, rest, stack, acc);
          } else if (buffer.bitSize >= 24) {
            if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 46) {
              let rest = bitArraySlice(buffer, 24);
              return start_decimal(Sign$Negative$const2, 0, rest, stack, acc);
            } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 101) {
              let rest = bitArraySlice(buffer, 16);
              return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
            } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 69) {
              let rest = bitArraySlice(buffer, 16);
              return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 101) {
              let rest = bitArraySlice(buffer, 24);
              return start_exponent(Sign$Negative$const2, 0, [0, 0], rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 69) {
              let rest = bitArraySlice(buffer, 24);
              return start_exponent(Sign$Negative$const2, 0, [0, 0], rest, stack, acc);
            } else if (buffer.byteAt(0) === 48) {
              let rest = bitArraySlice(buffer, 8);
              return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48) {
              let rest = bitArraySlice(buffer, 16);
              return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
            } else if (buffer.byteAt(0) === 49) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 1, rest, stack, acc);
            } else if (buffer.byteAt(0) === 50) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 2, rest, stack, acc);
            } else if (buffer.byteAt(0) === 51) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 3, rest, stack, acc);
            } else if (buffer.byteAt(0) === 52) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 4, rest, stack, acc);
            } else if (buffer.byteAt(0) === 53) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 5, rest, stack, acc);
            } else if (buffer.byteAt(0) === 54) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 6, rest, stack, acc);
            } else if (buffer.byteAt(0) === 55) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 7, rest, stack, acc);
            } else if (buffer.byteAt(0) === 56) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 8, rest, stack, acc);
            } else if (buffer.byteAt(0) === 57) {
              let rest = bitArraySlice(buffer, 8);
              return start_number(Sign$Positive$const2, 9, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 49) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 1, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 50) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 2, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 51) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 3, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 52) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 4, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 53) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 5, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 54) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 6, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 55) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 7, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 56) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 8, rest, stack, acc);
            } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 57) {
              let rest = bitArraySlice(buffer, 16);
              return start_number(Sign$Negative$const2, 9, rest, stack, acc);
            } else {
              return new Error2(new UnexpectedToken(buffer));
            }
          } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 101) {
            let rest = bitArraySlice(buffer, 16);
            return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 69) {
            let rest = bitArraySlice(buffer, 16);
            return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 48) {
            let rest = bitArraySlice(buffer, 8);
            return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48) {
            let rest = bitArraySlice(buffer, 16);
            return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
          } else if (buffer.byteAt(0) === 49) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 1, rest, stack, acc);
          } else if (buffer.byteAt(0) === 50) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 2, rest, stack, acc);
          } else if (buffer.byteAt(0) === 51) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 3, rest, stack, acc);
          } else if (buffer.byteAt(0) === 52) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 4, rest, stack, acc);
          } else if (buffer.byteAt(0) === 53) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 5, rest, stack, acc);
          } else if (buffer.byteAt(0) === 54) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 6, rest, stack, acc);
          } else if (buffer.byteAt(0) === 55) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 7, rest, stack, acc);
          } else if (buffer.byteAt(0) === 56) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 8, rest, stack, acc);
          } else if (buffer.byteAt(0) === 57) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 9, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 49) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 1, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 50) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 2, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 51) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 3, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 52) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 4, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 53) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 5, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 54) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 6, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 55) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 7, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 56) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 8, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 57) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 9, rest, stack, acc);
          } else {
            return new Error2(new UnexpectedToken(buffer));
          }
        } else if (buffer.byteAt(0) === 48) {
          let rest = bitArraySlice(buffer, 8);
          return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
        } else if (buffer.byteAt(0) === 49) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 1, rest, stack, acc);
        } else if (buffer.byteAt(0) === 50) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 2, rest, stack, acc);
        } else if (buffer.byteAt(0) === 51) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 3, rest, stack, acc);
        } else if (buffer.byteAt(0) === 52) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 4, rest, stack, acc);
        } else if (buffer.byteAt(0) === 53) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 5, rest, stack, acc);
        } else if (buffer.byteAt(0) === 54) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 6, rest, stack, acc);
        } else if (buffer.byteAt(0) === 55) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 7, rest, stack, acc);
        } else if (buffer.byteAt(0) === 56) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 8, rest, stack, acc);
        } else if (buffer.byteAt(0) === 57) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 9, rest, stack, acc);
        } else {
          return new Error2(new UnexpectedToken(buffer));
        }
      } else if (stack.head instanceof ArrayItem && buffer.byteAt(0) === 93) {
        let stack$1 = stack.tail;
        let rest = bitArraySlice(buffer, 8);
        return continue$(rest, stack$1, acc);
      } else if (buffer.byteAt(0) === 34) {
        let rest = bitArraySlice(buffer, 8);
        return try$(string5(rest, new$()), (_use0) => {
          let extracted = _use0[0];
          let rest$1 = _use0[1];
          return continue$(rest$1, stack, prepend([new String5(extracted), depth], acc));
        });
      } else if (buffer.bitSize >= 16) {
        if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 46) {
          let rest = bitArraySlice(buffer, 16);
          return start_decimal(Sign$Positive$const2, 0, rest, stack, acc);
        } else if (buffer.bitSize >= 24) {
          if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 46) {
            let rest = bitArraySlice(buffer, 24);
            return start_decimal(Sign$Negative$const2, 0, rest, stack, acc);
          } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 101) {
            let rest = bitArraySlice(buffer, 16);
            return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 69) {
            let rest = bitArraySlice(buffer, 16);
            return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 101) {
            let rest = bitArraySlice(buffer, 24);
            return start_exponent(Sign$Negative$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48 && buffer.byteAt(2) === 69) {
            let rest = bitArraySlice(buffer, 24);
            return start_exponent(Sign$Negative$const2, 0, [0, 0], rest, stack, acc);
          } else if (buffer.byteAt(0) === 48) {
            let rest = bitArraySlice(buffer, 8);
            return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48) {
            let rest = bitArraySlice(buffer, 16);
            return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
          } else if (buffer.byteAt(0) === 49) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 1, rest, stack, acc);
          } else if (buffer.byteAt(0) === 50) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 2, rest, stack, acc);
          } else if (buffer.byteAt(0) === 51) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 3, rest, stack, acc);
          } else if (buffer.byteAt(0) === 52) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 4, rest, stack, acc);
          } else if (buffer.byteAt(0) === 53) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 5, rest, stack, acc);
          } else if (buffer.byteAt(0) === 54) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 6, rest, stack, acc);
          } else if (buffer.byteAt(0) === 55) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 7, rest, stack, acc);
          } else if (buffer.byteAt(0) === 56) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 8, rest, stack, acc);
          } else if (buffer.byteAt(0) === 57) {
            let rest = bitArraySlice(buffer, 8);
            return start_number(Sign$Positive$const2, 9, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 49) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 1, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 50) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 2, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 51) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 3, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 52) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 4, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 53) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 5, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 54) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 6, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 55) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 7, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 56) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 8, rest, stack, acc);
          } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 57) {
            let rest = bitArraySlice(buffer, 16);
            return start_number(Sign$Negative$const2, 9, rest, stack, acc);
          } else {
            return new Error2(new UnexpectedToken(buffer));
          }
        } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 101) {
          let rest = bitArraySlice(buffer, 16);
          return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
        } else if (buffer.byteAt(0) === 48 && buffer.byteAt(1) === 69) {
          let rest = bitArraySlice(buffer, 16);
          return start_exponent(Sign$Positive$const2, 0, [0, 0], rest, stack, acc);
        } else if (buffer.byteAt(0) === 48) {
          let rest = bitArraySlice(buffer, 8);
          return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 48) {
          let rest = bitArraySlice(buffer, 16);
          return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
        } else if (buffer.byteAt(0) === 49) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 1, rest, stack, acc);
        } else if (buffer.byteAt(0) === 50) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 2, rest, stack, acc);
        } else if (buffer.byteAt(0) === 51) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 3, rest, stack, acc);
        } else if (buffer.byteAt(0) === 52) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 4, rest, stack, acc);
        } else if (buffer.byteAt(0) === 53) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 5, rest, stack, acc);
        } else if (buffer.byteAt(0) === 54) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 6, rest, stack, acc);
        } else if (buffer.byteAt(0) === 55) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 7, rest, stack, acc);
        } else if (buffer.byteAt(0) === 56) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 8, rest, stack, acc);
        } else if (buffer.byteAt(0) === 57) {
          let rest = bitArraySlice(buffer, 8);
          return start_number(Sign$Positive$const2, 9, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 49) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 1, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 50) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 2, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 51) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 3, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 52) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 4, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 53) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 5, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 54) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 6, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 55) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 7, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 56) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 8, rest, stack, acc);
        } else if (buffer.byteAt(0) === 45 && buffer.byteAt(1) === 57) {
          let rest = bitArraySlice(buffer, 16);
          return start_number(Sign$Negative$const2, 9, rest, stack, acc);
        } else {
          return new Error2(new UnexpectedToken(buffer));
        }
      } else if (buffer.byteAt(0) === 48) {
        let rest = bitArraySlice(buffer, 8);
        return continue$(rest, stack, prepend([new Integer4(0), depth], acc));
      } else if (buffer.byteAt(0) === 49) {
        let rest = bitArraySlice(buffer, 8);
        return start_number(Sign$Positive$const2, 1, rest, stack, acc);
      } else if (buffer.byteAt(0) === 50) {
        let rest = bitArraySlice(buffer, 8);
        return start_number(Sign$Positive$const2, 2, rest, stack, acc);
      } else if (buffer.byteAt(0) === 51) {
        let rest = bitArraySlice(buffer, 8);
        return start_number(Sign$Positive$const2, 3, rest, stack, acc);
      } else if (buffer.byteAt(0) === 52) {
        let rest = bitArraySlice(buffer, 8);
        return start_number(Sign$Positive$const2, 4, rest, stack, acc);
      } else if (buffer.byteAt(0) === 53) {
        let rest = bitArraySlice(buffer, 8);
        return start_number(Sign$Positive$const2, 5, rest, stack, acc);
      } else if (buffer.byteAt(0) === 54) {
        let rest = bitArraySlice(buffer, 8);
        return start_number(Sign$Positive$const2, 6, rest, stack, acc);
      } else if (buffer.byteAt(0) === 55) {
        let rest = bitArraySlice(buffer, 8);
        return start_number(Sign$Positive$const2, 7, rest, stack, acc);
      } else if (buffer.byteAt(0) === 56) {
        let rest = bitArraySlice(buffer, 8);
        return start_number(Sign$Positive$const2, 8, rest, stack, acc);
      } else if (buffer.byteAt(0) === 57) {
        let rest = bitArraySlice(buffer, 8);
        return start_number(Sign$Positive$const2, 9, rest, stack, acc);
      } else {
        return new Error2(new UnexpectedToken(buffer));
      }
    } else if (buffer.bitSize === 0) {
      return new Error2(Reason$UnexpectedEnd$const);
    } else {
      return new Error2(new UnexpectedToken(buffer));
    }
  }
}
function parse_bits2(buffer) {
  return value(buffer, List$Empty$const, List$Empty$const);
}
function print_bit_array(bit_array3) {
  let $ = bit_array_to_string(bit_array3);
  if ($ instanceof Ok) {
    let string$1 = $[0];
    return string$1;
  } else {
    return inspect2(bit_array3);
  }
}
function describe_reason(reason) {
  if (reason instanceof UnexpectedEnd) {
    return "unexpected end of JSON";
  } else if (reason instanceof UnexpectedToken) {
    let bytes = reason[0];
    return print_bit_array(bytes);
  } else if (reason instanceof MissingDigits) {
    return "missing digits in number";
  } else {
    let bytes = reason[0];
    return print_bit_array(bytes);
  }
}

// build/dev/javascript/touch_grass/touch_grass/decode_json.mjs
var label5 = "DecodeJSON";
var decode9 = as_binary;
function lift4() {
  return Type$Binary$const;
}
function lower4() {
  return result(new List2(record(prepend([
    "term",
    union2(prepend(["True", unit], prepend(["False", unit], prepend(["Null", unit], prepend(["Integer", Type$Integer$const], prepend([
      "Number",
      record(prepend([
        "sign",
        union2(prepend(["Positive", unit], prepend(["Negative", unit], List$Empty$const)))
      ], prepend(["integer", Type$Integer$const], prepend([
        "decimal",
        record(prepend(["numerator", Type$Integer$const], prepend(["size", Type$Integer$const], List$Empty$const)))
      ], prepend(["exponent", Type$Integer$const], List$Empty$const)))))
    ], prepend(["String", Type$String$const], prepend(["Array", unit], prepend(["Object", unit], prepend(["Field", Type$String$const], List$Empty$const))))))))))
  ], prepend(["depth", Type$Integer$const], List$Empty$const)))), Type$String$const);
}
function encode9(result2) {
  if (result2 instanceof Ok) {
    let parsed = result2[0];
    let list3 = new LinkedList(map2(parsed, (item) => {
      let term = item[0];
      let depth = item[1];
      let _block;
      if (term instanceof Boolean2) {
        if (term[0]) {
          _block = true$();
        } else {
          _block = false$();
        }
      } else if (term instanceof Null) {
        _block = new Tagged("Null", unit2());
      } else if (term instanceof String5) {
        let value2 = term[0];
        _block = new Tagged("String", new String4(value2));
      } else if (term instanceof Integer4) {
        let i = term.integer;
        _block = new Tagged("Integer", new Integer3(i));
      } else if (term instanceof Number2) {
        let sign = term.sign;
        let integer = term.integer;
        let decimal = term.decimal;
        let exponent = term.exponent;
        _block = new Tagged("Number", new Record2(from_list(prepend([
          "sign",
          (() => {
            if (sign instanceof Positive2) {
              return new Tagged("Positive", unit2());
            } else {
              return new Tagged("Negative", unit2());
            }
          })()
        ], prepend(["integer", new Integer3(integer)], prepend([
          "decimal",
          new Record2(from_list(prepend(["numerator", new Integer3(decimal[0])], prepend(["size", new Integer3(decimal[1])], List$Empty$const))))
        ], prepend(["exponent", new Integer3(exponent)], List$Empty$const)))))));
      } else if (term instanceof Array2) {
        _block = new Tagged("Array", unit2());
      } else if (term instanceof Object2) {
        _block = new Tagged("Object", unit2());
      } else {
        let f = term[0];
        _block = new Tagged("Field", new String4(f));
      }
      let term$1 = _block;
      return new Record2(from_list(prepend(["term", term$1], prepend(["depth", new Integer3(depth)], List$Empty$const))));
    }));
    return ok(list3);
  } else {
    let reason = result2[0];
    return error(new String4(reason));
  }
}
function sync(raw) {
  let _block;
  let _pipe = parse_bits2(raw);
  _block = map_error(_pipe, describe_reason);
  let result2 = _block;
  return encode9(result2);
}

// build/dev/javascript/touch_grass/touch_grass/env.mjs
var label6 = "Env";
var decode10 = as_string;
function lift5() {
  return Type$String$const;
}
function lower5() {
  return option(Type$String$const);
}
function encode10(value2) {
  if (value2 instanceof Some) {
    let s = value2[0];
    return some(new String4(s));
  } else {
    return none();
  }
}

// build/dev/javascript/touch_grass/touch_grass/eyg_parse.mjs
var label7 = "EYGParse";
function lift6() {
  return Type$String$const;
}
function lower6() {
  return result(ast(), Type$String$const);
}
function decode11(lift7) {
  return as_string(lift7);
}
function tagged(tag2, attribute) {
  return new Tagged(tag2, attribute);
}
function flatten2(node2, rest) {
  let expression = node2[0];
  if (expression instanceof Variable) {
    let label$1 = expression.label;
    return prepend(tagged("Variable", new String4(label$1)), rest);
  } else if (expression instanceof Lambda) {
    let label$1 = expression.label;
    let body = expression.body;
    return prepend(tagged("Lambda", new String4(label$1)), flatten2(body, rest));
  } else if (expression instanceof Apply) {
    let function$ = expression.func;
    let argument = expression.argument;
    return prepend(tagged("Apply", unit2()), flatten2(function$, flatten2(argument, rest)));
  } else if (expression instanceof Let) {
    let label$1 = expression.label;
    let value2 = expression.definition;
    let then$3 = expression.body;
    return prepend(tagged("Let", new String4(label$1)), flatten2(value2, flatten2(then$3, rest)));
  } else if (expression instanceof Binary) {
    let value2 = expression.value;
    return prepend(tagged("Binary", new Binary3(value2)), rest);
  } else if (expression instanceof Integer) {
    let value2 = expression.value;
    return prepend(tagged("Integer", new Integer3(value2)), rest);
  } else if (expression instanceof String2) {
    let value2 = expression.value;
    return prepend(tagged("String", new String4(value2)), rest);
  } else if (expression instanceof Tail) {
    return prepend(tagged("Tail", unit2()), rest);
  } else if (expression instanceof Cons) {
    return prepend(tagged("Cons", unit2()), rest);
  } else if (expression instanceof Vacant) {
    return prepend(tagged("Vacant", unit2()), rest);
  } else if (expression instanceof Empty2) {
    return prepend(tagged("Empty", unit2()), rest);
  } else if (expression instanceof Extend) {
    let label$1 = expression.label;
    return prepend(tagged("Extend", new String4(label$1)), rest);
  } else if (expression instanceof Select) {
    let label$1 = expression.label;
    return prepend(tagged("Select", new String4(label$1)), rest);
  } else if (expression instanceof Overwrite) {
    let label$1 = expression.label;
    return prepend(tagged("Overwrite", new String4(label$1)), rest);
  } else if (expression instanceof Tag) {
    let label$1 = expression.label;
    return prepend(tagged("Tag", new String4(label$1)), rest);
  } else if (expression instanceof Case) {
    let label$1 = expression.label;
    return prepend(tagged("Case", new String4(label$1)), rest);
  } else if (expression instanceof NoCases) {
    return prepend(tagged("NoCases", unit2()), rest);
  } else if (expression instanceof Perform) {
    let label$1 = expression.label;
    return prepend(tagged("Perform", new String4(label$1)), rest);
  } else if (expression instanceof Handle) {
    let label$1 = expression.label;
    return prepend(tagged("Handle", new String4(label$1)), rest);
  } else if (expression instanceof Builtin) {
    let identifier = expression.identifier;
    return prepend(tagged("Builtin", new String4(identifier)), rest);
  } else {
    let reference2 = expression.reference;
    let _block;
    if (reference2 instanceof Content) {
      let identifier = reference2.cid;
      _block = tagged("Content", new String4(to_string2(identifier)));
    } else if (reference2 instanceof Package) {
      let package$2 = reference2.package;
      _block = tagged("Package", new String4(package$2));
    } else if (reference2 instanceof Version) {
      let package$2 = reference2.package;
      let version = reference2.version;
      _block = tagged("Version", new Record2(from_list(prepend(["package", new String4(package$2)], prepend(["version", new Integer3(version)], List$Empty$const)))));
    } else if (reference2 instanceof Pinned) {
      let package$2 = reference2.release.package;
      let version = reference2.release.version;
      let identifier = reference2.release.module;
      _block = tagged("Release", new Record2(from_list(prepend(["package", new String4(package$2)], prepend(["version", new Integer3(version)], prepend(["cid", new String4(to_string2(identifier))], List$Empty$const))))));
    } else {
      let location = reference2.location;
      _block = tagged("Relative", new String4(location));
    }
    let reference$1 = _block;
    return prepend(tagged("Reference", reference$1), rest);
  }
}
function encode11(result2) {
  if (result2 instanceof Ok) {
    let node2 = result2[0];
    return ok(new LinkedList(flatten2(node2, List$Empty$const)));
  } else {
    let message = result2[0];
    return error(new String4(message));
  }
}

// build/dev/javascript/touch_grass/touch_grass/http.mjs
function method() {
  return union2(prepend(["CONNECT", unit], prepend(["DELETE", unit], prepend(["GET", unit], prepend(["HEAD", unit], prepend(["OPTIONS", unit], prepend(["PATCH", unit], prepend(["POST", unit], prepend(["PUT", unit], prepend(["TRACE", unit], List$Empty$const))))))))));
}
function method_to_gleam(value2) {
  return as_varient(value2, prepend([
    "CONNECT",
    (_capture) => {
      return as_unit(_capture, Method$Connect$const);
    }
  ], prepend([
    "DELETE",
    (_capture) => {
      return as_unit(_capture, Method$Delete$const);
    }
  ], prepend([
    "GET",
    (_capture) => {
      return as_unit(_capture, Method$Get$const);
    }
  ], prepend([
    "HEAD",
    (_capture) => {
      return as_unit(_capture, Method$Head$const);
    }
  ], prepend([
    "OPTIONS",
    (_capture) => {
      return as_unit(_capture, Method$Options$const);
    }
  ], prepend([
    "PATCH",
    (_capture) => {
      return as_unit(_capture, Method$Patch$const);
    }
  ], prepend([
    "POST",
    (_capture) => {
      return as_unit(_capture, Method$Post$const);
    }
  ], prepend([
    "PUT",
    (_capture) => {
      return as_unit(_capture, Method$Put$const);
    }
  ], prepend([
    "TRACE",
    (_capture) => {
      return as_unit(_capture, Method$Trace$const);
    }
  ], prepend([
    "OTHER",
    (() => {
      let _pipe = as_string;
      return map5(_pipe, (var0) => {
        return new Other(var0);
      });
    })()
  ], List$Empty$const)))))))))));
}
function scheme() {
  return union2(prepend(["HTTP", unit], prepend(["HTTPS", unit], List$Empty$const)));
}
function scheme_to_gleam(value2) {
  return as_varient(value2, prepend([
    "HTTP",
    (_capture) => {
      return as_unit(_capture, Scheme$Http$const);
    }
  ], prepend([
    "HTTPS",
    (_capture) => {
      return as_unit(_capture, Scheme$Https$const);
    }
  ], List$Empty$const)));
}
function headers() {
  return new List2(record(prepend(["key", Type$String$const], prepend(["value", Type$String$const], List$Empty$const))));
}
function headers_to_gleam(value2) {
  return as_list_of(value2, (h) => {
    return try$(field2("key", as_string, h), (k) => {
      return try$(field2("value", as_string, h), (value3) => {
        return new Ok([k, value3]);
      });
    });
  });
}
function headers_to_eyg(headers2) {
  return new LinkedList(map2(headers2, (h) => {
    let k = h[0];
    let v = h[1];
    return new Record2(from_list(prepend(["key", new String4(k)], prepend(["value", new String4(v)], List$Empty$const))));
  }));
}
function request() {
  return record(prepend(["method", method()], prepend(["scheme", scheme()], prepend(["host", Type$String$const], prepend(["port", option(Type$Integer$const)], prepend(["path", Type$String$const], prepend(["query", option(Type$String$const)], prepend(["headers", headers()], prepend(["body", Type$Binary$const], List$Empty$const)))))))));
}
function request_to_gleam(request2) {
  return try$(field2("method", method_to_gleam, request2), (method2) => {
    return try$(field2("scheme", scheme_to_gleam, request2), (scheme2) => {
      return try$(field2("host", as_string, request2), (host) => {
        return try$(field2("port", (_capture) => {
          return as_option(_capture, as_integer);
        }, request2), (port) => {
          return try$(field2("path", as_string, request2), (path2) => {
            return try$(field2("query", (_capture) => {
              return as_option(_capture, as_string);
            }, request2), (query) => {
              return try$(field2("headers", headers_to_gleam, request2), (headers2) => {
                return try$(field2("body", as_binary, request2), (body) => {
                  return new Ok(new Request(method2, headers2, body, scheme2, host, port, path2, query));
                });
              });
            });
          });
        });
      });
    });
  });
}
function response() {
  return record(prepend(["status", Type$Integer$const], prepend(["headers", headers()], prepend(["body", Type$Binary$const], List$Empty$const))));
}
function response_to_eyg(response2) {
  let status = response2.status;
  let headers$1 = response2.headers;
  let body = response2.body;
  return new Record2(from_list(prepend(["status", new Integer3(status)], prepend(["headers", headers_to_eyg(headers$1)], prepend(["body", new Binary3(body)], List$Empty$const)))));
}

// build/dev/javascript/touch_grass/touch_grass/fetch.mjs
var label8 = "Fetch";
var decode12 = request_to_gleam;
function lift7() {
  return request();
}
function lower7() {
  return result(response(), Type$String$const);
}
function encode12(result2) {
  if (result2 instanceof Ok) {
    let response2 = result2[0];
    return ok(response_to_eyg(response2));
  } else {
    let reason = result2[0];
    return error(new String4(reason));
  }
}

// build/dev/javascript/touch_grass/touch_grass/file_system/append_file.mjs
class Input2 extends CustomType {
  constructor(path2, contents) {
    super();
    this.path = path2;
    this.contents = contents;
  }
}
var label9 = "AppendFile";
function lift8() {
  return record(prepend(["path", Type$String$const], prepend(["contents", Type$Binary$const], List$Empty$const)));
}
function lower8() {
  return result(unit, Type$String$const);
}
function decode13(input) {
  return try$(field2("path", as_string, input), (path2) => {
    return try$(field2("contents", as_binary, input), (contents) => {
      return new Ok(new Input2(path2, contents));
    });
  });
}
function encode13(result2) {
  if (result2 instanceof Ok) {
    return ok(unit2());
  } else {
    let reason = result2[0];
    return error(new String4(reason));
  }
}

// build/dev/javascript/touch_grass/touch_grass/file_system/cwd.mjs
var label10 = "CWD";
function lift9() {
  return unit;
}
function lower9() {
  return result(Type$String$const, unit);
}
function decode14(input) {
  return as_unit(input, undefined);
}
function encode14(result2) {
  if (result2 instanceof Ok) {
    let path2 = result2[0];
    return ok(new String4(path2));
  } else {
    let reason = result2[0];
    return error(new String4(reason));
  }
}

// build/dev/javascript/touch_grass/touch_grass/file_system/delete_file.mjs
var label11 = "DeleteFile";
function lift10() {
  return Type$String$const;
}
function lower10() {
  return result(unit, Type$String$const);
}
function decode15(input) {
  return as_string(input);
}
function encode15(result2) {
  if (result2 instanceof Ok) {
    return ok(unit2());
  } else {
    let reason = result2[0];
    return error(new String4(reason));
  }
}

// build/dev/javascript/touch_grass/touch_grass/file_system/make_directory.mjs
var label12 = "MakeDirectory";
var decode16 = as_string;
function lift11() {
  return Type$String$const;
}
function lower11() {
  return result(unit, Type$String$const);
}
function encode16(result2) {
  if (result2 instanceof Ok) {
    return ok(unit2());
  } else {
    let reason = result2[0];
    return error(new String4(reason));
  }
}

// build/dev/javascript/touch_grass/touch_grass/file_system/read_directory.mjs
class Directory2 extends CustomType {
}
var Entry$Directory$const = new Directory2;
class File2 extends CustomType {
  constructor(size2) {
    super();
    this.size = size2;
  }
}
var label13 = "ReadDirectory";
var decode17 = as_string;
function lift12() {
  return Type$String$const;
}
function entry() {
  return record(prepend(["name", Type$String$const], prepend([
    "type",
    union2(prepend(["Directory", unit], prepend([
      "File",
      record(prepend(["size", Type$Integer$const], List$Empty$const))
    ], List$Empty$const)))
  ], List$Empty$const)));
}
function lower12() {
  return result(new List2(entry()), Type$String$const);
}
function entry_encode(entry2) {
  let name = entry2[0];
  let entry$1 = entry2[1];
  let _block;
  if (entry$1 instanceof Directory2) {
    _block = new Tagged("Directory", unit2());
  } else {
    let size2 = entry$1.size;
    _block = new Tagged("File", new Record2(from_list(prepend(["size", new Integer3(size2)], List$Empty$const))));
  }
  let type_ = _block;
  return new Record2(from_list(prepend(["name", new String4(name)], prepend(["type", type_], List$Empty$const))));
}
function encode17(result2) {
  if (result2 instanceof Ok) {
    let entries = result2[0];
    return ok(new LinkedList(map2(entries, entry_encode)));
  } else {
    let reason = result2[0];
    return error(new String4(reason));
  }
}

// build/dev/javascript/touch_grass/touch_grass/file_system/read_file.mjs
class Input3 extends CustomType {
  constructor(path2, offset, limit) {
    super();
    this.path = path2;
    this.offset = offset;
    this.limit = limit;
  }
}
var label14 = "ReadFile";
function lift13() {
  return record(prepend(["path", Type$String$const], prepend(["offset", Type$Integer$const], prepend(["limit", Type$Integer$const], List$Empty$const))));
}
function lower13() {
  return result(Type$Binary$const, Type$String$const);
}
function decode18(input) {
  return try$(field2("path", as_string, input), (path2) => {
    return try$(field2("offset", as_integer, input), (offset) => {
      return try$(field2("limit", as_integer, input), (limit) => {
        return new Ok(new Input3(path2, offset, limit));
      });
    });
  });
}
function encode18(result2) {
  if (result2 instanceof Ok) {
    let data = result2[0];
    return ok(new Binary3(data));
  } else {
    let reason = result2[0];
    return error(new String4(reason));
  }
}

// build/dev/javascript/touch_grass/touch_grass/file_system/write_file.mjs
class Input4 extends CustomType {
  constructor(path2, contents) {
    super();
    this.path = path2;
    this.contents = contents;
  }
}
var label15 = "WriteFile";
function lift14() {
  return record(prepend(["path", Type$String$const], prepend(["contents", Type$Binary$const], List$Empty$const)));
}
function lower14() {
  return result(unit, Type$String$const);
}
function decode19(input) {
  return try$(field2("path", as_string, input), (path2) => {
    return try$(field2("contents", as_binary, input), (contents) => {
      return new Ok(new Input4(path2, contents));
    });
  });
}
function encode19(result2) {
  if (result2 instanceof Ok) {
    return ok(unit2());
  } else {
    let reason = result2[0];
    return error(new String4(reason));
  }
}

// build/dev/javascript/touch_grass/touch_grass/flip.mjs
var label16 = "Flip";
function lift15() {
  return unit;
}
function lower15() {
  return boolean;
}
function decode20(input) {
  return as_unit(input, undefined);
}
function encode20(value2) {
  return bool2(value2);
}

// build/dev/javascript/touch_grass/touch_grass/exit.mjs
var label17 = "Exit";
var decode21 = as_integer;
function lift16() {
  return Type$Integer$const;
}
function lower16() {
  return Type$Never$const;
}

// build/dev/javascript/touch_grass/touch_grass/interface.mjs
class Interface extends CustomType {
  constructor(name, lift_type, lower_type, decode22) {
    super();
    this.name = name;
    this.lift_type = lift_type;
    this.lower_type = lower_type;
    this.decode = decode22;
  }
}
function cast(effects, label18, input) {
  let $ = find(effects, (i) => {
    return i.name === label18;
  });
  if ($ instanceof Ok) {
    let decode22 = $[0].decode;
    return decode22(input);
  } else {
    return new Error2(new UnhandledEffect(label18, input));
  }
}

// build/dev/javascript/touch_grass/touch_grass/now.mjs
var label18 = "Now";
function lift17() {
  return unit;
}
function lower17() {
  return Type$Integer$const;
}
function decode22(input) {
  return as_unit(input, undefined);
}
function encode21(millis) {
  return new Integer3(millis);
}

// build/dev/javascript/touch_grass/touch_grass/random.mjs
var label19 = "Random";
function lift18() {
  return Type$Integer$const;
}
function lower18() {
  return Type$Integer$const;
}
function decode23(lift19) {
  return as_integer(lift19);
}
function encode22(number) {
  return new Integer3(number);
}

// build/dev/javascript/touch_grass/touch_grass/sleep.mjs
var label20 = "Sleep";
function lift19() {
  return Type$Integer$const;
}
function lower19() {
  return unit;
}
function decode24(input) {
  return as_integer(input);
}
function encode23(_) {
  return unit2();
}

// build/dev/javascript/touch_grass/touch_grass/standard_error.mjs
var label21 = "StandardError";
var decode25 = as_string;
function lift20() {
  return Type$String$const;
}
function lower20() {
  return unit;
}
function encode24(_) {
  return unit2();
}

// build/dev/javascript/touch_grass/touch_grass/standard_in.mjs
var label22 = "StandardIn";
function lift21() {
  return unit;
}
function lower21() {
  return result(Type$Binary$const, Type$String$const);
}
function decode26(input) {
  return as_unit(input, undefined);
}
function encode25(result2) {
  if (result2 instanceof Ok) {
    let bytes = result2[0];
    return ok(new Binary3(bytes));
  } else {
    let reason = result2[0];
    return error(new String4(reason));
  }
}

// build/dev/javascript/touch_grass/touch_grass/standard_out.mjs
var label23 = "StandardOut";
var decode27 = as_string;
function lift22() {
  return Type$String$const;
}
function lower22() {
  return unit;
}
function encode26(_) {
  return unit2();
}

// build/dev/javascript/touch_grass/touch_grass.mjs
function append_file() {
  return new Interface(label9, lift8(), lower8(), decode13);
}
function create_key() {
  return new Interface(label2, lift(), lower(), decode6);
}
function cwd() {
  return new Interface(label10, lift9(), lower9(), decode14);
}
function decode_json() {
  return new Interface(label5, lift4(), lower4(), decode9);
}
function delete_file() {
  return new Interface(label11, lift10(), lower10(), decode15);
}
function env() {
  return new Interface(label6, lift5(), lower5(), decode10);
}
function exit() {
  return new Interface(label17, lift16(), lower16(), decode21);
}
function eyg_parse() {
  return new Interface(label7, lift6(), lower6(), decode11);
}
function fetch3() {
  return new Interface(label8, lift7(), lower7(), decode12);
}
function flip() {
  return new Interface(label16, lift15(), lower15(), decode20);
}
function hash() {
  return new Interface(label3, lift2(), lower2(), decode7);
}
function make_directory() {
  return new Interface(label12, lift11(), lower11(), decode16);
}
function now() {
  return new Interface(label18, lift17(), lower17(), decode22);
}
function random3() {
  return new Interface(label19, lift18(), lower18(), decode23);
}
function read_directory() {
  return new Interface(label13, lift12(), lower12(), decode17);
}
function read_file() {
  return new Interface(label14, lift13(), lower13(), decode18);
}
function sign() {
  return new Interface(label4, lift3(), lower3(), decode8);
}
function sleep() {
  return new Interface(label20, lift19(), lower19(), decode24);
}
function standard_error() {
  return new Interface(label21, lift20(), lower20(), decode25);
}
function standard_in() {
  return new Interface(label22, lift21(), lower21(), decode26);
}
function standard_out() {
  return new Interface(label23, lift22(), lower22(), decode27);
}
function write_file() {
  return new Interface(label15, lift14(), lower14(), decode19);
}
function map9(interface$, f) {
  let decode35 = interface$.decode;
  let decode$1 = map5(decode35, f);
  return new Interface(interface$.name, interface$.lift_type, interface$.lower_type, decode$1);
}
function replace3(interface$, value2) {
  let decode35 = interface$.decode;
  let decode$1 = map5(decode35, (_) => {
    return value2;
  });
  return new Interface(interface$.name, interface$.lift_type, interface$.lower_type, decode$1);
}

// build/dev/javascript/touch_grass/touch_grass/harness/computer.mjs
class AppendFile extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class CreateKey extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Cwd extends CustomType {
}
var Effect$Cwd$const = new Cwd;
class DecodeJson extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class DeleteFile extends CustomType {
  constructor(path2) {
    super();
    this.path = path2;
  }
}
class Env2 extends CustomType {
  constructor(name) {
    super();
    this.name = name;
  }
}
class Exit extends CustomType {
  constructor(status) {
    super();
    this.status = status;
  }
}
class EygParse extends CustomType {
  constructor(source) {
    super();
    this.source = source;
  }
}
class Fetch extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Flip extends CustomType {
}
var Effect$Flip$const = new Flip;
class Hash extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class MakeDirectory extends CustomType {
  constructor(path2) {
    super();
    this.path = path2;
  }
}
class Now extends CustomType {
}
var Effect$Now$const = new Now;
class Random extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class ReadDirectory extends CustomType {
  constructor(path2) {
    super();
    this.path = path2;
  }
}
class ReadFile extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Sign extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Sleep extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class StandardError extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class StandardIn extends CustomType {
}
var Effect$StandardIn$const = new StandardIn;
class StanardOut extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class WriteFile extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
function effects() {
  return toList([
    (() => {
      let _pipe = append_file();
      return map9(_pipe, (var0) => {
        return new AppendFile(var0);
      });
    })(),
    (() => {
      let _pipe = create_key();
      return map9(_pipe, (var0) => {
        return new CreateKey(var0);
      });
    })(),
    (() => {
      let _pipe = cwd();
      return replace3(_pipe, Effect$Cwd$const);
    })(),
    (() => {
      let _pipe = decode_json();
      return map9(_pipe, (var0) => {
        return new DecodeJson(var0);
      });
    })(),
    (() => {
      let _pipe = delete_file();
      return map9(_pipe, (var0) => {
        return new DeleteFile(var0);
      });
    })(),
    (() => {
      let _pipe = env();
      return map9(_pipe, (var0) => {
        return new Env2(var0);
      });
    })(),
    (() => {
      let _pipe = exit();
      return map9(_pipe, (var0) => {
        return new Exit(var0);
      });
    })(),
    (() => {
      let _pipe = eyg_parse();
      return map9(_pipe, (var0) => {
        return new EygParse(var0);
      });
    })(),
    (() => {
      let _pipe = fetch3();
      return map9(_pipe, (var0) => {
        return new Fetch(var0);
      });
    })(),
    (() => {
      let _pipe = flip();
      return replace3(_pipe, Effect$Flip$const);
    })(),
    (() => {
      let _pipe = hash();
      return map9(_pipe, (var0) => {
        return new Hash(var0);
      });
    })(),
    (() => {
      let _pipe = make_directory();
      return map9(_pipe, (var0) => {
        return new MakeDirectory(var0);
      });
    })(),
    (() => {
      let _pipe = now();
      return replace3(_pipe, Effect$Now$const);
    })(),
    (() => {
      let _pipe = random3();
      return map9(_pipe, (var0) => {
        return new Random(var0);
      });
    })(),
    (() => {
      let _pipe = read_directory();
      return map9(_pipe, (var0) => {
        return new ReadDirectory(var0);
      });
    })(),
    (() => {
      let _pipe = read_file();
      return map9(_pipe, (var0) => {
        return new ReadFile(var0);
      });
    })(),
    (() => {
      let _pipe = sign();
      return map9(_pipe, (var0) => {
        return new Sign(var0);
      });
    })(),
    (() => {
      let _pipe = sleep();
      return map9(_pipe, (var0) => {
        return new Sleep(var0);
      });
    })(),
    (() => {
      let _pipe = standard_error();
      return map9(_pipe, (var0) => {
        return new StandardError(var0);
      });
    })(),
    (() => {
      let _pipe = standard_in();
      return replace3(_pipe, Effect$StandardIn$const);
    })(),
    (() => {
      let _pipe = standard_out();
      return map9(_pipe, (var0) => {
        return new StanardOut(var0);
      });
    })(),
    (() => {
      let _pipe = write_file();
      return map9(_pipe, (var0) => {
        return new WriteFile(var0);
      });
    })()
  ]);
}

// build/dev/javascript/eyg_parser/eyg/parser/token.mjs
class Comment extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Whitespace extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Name extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Uppername extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Integer5 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class String6 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Let2 extends CustomType {
}
var Token$Let$const = new Let2;
class Match2 extends CustomType {
}
var Token$Match$const = new Match2;
class Perform3 extends CustomType {
}
var Token$Perform$const = new Perform3;
class Deep extends CustomType {
}
var Token$Deep$const = new Deep;
class Handle3 extends CustomType {
}
var Token$Handle$const = new Handle3;
class Import extends CustomType {
}
var Token$Import$const = new Import;
class Equal extends CustomType {
}
var Token$Equal$const = new Equal;
class Comma extends CustomType {
}
var Token$Comma$const = new Comma;
class DotDot extends CustomType {
}
var Token$DotDot$const = new DotDot;
class Dot extends CustomType {
}
var Token$Dot$const = new Dot;
class Colon extends CustomType {
}
var Token$Colon$const = new Colon;
class RightArrow extends CustomType {
}
var Token$RightArrow$const = new RightArrow;
class Minus extends CustomType {
}
var Token$Minus$const = new Minus;
class Bang extends CustomType {
}
var Token$Bang$const = new Bang;
class Bar extends CustomType {
}
var Token$Bar$const = new Bar;
class Hash2 extends CustomType {
}
var Token$Hash$const = new Hash2;
class At extends CustomType {
}
var Token$At$const = new At;
class LeftParen extends CustomType {
}
var Token$LeftParen$const = new LeftParen;
class RightParen extends CustomType {
}
var Token$RightParen$const = new RightParen;
class LeftBrace extends CustomType {
}
var Token$LeftBrace$const = new LeftBrace;
class RightBrace extends CustomType {
}
var Token$RightBrace$const = new RightBrace;
class LeftSquare extends CustomType {
}
var Token$LeftSquare$const = new LeftSquare;
class RightSquare extends CustomType {
}
var Token$RightSquare$const = new RightSquare;
class UnexpectedGrapheme extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class UnterminatedString extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class InvalidEscape extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
function drop_whitespace(tokens) {
  return filter(tokens, (token2) => {
    if (token2[0] instanceof Whitespace) {
      return false;
    } else {
      return true;
    }
  });
}
function drop_comments(tokens) {
  return filter(tokens, (token2) => {
    if (token2[0] instanceof Comment) {
      return false;
    } else {
      return true;
    }
  });
}
function to_string8(token2) {
  if (token2 instanceof Comment) {
    let content = token2[0];
    return "//" + content;
  } else if (token2 instanceof Whitespace) {
    let raw = token2[0];
    return raw;
  } else if (token2 instanceof Name) {
    let raw = token2[0];
    return raw;
  } else if (token2 instanceof Uppername) {
    let raw = token2[0];
    return raw;
  } else if (token2 instanceof Integer5) {
    let raw = token2[0];
    return raw;
  } else if (token2 instanceof String6) {
    let raw = token2[0];
    return '"' + raw + '"';
  } else if (token2 instanceof Let2) {
    return "let";
  } else if (token2 instanceof Match2) {
    return "match";
  } else if (token2 instanceof Perform3) {
    return "perform";
  } else if (token2 instanceof Deep) {
    return "deep";
  } else if (token2 instanceof Handle3) {
    return "handle";
  } else if (token2 instanceof Import) {
    return "import";
  } else if (token2 instanceof Equal) {
    return "=";
  } else if (token2 instanceof Comma) {
    return ",";
  } else if (token2 instanceof DotDot) {
    return "..";
  } else if (token2 instanceof Dot) {
    return ".";
  } else if (token2 instanceof Colon) {
    return ":";
  } else if (token2 instanceof RightArrow) {
    return "->";
  } else if (token2 instanceof Minus) {
    return "-";
  } else if (token2 instanceof Bang) {
    return "!";
  } else if (token2 instanceof Bar) {
    return "|";
  } else if (token2 instanceof Hash2) {
    return "#";
  } else if (token2 instanceof At) {
    return "@";
  } else if (token2 instanceof LeftParen) {
    return "(";
  } else if (token2 instanceof RightParen) {
    return ")";
  } else if (token2 instanceof LeftBrace) {
    return "{";
  } else if (token2 instanceof RightBrace) {
    return "}";
  } else if (token2 instanceof LeftSquare) {
    return "[";
  } else if (token2 instanceof RightSquare) {
    return "]";
  } else if (token2 instanceof UnexpectedGrapheme) {
    let raw = token2[0];
    return raw;
  } else if (token2 instanceof UnterminatedString) {
    let raw = token2[0];
    return '"' + raw;
  } else {
    let raw = token2[0];
    return '"' + raw;
  }
}

// build/dev/javascript/eyg_parser/eyg/parser/parser.mjs
var FILEPATH11 = "src/eyg/parser/parser.gleam";

class UnexpectEnd extends CustomType {
}
var Reason$UnexpectEnd$const = new UnexpectEnd;
class UnexpectedToken2 extends CustomType {
  constructor(token2, position) {
    super();
    this.token = token2;
    this.position = position;
  }
}
class MissingEquals extends CustomType {
  constructor(position) {
    super();
    this.position = position;
  }
}
class MissingArrow extends CustomType {
  constructor(position) {
    super();
    this.position = position;
  }
}
class UnclosedFunctionBody extends CustomType {
  constructor(open_at) {
    super();
    this.open_at = open_at;
  }
}
class ExpectedEffectName extends CustomType {
  constructor(keyword, position) {
    super();
    this.keyword = keyword;
    this.position = position;
  }
}
class ExpectedBuiltinName extends CustomType {
  constructor(position) {
    super();
    this.position = position;
  }
}
class InvalidCidReference extends CustomType {
  constructor(position) {
    super();
    this.position = position;
  }
}
class InvalidReleaseVersion extends CustomType {
  constructor(position) {
    super();
    this.position = position;
  }
}
class InvalidImportPath extends CustomType {
  constructor(position) {
    super();
    this.position = position;
  }
}
class TrailingTokens extends CustomType {
  constructor(token2, position) {
    super();
    this.token = token2;
    this.position = position;
  }
}
class InvalidCharacter extends CustomType {
  constructor(char2, position) {
    super();
    this.char = char2;
    this.position = position;
  }
}
class UnterminatedStringLiteral extends CustomType {
  constructor(position) {
    super();
    this.position = position;
  }
}
class InvalidEscapeSequence extends CustomType {
  constructor(escape_char, position) {
    super();
    this.escape_char = escape_char;
    this.position = position;
  }
}
class IntegerLiteralOutOfRange extends CustomType {
  constructor(raw, position) {
    super();
    this.raw = raw;
    this.position = position;
  }
}
class Assign2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Destructure extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
function fail(tokens) {
  if (tokens instanceof Empty) {
    return new Error2(Reason$UnexpectEnd$const);
  } else {
    let t = tokens.head[0];
    let start = tokens.head[1];
    return new Error2(new UnexpectedToken2(t, start));
  }
}
function do_destructure(loop$tokens, loop$acc) {
  while (true) {
    let tokens = loop$tokens;
    let acc = loop$acc;
    if (tokens instanceof Empty) {
      return fail(tokens);
    } else {
      let $ = tokens.head[0];
      if ($ instanceof Name) {
        let $1 = tokens.tail;
        if ($1 instanceof Empty) {
          let rest = $1;
          let start = tokens.head[1];
          let field3 = $[0];
          let field$1 = [field3, [start, start + string_length(field3)]];
          let acc$1 = prepend([field$1, Option$None$const], acc);
          if (rest instanceof Empty) {
            return fail(rest);
          } else {
            let $2 = rest.head[0];
            if ($2 instanceof Comma) {
              let rest$1 = rest.tail;
              loop$tokens = rest$1;
              loop$acc = acc$1;
            } else if ($2 instanceof RightBrace) {
              let rest$1 = rest.tail;
              return new Ok([acc$1, rest$1]);
            } else {
              return fail(rest);
            }
          }
        } else {
          let $2 = $1.tail;
          if ($2 instanceof Empty) {
            let rest = $1;
            let start = tokens.head[1];
            let field3 = $[0];
            let field$1 = [field3, [start, start + string_length(field3)]];
            let acc$1 = prepend([field$1, Option$None$const], acc);
            if (rest instanceof Empty) {
              return fail(rest);
            } else {
              let $3 = rest.head[0];
              if ($3 instanceof Comma) {
                let rest$1 = rest.tail;
                loop$tokens = rest$1;
                loop$acc = acc$1;
              } else if ($3 instanceof RightBrace) {
                let rest$1 = rest.tail;
                return new Ok([acc$1, rest$1]);
              } else {
                return fail(rest);
              }
            }
          } else if ($1.head[0] instanceof Colon) {
            let $3 = $2.head[0];
            if ($3 instanceof Name) {
              let f = tokens.head[1];
              let field3 = $[0];
              let c = $1.head[1];
              let rest = $2.tail;
              let v = $2.head[1];
              let var$ = $3[0];
              let field$1 = [field3, [f, f + string_length(field3)]];
              let colon = [c, c + 1];
              let var$1 = [var$, [v, v + string_length(var$)]];
              let acc$1 = prepend([field$1, new Some([colon, var$1])], acc);
              if (rest instanceof Empty) {
                return fail(rest);
              } else {
                let $4 = rest.head[0];
                if ($4 instanceof Comma) {
                  let rest$1 = rest.tail;
                  loop$tokens = rest$1;
                  loop$acc = acc$1;
                } else if ($4 instanceof RightBrace) {
                  let rest$1 = rest.tail;
                  return new Ok([acc$1, rest$1]);
                } else {
                  return fail(rest);
                }
              }
            } else {
              let rest = $1;
              let start = tokens.head[1];
              let field3 = $[0];
              let field$1 = [field3, [start, start + string_length(field3)]];
              let acc$1 = prepend([field$1, Option$None$const], acc);
              if (rest instanceof Empty) {
                return fail(rest);
              } else {
                let $4 = rest.head[0];
                if ($4 instanceof Comma) {
                  let rest$1 = rest.tail;
                  loop$tokens = rest$1;
                  loop$acc = acc$1;
                } else if ($4 instanceof RightBrace) {
                  let rest$1 = rest.tail;
                  return new Ok([acc$1, rest$1]);
                } else {
                  return fail(rest);
                }
              }
            }
          } else {
            let rest = $1;
            let start = tokens.head[1];
            let field3 = $[0];
            let field$1 = [field3, [start, start + string_length(field3)]];
            let acc$1 = prepend([field$1, Option$None$const], acc);
            if (rest instanceof Empty) {
              return fail(rest);
            } else {
              let $3 = rest.head[0];
              if ($3 instanceof Comma) {
                let rest$1 = rest.tail;
                loop$tokens = rest$1;
                loop$acc = acc$1;
              } else if ($3 instanceof RightBrace) {
                let rest$1 = rest.tail;
                return new Ok([acc$1, rest$1]);
              } else {
                return fail(rest);
              }
            }
          }
        }
      } else if ($ instanceof RightBrace) {
        let rest = tokens.tail;
        return new Ok([acc, rest]);
      } else {
        return fail(tokens);
      }
    }
  }
}
function one_pattern(tokens) {
  if (tokens instanceof Empty) {
    return fail(tokens);
  } else {
    let $ = tokens.head[0];
    if ($ instanceof Name) {
      let rest = tokens.tail;
      let label31 = $[0];
      return new Ok([new Assign2(label31), rest]);
    } else if ($ instanceof LeftBrace) {
      let rest = tokens.tail;
      return try$(do_destructure(rest, List$Empty$const), (_use0) => {
        let matches = _use0[0];
        let rest$1 = _use0[1];
        return new Ok([new Destructure(matches), rest$1]);
      });
    } else {
      return fail(tokens);
    }
  }
}
function pop(tokens) {
  if (tokens instanceof Empty) {
    return new Error2(Reason$UnexpectEnd$const);
  } else {
    let t = tokens.head;
    let rest = tokens.tail;
    return new Ok([t, rest]);
  }
}
function do_patterns(tokens, acc) {
  return try$(one_pattern(tokens), (_use0) => {
    let pattern = _use0[0];
    let tokens$1 = _use0[1];
    let acc$1 = prepend(pattern, acc);
    return try$(pop(tokens$1), (_use02) => {
      let next;
      let start;
      let rest;
      rest = _use02[1];
      next = _use02[0][0];
      start = _use02[0][1];
      if (next instanceof Comma) {
        return do_patterns(rest, acc$1);
      } else if (next instanceof RightParen) {
        return new Ok([acc$1, rest]);
      } else {
        return new Error2(new UnexpectedToken2(next, start));
      }
    });
  });
}
function destructured(matches, term) {
  return fold2(matches, term, (acc, pair) => {
    let field3 = pair[0];
    let assign = pair[1];
    let field$1 = field3[0];
    let fspan = field3[1];
    let _block;
    if (assign instanceof Some) {
      let cspan2 = assign[0][0];
      let var$2 = assign[0][1][0];
      let vspan = assign[0][1][1];
      _block = [cspan2, [var$2, vspan]];
    } else {
      _block = [fspan, [field$1, fspan]];
    }
    let $ = _block;
    let cspan;
    let var$;
    cspan = $[0];
    var$ = $[1][0];
    let aspan = [fspan[0], cspan[1]];
    let lspan = [fspan[0], term[1][1]];
    return [
      new Let(var$, [
        new Apply([new Select(field$1), fspan], [new Variable("$"), cspan]),
        aspan
      ], acc),
      lspan
    ];
  });
}
function next_pos(rest, fallback) {
  if (rest instanceof Empty) {
    return fallback;
  } else {
    let at = rest.head[1];
    return at;
  }
}
function build_overwrite(loop$reversed, loop$acc) {
  while (true) {
    let reversed = loop$reversed;
    let acc = loop$acc;
    if (reversed instanceof Empty) {
      return acc;
    } else {
      let rest = reversed.tail;
      let span = reversed.head[0];
      let label31 = reversed.head[1];
      let item = reversed.head[2];
      let c;
      c = acc[1][1];
      let b;
      b = item[1][1];
      let a = span[0];
      loop$reversed = rest;
      loop$acc = [
        new Apply([new Apply([new Overwrite(label31), span], item), [a, b]], acc),
        [a, c]
      ];
    }
  }
}
function build_record(loop$reversed, loop$acc) {
  while (true) {
    let reversed = loop$reversed;
    let acc = loop$acc;
    if (reversed instanceof Empty) {
      return acc;
    } else {
      let rest = reversed.tail;
      let span = reversed.head[0];
      let label31 = reversed.head[1];
      let item = reversed.head[2];
      let c;
      c = acc[1][1];
      let b;
      b = item[1][1];
      let a = span[0];
      loop$reversed = rest;
      loop$acc = [
        new Apply([new Apply([new Extend(label31), span], item), [a, b]], acc),
        [a, c]
      ];
    }
  }
}
function build_list(loop$reversed, loop$acc) {
  while (true) {
    let reversed = loop$reversed;
    let acc = loop$acc;
    if (reversed instanceof Empty) {
      return acc;
    } else {
      let rest = reversed.tail;
      let from3 = reversed.head[0];
      let item = reversed.head[1];
      let c;
      c = acc[1][1];
      let b;
      b = item[1][1];
      loop$reversed = rest;
      loop$acc = [
        new Apply([
          new Apply([Expression$Cons$const, [from3, from3 + 1]], item),
          [from3, b]
        ], acc),
        [from3, c]
      ];
    }
  }
}
function in_range(value2, raw, position) {
  let $ = isSafeInteger(value2);
  if ($) {
    return new Ok(value2);
  } else {
    return new Error2(new IntegerLiteralOutOfRange(raw, position));
  }
}
function do_args(tokens, acc) {
  if (tokens instanceof Empty) {
    return fail(tokens);
  } else {
    let $ = tokens.head[0];
    if ($ instanceof Comma) {
      let rest = tokens.tail;
      return try$(expression(rest), (_use0) => {
        let arg = _use0[0];
        let rest$1 = _use0[1];
        return do_args(rest$1, prepend(arg, acc));
      });
    } else if ($ instanceof RightParen) {
      let rest = tokens.tail;
      let end = tokens.head[1];
      return new Ok([acc, end + 1, rest]);
    } else {
      return fail(tokens);
    }
  }
}
function after_expression(loop$exp, loop$rest) {
  while (true) {
    let exp2 = loop$exp;
    let rest = loop$rest;
    if (rest instanceof Empty) {
      return new Ok([exp2, rest]);
    } else {
      let $ = rest.head[0];
      if ($ instanceof Dot) {
        let $1 = rest.tail;
        if ($1 instanceof Empty) {
          return new Ok([exp2, rest]);
        } else {
          let $2 = $1.head[0];
          if ($2 instanceof Name) {
            let dot_at = rest.head[1];
            let rest$1 = $1.tail;
            let name_at = $1.head[1];
            let label31 = $2[0];
            let end = name_at + string_length(label31);
            let select2 = [new Select(label31), [dot_at, end]];
            let start;
            start = exp2[1][0];
            let span = [start, end];
            loop$exp = [new Apply(select2, exp2), span];
            loop$rest = rest$1;
          } else {
            return new Ok([exp2, rest]);
          }
        }
      } else if ($ instanceof LeftParen) {
        let rest$1 = rest.tail;
        return try$(expression(rest$1), (_use0) => {
          let arg = _use0[0];
          let rest$2 = _use0[1];
          return try$(do_args(rest$2, prepend(arg, List$Empty$const)), (_use02) => {
            let args = _use02[0];
            let rest$3 = _use02[2];
            let args$1 = reverse(args);
            let exp$1 = fold2(args$1, exp2, (acc, arg2) => {
              let start;
              start = acc[1][0];
              let end;
              end = arg2[1][1];
              return [new Apply(acc, arg2), [start, end + 1]];
            });
            return after_expression(exp$1, rest$3);
          });
        });
      } else {
        return new Ok([exp2, rest]);
      }
    }
  }
}
function do_clauses(tokens, start, acc) {
  return try$(pop(tokens), (_use0) => {
    let token2;
    let clause;
    let rest;
    rest = _use0[1];
    token2 = _use0[0][0];
    clause = _use0[0][1];
    if (token2 instanceof Uppername) {
      let label31 = token2[0];
      return try$(expression(rest), (_use02) => {
        let branch = _use02[0];
        let rest$1 = _use02[1];
        let acc$1 = prepend([start, label31, [clause, clause + string_length(label31)], branch], acc);
        if (rest$1 instanceof Empty) {
          return new Error2(Reason$UnexpectEnd$const);
        } else {
          let last2 = rest$1.head[1];
          return do_clauses(rest$1, last2, acc$1);
        }
      });
    } else if (token2 instanceof Bar) {
      return try$(expression(rest), (_use02) => {
        let otherwise;
        let span;
        let rest$1;
        rest$1 = _use02[1];
        otherwise = _use02[0][0];
        span = _use02[0][1];
        if (rest$1 instanceof Empty) {
          return fail(rest$1);
        } else if (rest$1.head[0] instanceof RightBrace) {
          let rest$2 = rest$1.tail;
          return new Ok([acc, [otherwise, span], rest$2]);
        } else {
          return fail(rest$1);
        }
      });
    } else if (token2 instanceof RightBrace) {
      return new Ok([acc, [Expression$NoCases$const, [start, clause + 1]], rest]);
    } else {
      return new Error2(new UnexpectedToken2(token2, clause));
    }
  });
}
function clauses(tokens, start) {
  return try$(do_clauses(tokens, start, List$Empty$const), (_use0) => {
    let clauses$1 = _use0[0];
    let tail = _use0[1];
    let rest = _use0[2];
    let end;
    end = tail[1][1];
    let exp2 = fold2(clauses$1, tail, (exp3, clause) => {
      let start$1 = clause[0];
      let label31 = clause[1];
      let cspan = clause[2];
      let branch = clause[3];
      let case_2 = [new Case(label31), cspan];
      let branch_end;
      branch_end = branch[1][1];
      let inner = [new Apply(case_2, branch), [cspan[0], branch_end]];
      let final;
      final = tail[1][1];
      return [new Apply(inner, exp3), [start$1, final]];
    });
    return new Ok([exp2, end, rest]);
  });
}
function do_record(rest, start, acc) {
  return try$(pop(rest), (_use0) => {
    let token2;
    let kstart;
    let rest$1;
    rest$1 = _use0[1];
    token2 = _use0[0][0];
    kstart = _use0[0][1];
    if (token2 instanceof Name) {
      let label31 = token2[0];
      return try$(pop(rest$1), (_use02) => {
        let token$1;
        let next;
        let rest$2;
        rest$2 = _use02[1];
        token$1 = _use02[0][0];
        next = _use02[0][1];
        if (token$1 instanceof Comma) {
          let acc$1 = prepend([
            [start, kstart + string_length(label31)],
            label31,
            [
              new Variable(label31),
              [kstart, kstart + string_length(label31)]
            ]
          ], acc);
          return do_record(rest$2, next, acc$1);
        } else if (token$1 instanceof Colon) {
          return try$(expression(rest$2), (_use03) => {
            let value2 = _use03[0];
            let rest$3 = _use03[1];
            let acc$1 = prepend([[start, next + 1], label31, value2], acc);
            if (rest$3 instanceof Empty) {
              return fail(rest$3);
            } else {
              let $ = rest$3.head[0];
              if ($ instanceof Comma) {
                let rest$4 = rest$3.tail;
                let start$1 = rest$3.head[1];
                return do_record(rest$4, start$1, acc$1);
              } else if ($ instanceof RightBrace) {
                let rest$4 = rest$3.tail;
                let start$1 = rest$3.head[1];
                let span = [start$1, start$1 + 1];
                return new Ok([
                  build_record(acc$1, [Expression$Empty$const, span]),
                  rest$4
                ]);
              } else {
                return fail(rest$3);
              }
            }
          });
        } else if (token$1 instanceof RightBrace) {
          let acc$1 = prepend([
            [start, kstart + string_length(label31)],
            label31,
            [
              new Variable(label31),
              [kstart, kstart + string_length(label31)]
            ]
          ], acc);
          let span = [next, next + 1];
          return new Ok([
            build_record(acc$1, [Expression$Empty$const, span]),
            rest$2
          ]);
        } else {
          return new Error2(new UnexpectedToken2(token$1, start));
        }
      });
    } else if (token2 instanceof DotDot) {
      return try$(expression(rest$1), (_use02) => {
        let value2 = _use02[0];
        let rest$2 = _use02[1];
        return try$(pop(rest$2), (_use03) => {
          let token$1;
          let start$1;
          let rest$3;
          rest$3 = _use03[1];
          token$1 = _use03[0][0];
          start$1 = _use03[0][1];
          return try$((() => {
            if (token$1 instanceof RightBrace) {
              return new Ok(rest$3);
            } else {
              return new Error2(new UnexpectedToken2(token$1, start$1));
            }
          })(), (rest2) => {
            return new Ok([build_overwrite(acc, value2), rest2]);
          });
        });
      });
    } else if (token2 instanceof RightBrace) {
      if (acc instanceof Empty) {
        return new Ok([[Expression$Empty$const, [start, kstart + 1]], rest$1]);
      } else {
        let span = [kstart, kstart + 1];
        return new Ok([build_record(acc, [Expression$Empty$const, span]), rest$1]);
      }
    } else {
      return new Error2(new UnexpectedToken2(token2, start));
    }
  });
}
function do_list(tokens, start, acc) {
  if (tokens instanceof Empty) {
    return new Error2(Reason$UnexpectEnd$const);
  } else if (tokens.head[0] instanceof RightSquare) {
    let rest = tokens.tail;
    let end = tokens.head[1];
    let span = [start, end + 1];
    return new Ok([build_list(acc, [Expression$Tail$const, span]), rest]);
  } else {
    return try$(expression(tokens), (_use0) => {
      let item = _use0[0];
      let rest = _use0[1];
      let acc$1 = prepend([start, item], acc);
      if (rest instanceof Empty) {
        return new Error2(Reason$UnexpectEnd$const);
      } else {
        let $ = rest.tail;
        if ($ instanceof Empty) {
          let $1 = rest.head[0];
          if ($1 instanceof Comma) {
            let rest$1 = $;
            let start$1 = rest.head[1];
            return do_list(rest$1, start$1, acc$1);
          } else if ($1 instanceof RightSquare) {
            let rest$1 = $;
            let start$1 = rest.head[1];
            let span = [start$1, start$1 + 1];
            return new Ok([build_list(acc$1, [Expression$Tail$const, span]), rest$1]);
          } else {
            let t = $1;
            let start$1 = rest.head[1];
            return new Error2(new UnexpectedToken2(t, start$1));
          }
        } else {
          let $1 = rest.head[0];
          if ($1 instanceof Comma) {
            if ($.head[0] instanceof DotDot) {
              let rest$1 = $.tail;
              return try$(expression(rest$1), (_use02) => {
                let tail = _use02[0];
                let rest$2 = _use02[1];
                return try$(pop(rest$2), (_use03) => {
                  let token2;
                  let start$1;
                  let rest$3;
                  rest$3 = _use03[1];
                  token2 = _use03[0][0];
                  start$1 = _use03[0][1];
                  if (token2 instanceof RightSquare) {
                    return new Ok([build_list(acc$1, tail), rest$3]);
                  } else {
                    return new Error2(new UnexpectedToken2(token2, start$1));
                  }
                });
              });
            } else {
              let rest$1 = $;
              let start$1 = rest.head[1];
              return do_list(rest$1, start$1, acc$1);
            }
          } else if ($1 instanceof RightSquare) {
            let rest$1 = $;
            let start$1 = rest.head[1];
            let span = [start$1, start$1 + 1];
            return new Ok([build_list(acc$1, [Expression$Tail$const, span]), rest$1]);
          } else {
            let t = $1;
            let start$1 = rest.head[1];
            return new Error2(new UnexpectedToken2(t, start$1));
          }
        }
      }
    });
  }
}
function expression(tokens) {
  return try$(pop(tokens), (_use0) => {
    let token2;
    let start;
    let rest;
    rest = _use0[1];
    token2 = _use0[0][0];
    start = _use0[0][1];
    return try$((() => {
      if (token2 instanceof Name) {
        let label31 = token2[0];
        let span = [start, start + string_length(label31)];
        return new Ok([[new Variable(label31), span], rest]);
      } else if (token2 instanceof Uppername) {
        let label31 = token2[0];
        let span = [start, start + string_length(label31)];
        return new Ok([[new Tag(label31), span], rest]);
      } else if (token2 instanceof Integer5) {
        let raw = token2[0];
        let $ = parse_int(raw);
        let value2;
        if ($ instanceof Ok) {
          value2 = $[0];
        } else {
          throw makeError("let_assert", FILEPATH11, "eyg/parser/parser", 232, "expression", "Pattern match failed, no pattern matched the value.", {
            value: $,
            start: 7489,
            end: 7526,
            pattern_start: 7500,
            pattern_end: 7509
          });
        }
        return try$(in_range(value2, raw, start), (value3) => {
          let span = [start, start + string_length(raw)];
          return new Ok([[new Integer(value3), span], rest]);
        });
      } else if (token2 instanceof String6) {
        let value2 = token2[0];
        let span = [start, start + string_length(value2) + 2];
        return new Ok([[new String2(value2), span], rest]);
      } else if (token2 instanceof Let2) {
        return try$(one_pattern(rest), (_use02) => {
          let pattern = _use02[0];
          let rest$1 = _use02[1];
          return try$((() => {
            if (rest$1 instanceof Empty) {
              return new Error2(Reason$UnexpectEnd$const);
            } else if (rest$1.head[0] instanceof Equal) {
              let rest$2 = rest$1.tail;
              return new Ok(rest$2);
            } else {
              let at = rest$1.head[1];
              return new Error2(new MissingEquals(at));
            }
          })(), (rest2) => {
            return try$(expression(rest2), (_use03) => {
              let value2 = _use03[0];
              let rest$2 = _use03[1];
              return try$(expression(rest$2), (_use04) => {
                let then$3 = _use04[0];
                let rest$3 = _use04[1];
                let end;
                end = then$3[1][1];
                let span = [start, end];
                let _block;
                if (pattern instanceof Assign2) {
                  let label31 = pattern[0];
                  _block = [new Let(label31, value2, then$3), span];
                } else {
                  let matches = pattern[0];
                  _block = [
                    new Let("$", value2, destructured(matches, then$3)),
                    span
                  ];
                }
                let exp2 = _block;
                return new Ok([exp2, rest$3]);
              });
            });
          });
        });
      } else if (token2 instanceof Match2) {
        if (rest instanceof Empty) {
          return try$(expression(rest), (_use02) => {
            let subject = _use02[0];
            let rest$1 = _use02[1];
            if (rest$1 instanceof Empty) {
              return fail(rest$1);
            } else if (rest$1.head[0] instanceof LeftBrace) {
              let rest$2 = rest$1.tail;
              let inner = rest$1.head[1];
              return try$(clauses(rest$2, inner), (_use03) => {
                let exp2 = _use03[0];
                let end = _use03[1];
                let rest$3 = _use03[2];
                let span = [start, end];
                return new Ok([[new Apply(exp2, subject), span], rest$3]);
              });
            } else {
              return fail(rest$1);
            }
          });
        } else if (rest.head[0] instanceof LeftBrace) {
          let rest$1 = rest.tail;
          return try$(clauses(rest$1, start), (_use02) => {
            let exp2 = _use02[0];
            let rest$2 = _use02[2];
            return new Ok([exp2, rest$2]);
          });
        } else {
          return try$(expression(rest), (_use02) => {
            let subject = _use02[0];
            let rest$1 = _use02[1];
            if (rest$1 instanceof Empty) {
              return fail(rest$1);
            } else if (rest$1.head[0] instanceof LeftBrace) {
              let rest$2 = rest$1.tail;
              let inner = rest$1.head[1];
              return try$(clauses(rest$2, inner), (_use03) => {
                let exp2 = _use03[0];
                let end = _use03[1];
                let rest$3 = _use03[2];
                let span = [start, end];
                return new Ok([[new Apply(exp2, subject), span], rest$3]);
              });
            } else {
              return fail(rest$1);
            }
          });
        }
      } else if (token2 instanceof Perform3) {
        if (rest instanceof Empty) {
          return new Error2(new ExpectedEffectName("perform", next_pos(rest, start + 7)));
        } else {
          let $ = rest.head[0];
          if ($ instanceof Uppername) {
            let rest$1 = rest.tail;
            let end = rest.head[1];
            let label31 = $[0];
            let span = [start, end + string_length(label31)];
            return new Ok([[new Perform(label31), span], rest$1]);
          } else {
            return new Error2(new ExpectedEffectName("perform", next_pos(rest, start + 7)));
          }
        }
      } else if (token2 instanceof Handle3) {
        if (rest instanceof Empty) {
          return new Error2(new ExpectedEffectName("handle", next_pos(rest, start + 6)));
        } else {
          let $ = rest.head[0];
          if ($ instanceof Uppername) {
            let rest$1 = rest.tail;
            let end = rest.head[1];
            let label31 = $[0];
            let span = [start, end + string_length(label31)];
            return new Ok([[new Handle(label31), span], rest$1]);
          } else {
            return new Error2(new ExpectedEffectName("handle", next_pos(rest, start + 6)));
          }
        }
      } else if (token2 instanceof Import) {
        if (rest instanceof Empty) {
          return new Error2(new InvalidImportPath(next_pos(rest, start + 6)));
        } else {
          let $ = rest.head[0];
          if ($ instanceof String6) {
            let rest$1 = rest.tail;
            let end = rest.head[1];
            let value2 = $[0];
            let span = [start, end + string_length(value2) + 2];
            return new Ok([[new Reference(new Relative(value2)), span], rest$1]);
          } else {
            return new Error2(new InvalidImportPath(next_pos(rest, start + 6)));
          }
        }
      } else if (token2 instanceof Minus) {
        return try$(pop(rest), (_use02) => {
          let next;
          let from3;
          let rest$1;
          rest$1 = _use02[1];
          next = _use02[0][0];
          from3 = _use02[0][1];
          if (next instanceof Integer5) {
            let raw = next[0];
            let $ = parse_int(raw);
            let value2;
            if ($ instanceof Ok) {
              value2 = $[0];
            } else {
              throw makeError("let_assert", FILEPATH11, "eyg/parser/parser", 241, "expression", "Pattern match failed, no pattern matched the value.", {
                value: $,
                start: 7809,
                end: 7846,
                pattern_start: 7820,
                pattern_end: 7829
              });
            }
            return try$(in_range(-1 * value2, raw, from3), (value3) => {
              let span = [start, from3 + string_length(raw)];
              return new Ok([[new Integer(value3), span], rest$1]);
            });
          } else {
            return new Error2(new UnexpectedToken2(token2, start));
          }
        });
      } else if (token2 instanceof Bang) {
        if (rest instanceof Empty) {
          return new Error2(new ExpectedBuiltinName(next_pos(rest, start + 1)));
        } else {
          let $ = rest.head[0];
          if ($ instanceof Name) {
            let rest$1 = rest.tail;
            let end = rest.head[1];
            let label31 = $[0];
            let span = [start, end + string_length(label31)];
            return new Ok([[new Builtin(label31), span], rest$1]);
          } else {
            return new Error2(new ExpectedBuiltinName(next_pos(rest, start + 1)));
          }
        }
      } else if (token2 instanceof Hash2) {
        if (rest instanceof Empty) {
          return new Error2(new InvalidCidReference(next_pos(rest, start + 1)));
        } else {
          let $ = rest.head[0];
          if ($ instanceof Name) {
            let rest$1 = rest.tail;
            let end = rest.head[1];
            let label31 = $[0];
            let span = [start, end + string_length(label31)];
            let $1 = from_string(label31);
            if ($1 instanceof Ok) {
              let cid2 = $1[0][0];
              return new Ok([[new Reference(new Content(cid2)), span], rest$1]);
            } else {
              return new Error2(new InvalidCidReference(end));
            }
          } else {
            return new Error2(new InvalidCidReference(next_pos(rest, start + 1)));
          }
        }
      } else if (token2 instanceof At) {
        if (rest instanceof Empty) {
          return fail(rest);
        } else {
          let $ = rest.head[0];
          if ($ instanceof Name) {
            let rest$1 = rest.tail;
            let end = rest.head[1];
            let label31 = $[0];
            let after_name = end + string_length(label31);
            if (rest$1 instanceof Empty) {
              let span = [start, after_name];
              return new Ok([[new Reference(new Package(label31)), span], rest$1]);
            } else {
              let $1 = rest$1.tail;
              if ($1 instanceof Empty) {
                if (rest$1.head[0] instanceof Colon) {
                  let colon_at = rest$1.head[1];
                  return new Error2(new InvalidReleaseVersion(colon_at + 1));
                } else {
                  let span = [start, after_name];
                  return new Ok([
                    [new Reference(new Package(label31)), span],
                    rest$1
                  ]);
                }
              } else if (rest$1.head[0] instanceof Colon) {
                let $2 = $1.head[0];
                if ($2 instanceof Integer5) {
                  let rest$2 = $1.tail;
                  let int_at = $1.head[1];
                  let raw = $2[0];
                  let $3 = parse_int(raw);
                  let version;
                  if ($3 instanceof Ok) {
                    version = $3[0];
                  } else {
                    throw makeError("let_assert", FILEPATH11, "eyg/parser/parser", 320, "expression", "Pattern match failed, no pattern matched the value.", {
                      value: $3,
                      start: 10487,
                      end: 10526,
                      pattern_start: 10498,
                      pattern_end: 10509
                    });
                  }
                  let after_version = int_at + string_length(raw);
                  let $4 = version > 0;
                  if ($4) {
                    if (rest$2 instanceof Empty) {
                      let span = [start, after_version];
                      return new Ok([
                        [
                          new Reference(new Version(label31, version)),
                          span
                        ],
                        rest$2
                      ]);
                    } else {
                      let $5 = rest$2.tail;
                      if ($5 instanceof Empty) {
                        if (rest$2.head[0] instanceof Colon) {
                          let hash_at = rest$2.head[1];
                          return new Error2(new InvalidCidReference(hash_at + 1));
                        } else {
                          let span = [start, after_version];
                          return new Ok([
                            [
                              new Reference(new Version(label31, version)),
                              span
                            ],
                            rest$2
                          ]);
                        }
                      } else if (rest$2.head[0] instanceof Colon) {
                        let $6 = $5.head[0];
                        if ($6 instanceof Name) {
                          let rest$3 = $5.tail;
                          let cid_at = $5.head[1];
                          let cid_label = $6[0];
                          let after_cid = cid_at + string_length(cid_label);
                          let span = [start, after_cid];
                          let $7 = from_string(cid_label);
                          if ($7 instanceof Ok) {
                            let cid2 = $7[0][0];
                            return new Ok([
                              [
                                new Reference(new Pinned(new Release(label31, version, cid2))),
                                span
                              ],
                              rest$3
                            ]);
                          } else {
                            return new Error2(new InvalidCidReference(cid_at));
                          }
                        } else {
                          let hash_at = rest$2.head[1];
                          return new Error2(new InvalidCidReference(hash_at + 1));
                        }
                      } else {
                        let span = [start, after_version];
                        return new Ok([
                          [
                            new Reference(new Version(label31, version)),
                            span
                          ],
                          rest$2
                        ]);
                      }
                    }
                  } else {
                    return new Error2(new InvalidReleaseVersion(int_at));
                  }
                } else {
                  let colon_at = rest$1.head[1];
                  return new Error2(new InvalidReleaseVersion(colon_at + 1));
                }
              } else {
                let span = [start, after_name];
                return new Ok([
                  [new Reference(new Package(label31)), span],
                  rest$1
                ]);
              }
            }
          } else {
            return fail(rest);
          }
        }
      } else if (token2 instanceof LeftParen) {
        return try$(do_patterns(rest, List$Empty$const), (_use02) => {
          let patterns_reversed = _use02[0];
          let rest$1 = _use02[1];
          return try$((() => {
            if (rest$1 instanceof Empty) {
              return new Error2(Reason$UnexpectEnd$const);
            } else {
              let $ = rest$1.tail;
              if ($ instanceof Empty) {
                if (rest$1.head[0] instanceof RightArrow) {
                  let arrow_at = rest$1.head[1];
                  return new Error2(new MissingArrow(arrow_at + 2));
                } else {
                  let at = rest$1.head[1];
                  return new Error2(new MissingArrow(at));
                }
              } else if (rest$1.head[0] instanceof RightArrow) {
                if ($.head[0] instanceof LeftBrace) {
                  let rest$2 = $.tail;
                  let brace_at = $.head[1];
                  return new Ok([rest$2, brace_at]);
                } else {
                  let at = $.head[1];
                  return new Error2(new MissingArrow(at));
                }
              } else {
                let at = rest$1.head[1];
                return new Error2(new MissingArrow(at));
              }
            }
          })(), (_use03) => {
            let rest$2 = _use03[0];
            let brace_at = _use03[1];
            return try$(expression(rest$2), (_use04) => {
              let body = _use04[0];
              let rest$3 = _use04[1];
              return try$((() => {
                if (rest$3 instanceof Empty) {
                  return new Error2(new UnclosedFunctionBody(brace_at));
                } else if (rest$3.head[0] instanceof RightBrace) {
                  let rest$4 = rest$3.tail;
                  let end = rest$3.head[1];
                  return new Ok([rest$4, end]);
                } else {
                  return new Error2(new UnclosedFunctionBody(brace_at));
                }
              })(), (_use05) => {
                let rest$4 = _use05[0];
                let end = _use05[1];
                let span = [start, end + 1];
                let exp2 = fold2(patterns_reversed, body, (body2, pattern) => {
                  if (pattern instanceof Assign2) {
                    let label31 = pattern[0];
                    return [new Lambda(label31, body2), span];
                  } else {
                    let matches = pattern[0];
                    return [
                      new Lambda("$", destructured(matches, body2)),
                      span
                    ];
                  }
                });
                return new Ok([exp2, rest$4]);
              });
            });
          });
        });
      } else if (token2 instanceof LeftBrace) {
        return do_record(rest, start, List$Empty$const);
      } else if (token2 instanceof LeftSquare) {
        return do_list(rest, start, List$Empty$const);
      } else if (token2 instanceof UnexpectedGrapheme) {
        let raw = token2[0];
        return new Error2(new InvalidCharacter(slice(raw, 0, 1), start));
      } else if (token2 instanceof UnterminatedString) {
        return new Error2(new UnterminatedStringLiteral(start));
      } else if (token2 instanceof InvalidEscape) {
        let raw = token2[0];
        return new Error2(new InvalidEscapeSequence(slice(raw, 1, 1), start));
      } else {
        return new Error2(new UnexpectedToken2(token2, start));
      }
    })(), (_use02) => {
      let exp2 = _use02[0];
      let rest$1 = _use02[1];
      return after_expression(exp2, rest$1);
    });
  });
}

// build/dev/javascript/eyg_parser/eyg/parser/debug.mjs
function describe2(reason) {
  if (reason instanceof UnexpectEnd) {
    return "unexpected end of input";
  } else if (reason instanceof UnexpectedToken2) {
    let token2 = reason.token;
    let position = reason.position;
    return "unexpected `" + to_string8(token2) + "` at position " + to_string(position);
  } else if (reason instanceof MissingEquals) {
    let position = reason.position;
    return "expected `=` after let binding name at position " + to_string(position);
  } else if (reason instanceof MissingArrow) {
    let position = reason.position;
    return "expected `->` followed by `{` in function definition at position " + to_string(position);
  } else if (reason instanceof UnclosedFunctionBody) {
    let open_at = reason.open_at;
    return "unclosed function body \u2014 expected `}` to close the `{` opened at position " + to_string(open_at);
  } else if (reason instanceof ExpectedEffectName) {
    let keyword = reason.keyword;
    let position = reason.position;
    return "expected an uppercase effect name after `" + keyword + "` at position " + to_string(position);
  } else if (reason instanceof ExpectedBuiltinName) {
    let position = reason.position;
    return "expected a builtin identifier after `!` at position " + to_string(position);
  } else if (reason instanceof InvalidCidReference) {
    let position = reason.position;
    return "invalid content identifier (CID) at position " + to_string(position);
  } else if (reason instanceof InvalidReleaseVersion) {
    let position = reason.position;
    return "expected an integer release version after `:` at position " + to_string(position);
  } else if (reason instanceof InvalidImportPath) {
    let position = reason.position;
    return "expected a string path after `import` at position " + to_string(position);
  } else if (reason instanceof TrailingTokens) {
    let token2 = reason.token;
    let position = reason.position;
    let _block;
    if (token2 instanceof UnexpectedGrapheme) {
      let raw = token2[0];
      _block = slice(raw, 0, 1);
    } else {
      _block = to_string8(token2);
    }
    let token_str = _block;
    return "unexpected `" + token_str + "` at position " + to_string(position) + " \u2014 the expression is complete but there are leftover tokens";
  } else if (reason instanceof InvalidCharacter) {
    let char2 = reason.char;
    let position = reason.position;
    return "invalid character '" + char2 + "' at position " + to_string(position);
  } else if (reason instanceof UnterminatedStringLiteral) {
    let position = reason.position;
    return "unterminated string literal at position " + to_string(position);
  } else if (reason instanceof InvalidEscapeSequence) {
    let escape_char = reason.escape_char;
    let position = reason.position;
    return "invalid escape sequence `\\" + escape_char + "` in string at position " + to_string(position);
  } else {
    let raw = reason.raw;
    let position = reason.position;
    return "integer literal `" + raw + "` is out of range at position " + to_string(position);
  }
}
function hint2(reason) {
  if (reason instanceof UnexpectEnd) {
    return "program must end with valid expression";
  } else if (reason instanceof UnexpectedToken2) {
    return "view the syntax guide";
  } else if (reason instanceof MissingEquals) {
    return "let bindings use the form `let name = expression`";
  } else if (reason instanceof MissingArrow) {
    return "functions are written as `(arg) -> { body }`";
  } else if (reason instanceof UnclosedFunctionBody) {
    return "every `{` in a function body must be closed with `}`";
  } else if (reason instanceof ExpectedEffectName) {
    let keyword = reason.keyword;
    return "effect names must start with an uppercase letter, e.g. `" + keyword + " Log`";
  } else if (reason instanceof ExpectedBuiltinName) {
    return "builtins use lowercase names, e.g. `!int_add`";
  } else if (reason instanceof InvalidCidReference) {
    return "CID references use a valid base32-encoded CID, e.g. `#bafyreig...`";
  } else if (reason instanceof InvalidReleaseVersion) {
    return "pin a release with `@package:N` (e.g. `@tandard:3`) or omit `:` to track the latest";
  } else if (reason instanceof InvalidImportPath) {
    return 'import paths must be string literals, e.g. `import "./module.eyg.json"`';
  } else if (reason instanceof TrailingTokens) {
    let token2 = reason.token;
    if (token2 instanceof Let2) {
      return "the previous expression already completed the block. If you meant the block to continue, bind that expression to `let _ = ...` first.";
    } else {
      return "EYG uses function calls for operations (e.g. !int_add(a, b)), not infix operators";
    }
  } else if (reason instanceof InvalidCharacter) {
    return "remove or replace this character \u2014 EYG does not use it";
  } else if (reason instanceof UnterminatedStringLiteral) {
    return 'close the string with a double-quote `"`';
  } else if (reason instanceof InvalidEscapeSequence) {
    return "valid escapes are \\n (newline), \\t (tab), \\r (carriage return), \\\" (quote), \\\\ (backslash)";
  } else {
    return "on the JavaScript target integers must be within the safe range (-(2^53-1) to 2^53-1)";
  }
}

// build/dev/javascript/eyg_parser/eyg/parser/lexer.mjs
var FILEPATH12 = "src/eyg/parser/lexer.gleam";
function to_string9(bits2) {
  let $ = bit_array_to_string(bits2);
  if ($ instanceof Ok) {
    let s = $[0];
    return s;
  } else {
    throw makeError("panic", FILEPATH12, "eyg/parser/lexer", 139, "to_string", "invalid utf8 in token", {});
  }
}
function is_digit_grapheme(grapheme) {
  if (grapheme.bitSize === 8) {
    if (grapheme.byteAt(0) === 49) {
      return true;
    } else if (grapheme.byteAt(0) === 50) {
      return true;
    } else if (grapheme.byteAt(0) === 51) {
      return true;
    } else if (grapheme.byteAt(0) === 52) {
      return true;
    } else if (grapheme.byteAt(0) === 53) {
      return true;
    } else if (grapheme.byteAt(0) === 54) {
      return true;
    } else if (grapheme.byteAt(0) === 55) {
      return true;
    } else if (grapheme.byteAt(0) === 56) {
      return true;
    } else if (grapheme.byteAt(0) === 57) {
      return true;
    } else if (grapheme.byteAt(0) === 48) {
      return true;
    } else {
      return false;
    }
  } else {
    return false;
  }
}
function is_lower_grapheme(grapheme) {
  if (grapheme.bitSize === 8) {
    if (grapheme.byteAt(0) === 97) {
      return true;
    } else if (grapheme.byteAt(0) === 98) {
      return true;
    } else if (grapheme.byteAt(0) === 99) {
      return true;
    } else if (grapheme.byteAt(0) === 100) {
      return true;
    } else if (grapheme.byteAt(0) === 101) {
      return true;
    } else if (grapheme.byteAt(0) === 102) {
      return true;
    } else if (grapheme.byteAt(0) === 103) {
      return true;
    } else if (grapheme.byteAt(0) === 104) {
      return true;
    } else if (grapheme.byteAt(0) === 105) {
      return true;
    } else if (grapheme.byteAt(0) === 106) {
      return true;
    } else if (grapheme.byteAt(0) === 107) {
      return true;
    } else if (grapheme.byteAt(0) === 108) {
      return true;
    } else if (grapheme.byteAt(0) === 109) {
      return true;
    } else if (grapheme.byteAt(0) === 110) {
      return true;
    } else if (grapheme.byteAt(0) === 111) {
      return true;
    } else if (grapheme.byteAt(0) === 112) {
      return true;
    } else if (grapheme.byteAt(0) === 113) {
      return true;
    } else if (grapheme.byteAt(0) === 114) {
      return true;
    } else if (grapheme.byteAt(0) === 115) {
      return true;
    } else if (grapheme.byteAt(0) === 116) {
      return true;
    } else if (grapheme.byteAt(0) === 117) {
      return true;
    } else if (grapheme.byteAt(0) === 118) {
      return true;
    } else if (grapheme.byteAt(0) === 119) {
      return true;
    } else if (grapheme.byteAt(0) === 120) {
      return true;
    } else if (grapheme.byteAt(0) === 121) {
      return true;
    } else if (grapheme.byteAt(0) === 122) {
      return true;
    } else {
      return false;
    }
  } else {
    return false;
  }
}
function is_upper_grapheme(grapheme) {
  if (grapheme.bitSize === 8) {
    if (grapheme.byteAt(0) === 65) {
      return true;
    } else if (grapheme.byteAt(0) === 66) {
      return true;
    } else if (grapheme.byteAt(0) === 67) {
      return true;
    } else if (grapheme.byteAt(0) === 68) {
      return true;
    } else if (grapheme.byteAt(0) === 69) {
      return true;
    } else if (grapheme.byteAt(0) === 70) {
      return true;
    } else if (grapheme.byteAt(0) === 71) {
      return true;
    } else if (grapheme.byteAt(0) === 72) {
      return true;
    } else if (grapheme.byteAt(0) === 73) {
      return true;
    } else if (grapheme.byteAt(0) === 74) {
      return true;
    } else if (grapheme.byteAt(0) === 75) {
      return true;
    } else if (grapheme.byteAt(0) === 76) {
      return true;
    } else if (grapheme.byteAt(0) === 77) {
      return true;
    } else if (grapheme.byteAt(0) === 78) {
      return true;
    } else if (grapheme.byteAt(0) === 79) {
      return true;
    } else if (grapheme.byteAt(0) === 80) {
      return true;
    } else if (grapheme.byteAt(0) === 81) {
      return true;
    } else if (grapheme.byteAt(0) === 82) {
      return true;
    } else if (grapheme.byteAt(0) === 83) {
      return true;
    } else if (grapheme.byteAt(0) === 84) {
      return true;
    } else if (grapheme.byteAt(0) === 85) {
      return true;
    } else if (grapheme.byteAt(0) === 86) {
      return true;
    } else if (grapheme.byteAt(0) === 87) {
      return true;
    } else if (grapheme.byteAt(0) === 88) {
      return true;
    } else if (grapheme.byteAt(0) === 89) {
      return true;
    } else if (grapheme.byteAt(0) === 90) {
      return true;
    } else {
      return false;
    }
  } else {
    return false;
  }
}
function bytes_drop_first(raw) {
  if (raw.bitSize >= 8) {
    let slice2 = bitArraySlice(raw, 8);
    return slice2;
  } else if (raw.bitSize === 0) {
    return toBitArray([]);
  } else {
    throw makeError("panic", FILEPATH12, "eyg/parser/lexer", 368, "bytes_drop_first", "unexpected bit string", {});
  }
}
function bytes_take_first(raw) {
  if (raw.bitSize >= 8) {
    let byte = raw.byteAt(0);
    return toBitArray([byte]);
  } else if (raw.bitSize === 0) {
    return toBitArray([]);
  } else {
    throw makeError("panic", FILEPATH12, "eyg/parser/lexer", 359, "bytes_take_first", "unexpected bit string", {});
  }
}
function uppername(loop$buffer, loop$raw, loop$done) {
  while (true) {
    let buffer = loop$buffer;
    let raw = loop$raw;
    let done = loop$done;
    let next_byte = bytes_take_first(raw);
    let rest = bytes_drop_first(raw);
    let $ = is_upper_grapheme(next_byte) || is_lower_grapheme(next_byte) || is_digit_grapheme(next_byte) || isEqual(next_byte, toBitArray([stringBits("_")]));
    if ($) {
      loop$buffer = append2(buffer, next_byte);
      loop$raw = rest;
      loop$done = done;
    } else {
      return done(new Uppername(to_string9(buffer)), bit_array_byte_size(buffer), raw);
    }
  }
}
function keyword_or_name(buffer) {
  if (buffer === "let") {
    return Token$Let$const;
  } else if (buffer === "match") {
    return Token$Match$const;
  } else if (buffer === "perform") {
    return Token$Perform$const;
  } else if (buffer === "deep") {
    return Token$Deep$const;
  } else if (buffer === "handle") {
    return Token$Handle$const;
  } else if (buffer === "import") {
    return Token$Import$const;
  } else {
    return new Name(buffer);
  }
}
function name(loop$buffer, loop$raw, loop$done) {
  while (true) {
    let buffer = loop$buffer;
    let raw = loop$raw;
    let done = loop$done;
    let next_byte = bytes_take_first(raw);
    let rest = bytes_drop_first(raw);
    let $ = is_lower_grapheme(next_byte) || is_digit_grapheme(next_byte) || isEqual(next_byte, toBitArray([stringBits("_")]));
    if ($) {
      loop$buffer = append2(buffer, next_byte);
      loop$raw = rest;
      loop$done = done;
    } else {
      return done(keyword_or_name(to_string9(buffer)), bit_array_byte_size(buffer), raw);
    }
  }
}
function integer(loop$buffer, loop$rest, loop$done) {
  while (true) {
    let buffer = loop$buffer;
    let rest = loop$rest;
    let done = loop$done;
    if (rest.bitSize >= 8) {
      if (rest.byteAt(0) === 49) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits("1")]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 50) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits("2")]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 51) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits("3")]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 52) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits("4")]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 53) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits("5")]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 54) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits("6")]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 55) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits("7")]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 56) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits("8")]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 57) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits("9")]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 48) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits("0")]));
        loop$rest = rest$1;
        loop$done = done;
      } else {
        return done(new Integer5(to_string9(buffer)), bit_array_byte_size(buffer), rest);
      }
    } else {
      return done(new Integer5(to_string9(buffer)), bit_array_byte_size(buffer), rest);
    }
  }
}
function string6(loop$buffer, loop$length, loop$rest, loop$done) {
  while (true) {
    let buffer = loop$buffer;
    let length4 = loop$length;
    let rest = loop$rest;
    let done = loop$done;
    if (rest.bitSize >= 8) {
      if (rest.byteAt(0) === 34) {
        let rest$1 = bitArraySlice(rest, 8);
        return done(new String6(to_string9(buffer)), length4 + 1, rest$1);
      } else if (rest.byteAt(0) === 92) {
        let rest$1 = bitArraySlice(rest, 8);
        if (rest$1.bitSize >= 8) {
          if (rest$1.byteAt(0) === 34) {
            let rest$2 = bitArraySlice(rest$1, 8);
            loop$buffer = append2(buffer, toBitArray([stringBits('"')]));
            loop$length = length4 + 2;
            loop$rest = rest$2;
            loop$done = done;
          } else if (rest$1.byteAt(0) === 92) {
            let rest$2 = bitArraySlice(rest$1, 8);
            loop$buffer = append2(buffer, toBitArray([stringBits("\\")]));
            loop$length = length4 + 2;
            loop$rest = rest$2;
            loop$done = done;
          } else if (rest$1.byteAt(0) === 116) {
            let rest$2 = bitArraySlice(rest$1, 8);
            loop$buffer = append2(buffer, toBitArray([stringBits("\t")]));
            loop$length = length4 + 2;
            loop$rest = rest$2;
            loop$done = done;
          } else if (rest$1.byteAt(0) === 114) {
            let rest$2 = bitArraySlice(rest$1, 8);
            loop$buffer = append2(buffer, toBitArray([stringBits("\r")]));
            loop$length = length4 + 2;
            loop$rest = rest$2;
            loop$done = done;
          } else if (rest$1.byteAt(0) === 110) {
            let rest$2 = bitArraySlice(rest$1, 8);
            loop$buffer = append2(buffer, toBitArray([stringBits(`
`)]));
            loop$length = length4 + 2;
            loop$rest = rest$2;
            loop$done = done;
          } else {
            return done(new InvalidEscape(to_string9(append2(append2(buffer, toBitArray([stringBits("\\")])), rest$1))), length4, toBitArray([]));
          }
        } else if (rest$1.bitSize === 0) {
          return done(new UnterminatedString(to_string9(append2(buffer, toBitArray([stringBits("\\")])))), length4 + 1, toBitArray([]));
        } else {
          return done(new InvalidEscape(to_string9(append2(append2(buffer, toBitArray([stringBits("\\")])), rest$1))), length4, toBitArray([]));
        }
      } else {
        let next_byte = bytes_take_first(rest);
        let rest$1 = bytes_drop_first(rest);
        loop$buffer = append2(buffer, next_byte);
        loop$length = length4 + 1;
        loop$rest = rest$1;
        loop$done = done;
      }
    } else if (rest.bitSize === 0) {
      return done(new UnterminatedString(to_string9(buffer)), length4, toBitArray([]));
    } else {
      let next_byte = bytes_take_first(rest);
      let rest$1 = bytes_drop_first(rest);
      loop$buffer = append2(buffer, next_byte);
      loop$length = length4 + 1;
      loop$rest = rest$1;
      loop$done = done;
    }
  }
}
function whitespace(loop$buffer, loop$rest, loop$done) {
  while (true) {
    let buffer = loop$buffer;
    let rest = loop$rest;
    let done = loop$done;
    if (rest.bitSize >= 16) {
      if (rest.byteAt(0) === 13 && rest.byteAt(1) === 10) {
        let rest$1 = bitArraySlice(rest, 16);
        loop$buffer = append2(buffer, toBitArray([stringBits(`\r
`)]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 10) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits(`
`)]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 32) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits(" ")]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 9) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits("\t")]));
        loop$rest = rest$1;
        loop$done = done;
      } else {
        return done(new Whitespace(to_string9(buffer)), bit_array_byte_size(buffer), rest);
      }
    } else if (rest.bitSize >= 8) {
      if (rest.byteAt(0) === 10) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits(`
`)]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 32) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits(" ")]));
        loop$rest = rest$1;
        loop$done = done;
      } else if (rest.byteAt(0) === 9) {
        let rest$1 = bitArraySlice(rest, 8);
        loop$buffer = append2(buffer, toBitArray([stringBits("\t")]));
        loop$rest = rest$1;
        loop$done = done;
      } else {
        return done(new Whitespace(to_string9(buffer)), bit_array_byte_size(buffer), rest);
      }
    } else {
      return done(new Whitespace(to_string9(buffer)), bit_array_byte_size(buffer), rest);
    }
  }
}
function comment(loop$buffer, loop$rest, loop$done) {
  while (true) {
    let buffer = loop$buffer;
    let rest = loop$rest;
    let done = loop$done;
    if (rest.bitSize >= 16) {
      if (rest.byteAt(0) === 13 && rest.byteAt(1) === 10) {
        return done(new Comment(to_string9(buffer)), bit_array_byte_size(buffer) + 2, rest);
      } else if (rest.byteAt(0) === 10) {
        return done(new Comment(to_string9(buffer)), bit_array_byte_size(buffer) + 2, rest);
      } else {
        let next_byte = bytes_take_first(rest);
        let rest$1 = bytes_drop_first(rest);
        loop$buffer = append2(buffer, next_byte);
        loop$rest = rest$1;
        loop$done = done;
      }
    } else if (rest.bitSize >= 8) {
      if (rest.byteAt(0) === 10) {
        return done(new Comment(to_string9(buffer)), bit_array_byte_size(buffer) + 2, rest);
      } else {
        let next_byte = bytes_take_first(rest);
        let rest$1 = bytes_drop_first(rest);
        loop$buffer = append2(buffer, next_byte);
        loop$rest = rest$1;
        loop$done = done;
      }
    } else if (rest.bitSize === 0) {
      return done(new Comment(to_string9(buffer)), bit_array_byte_size(buffer) + 2, toBitArray([]));
    } else {
      let next_byte = bytes_take_first(rest);
      let rest$1 = bytes_drop_first(rest);
      loop$buffer = append2(buffer, next_byte);
      loop$rest = rest$1;
      loop$done = done;
    }
  }
}
function done(start) {
  return (t, size2, rest) => {
    return new Ok([[t, start], start + size2, rest]);
  };
}
function pop2(raw, start) {
  let done$1 = done(start);
  if (raw.bitSize >= 16) {
    if (raw.byteAt(0) === 47 && raw.byteAt(1) === 47) {
      let rest = bitArraySlice(raw, 16);
      return comment(toBitArray([]), rest, done$1);
    } else if (raw.byteAt(0) === 13 && raw.byteAt(1) === 10) {
      let rest = bitArraySlice(raw, 16);
      return whitespace(toBitArray([stringBits(`\r
`)]), rest, done$1);
    } else if (raw.byteAt(0) === 10) {
      let rest = bitArraySlice(raw, 8);
      return whitespace(toBitArray([stringBits(`
`)]), rest, done$1);
    } else if (raw.byteAt(0) === 32) {
      let rest = bitArraySlice(raw, 8);
      return whitespace(toBitArray([stringBits(" ")]), rest, done$1);
    } else if (raw.byteAt(0) === 9) {
      let rest = bitArraySlice(raw, 8);
      return whitespace(toBitArray([stringBits("\t")]), rest, done$1);
    } else if (raw.byteAt(0) === 40) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$LeftParen$const, 1, rest);
    } else if (raw.byteAt(0) === 41) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$RightParen$const, 1, rest);
    } else if (raw.byteAt(0) === 123) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$LeftBrace$const, 1, rest);
    } else if (raw.byteAt(0) === 125) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$RightBrace$const, 1, rest);
    } else if (raw.byteAt(0) === 91) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$LeftSquare$const, 1, rest);
    } else if (raw.byteAt(0) === 93) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$RightSquare$const, 1, rest);
    } else if (raw.byteAt(0) === 61) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Equal$const, 1, rest);
    } else if (raw.byteAt(0) === 45 && raw.byteAt(1) === 62) {
      let rest = bitArraySlice(raw, 16);
      return done$1(Token$RightArrow$const, 2, rest);
    } else if (raw.byteAt(0) === 44) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Comma$const, 1, rest);
    } else if (raw.byteAt(0) === 46 && raw.byteAt(1) === 46) {
      let rest = bitArraySlice(raw, 16);
      return done$1(Token$DotDot$const, 2, rest);
    } else if (raw.byteAt(0) === 46) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Dot$const, 1, rest);
    } else if (raw.byteAt(0) === 58) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Colon$const, 1, rest);
    } else if (raw.byteAt(0) === 45) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Minus$const, 1, rest);
    } else if (raw.byteAt(0) === 33) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Bang$const, 1, rest);
    } else if (raw.byteAt(0) === 124) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Bar$const, 1, rest);
    } else if (raw.byteAt(0) === 35) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Hash$const, 1, rest);
    } else if (raw.byteAt(0) === 64) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$At$const, 1, rest);
    } else if (raw.byteAt(0) === 34) {
      let rest = bitArraySlice(raw, 8);
      return string6(toBitArray([]), 1, rest, done$1);
    } else if (raw.byteAt(0) === 49) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("1")]), rest, done$1);
    } else if (raw.byteAt(0) === 50) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("2")]), rest, done$1);
    } else if (raw.byteAt(0) === 51) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("3")]), rest, done$1);
    } else if (raw.byteAt(0) === 52) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("4")]), rest, done$1);
    } else if (raw.byteAt(0) === 53) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("5")]), rest, done$1);
    } else if (raw.byteAt(0) === 54) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("6")]), rest, done$1);
    } else if (raw.byteAt(0) === 55) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("7")]), rest, done$1);
    } else if (raw.byteAt(0) === 56) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("8")]), rest, done$1);
    } else if (raw.byteAt(0) === 57) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("9")]), rest, done$1);
    } else if (raw.byteAt(0) === 48) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("0")]), rest, done$1);
    } else {
      let next_byte = bytes_take_first(raw);
      let rest = bytes_drop_first(raw);
      if (next_byte.bitSize === 8) {
        if (next_byte.byteAt(0) === 95) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 97) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 98) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 99) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 100) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 101) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 102) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 103) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 104) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 105) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 106) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 107) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 108) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 109) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 110) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 111) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 112) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 113) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 114) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 115) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 116) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 117) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 118) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 119) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 120) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 121) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 122) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 65) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 66) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 67) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 68) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 69) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 70) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 71) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 72) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 73) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 74) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 75) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 76) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 77) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 78) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 79) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 80) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 81) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 82) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 83) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 84) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 85) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 86) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 87) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 88) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 89) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 90) {
          return uppername(next_byte, rest, done$1);
        } else {
          let string$1 = to_string9(raw);
          let _block;
          let _pipe = pop_grapheme(string$1);
          _block = unwrap(_pipe, [string$1, ""]);
          let $ = _block;
          let char2 = $[0];
          let rest$1 = $[1];
          let size2 = bit_array_byte_size(toBitArray([stringBits(char2)]));
          return done$1(new UnexpectedGrapheme(char2), size2, toBitArray([stringBits(rest$1)]));
        }
      } else if (next_byte.bitSize === 0) {
        return new Error2(undefined);
      } else {
        let string$1 = to_string9(raw);
        let _block;
        let _pipe = pop_grapheme(string$1);
        _block = unwrap(_pipe, [string$1, ""]);
        let $ = _block;
        let char2 = $[0];
        let rest$1 = $[1];
        let size2 = bit_array_byte_size(toBitArray([stringBits(char2)]));
        return done$1(new UnexpectedGrapheme(char2), size2, toBitArray([stringBits(rest$1)]));
      }
    }
  } else if (raw.bitSize >= 8) {
    if (raw.byteAt(0) === 10) {
      let rest = bitArraySlice(raw, 8);
      return whitespace(toBitArray([stringBits(`
`)]), rest, done$1);
    } else if (raw.byteAt(0) === 32) {
      let rest = bitArraySlice(raw, 8);
      return whitespace(toBitArray([stringBits(" ")]), rest, done$1);
    } else if (raw.byteAt(0) === 9) {
      let rest = bitArraySlice(raw, 8);
      return whitespace(toBitArray([stringBits("\t")]), rest, done$1);
    } else if (raw.byteAt(0) === 40) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$LeftParen$const, 1, rest);
    } else if (raw.byteAt(0) === 41) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$RightParen$const, 1, rest);
    } else if (raw.byteAt(0) === 123) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$LeftBrace$const, 1, rest);
    } else if (raw.byteAt(0) === 125) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$RightBrace$const, 1, rest);
    } else if (raw.byteAt(0) === 91) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$LeftSquare$const, 1, rest);
    } else if (raw.byteAt(0) === 93) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$RightSquare$const, 1, rest);
    } else if (raw.byteAt(0) === 61) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Equal$const, 1, rest);
    } else if (raw.byteAt(0) === 44) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Comma$const, 1, rest);
    } else if (raw.byteAt(0) === 46) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Dot$const, 1, rest);
    } else if (raw.byteAt(0) === 58) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Colon$const, 1, rest);
    } else if (raw.byteAt(0) === 45) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Minus$const, 1, rest);
    } else if (raw.byteAt(0) === 33) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Bang$const, 1, rest);
    } else if (raw.byteAt(0) === 124) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Bar$const, 1, rest);
    } else if (raw.byteAt(0) === 35) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$Hash$const, 1, rest);
    } else if (raw.byteAt(0) === 64) {
      let rest = bitArraySlice(raw, 8);
      return done$1(Token$At$const, 1, rest);
    } else if (raw.byteAt(0) === 34) {
      let rest = bitArraySlice(raw, 8);
      return string6(toBitArray([]), 1, rest, done$1);
    } else if (raw.byteAt(0) === 49) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("1")]), rest, done$1);
    } else if (raw.byteAt(0) === 50) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("2")]), rest, done$1);
    } else if (raw.byteAt(0) === 51) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("3")]), rest, done$1);
    } else if (raw.byteAt(0) === 52) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("4")]), rest, done$1);
    } else if (raw.byteAt(0) === 53) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("5")]), rest, done$1);
    } else if (raw.byteAt(0) === 54) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("6")]), rest, done$1);
    } else if (raw.byteAt(0) === 55) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("7")]), rest, done$1);
    } else if (raw.byteAt(0) === 56) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("8")]), rest, done$1);
    } else if (raw.byteAt(0) === 57) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("9")]), rest, done$1);
    } else if (raw.byteAt(0) === 48) {
      let rest = bitArraySlice(raw, 8);
      return integer(toBitArray([stringBits("0")]), rest, done$1);
    } else {
      let next_byte = bytes_take_first(raw);
      let rest = bytes_drop_first(raw);
      if (next_byte.bitSize === 8) {
        if (next_byte.byteAt(0) === 95) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 97) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 98) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 99) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 100) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 101) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 102) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 103) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 104) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 105) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 106) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 107) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 108) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 109) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 110) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 111) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 112) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 113) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 114) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 115) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 116) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 117) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 118) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 119) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 120) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 121) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 122) {
          return name(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 65) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 66) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 67) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 68) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 69) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 70) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 71) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 72) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 73) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 74) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 75) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 76) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 77) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 78) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 79) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 80) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 81) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 82) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 83) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 84) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 85) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 86) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 87) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 88) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 89) {
          return uppername(next_byte, rest, done$1);
        } else if (next_byte.byteAt(0) === 90) {
          return uppername(next_byte, rest, done$1);
        } else {
          let string$1 = to_string9(raw);
          let _block;
          let _pipe = pop_grapheme(string$1);
          _block = unwrap(_pipe, [string$1, ""]);
          let $ = _block;
          let char2 = $[0];
          let rest$1 = $[1];
          let size2 = bit_array_byte_size(toBitArray([stringBits(char2)]));
          return done$1(new UnexpectedGrapheme(char2), size2, toBitArray([stringBits(rest$1)]));
        }
      } else if (next_byte.bitSize === 0) {
        return new Error2(undefined);
      } else {
        let string$1 = to_string9(raw);
        let _block;
        let _pipe = pop_grapheme(string$1);
        _block = unwrap(_pipe, [string$1, ""]);
        let $ = _block;
        let char2 = $[0];
        let rest$1 = $[1];
        let size2 = bit_array_byte_size(toBitArray([stringBits(char2)]));
        return done$1(new UnexpectedGrapheme(char2), size2, toBitArray([stringBits(rest$1)]));
      }
    }
  } else {
    let next_byte = bytes_take_first(raw);
    let rest = bytes_drop_first(raw);
    if (next_byte.bitSize === 8) {
      if (next_byte.byteAt(0) === 95) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 97) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 98) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 99) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 100) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 101) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 102) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 103) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 104) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 105) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 106) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 107) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 108) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 109) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 110) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 111) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 112) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 113) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 114) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 115) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 116) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 117) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 118) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 119) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 120) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 121) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 122) {
        return name(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 65) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 66) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 67) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 68) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 69) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 70) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 71) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 72) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 73) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 74) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 75) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 76) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 77) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 78) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 79) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 80) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 81) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 82) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 83) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 84) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 85) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 86) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 87) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 88) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 89) {
        return uppername(next_byte, rest, done$1);
      } else if (next_byte.byteAt(0) === 90) {
        return uppername(next_byte, rest, done$1);
      } else {
        let string$1 = to_string9(raw);
        let _block;
        let _pipe = pop_grapheme(string$1);
        _block = unwrap(_pipe, [string$1, ""]);
        let $ = _block;
        let char2 = $[0];
        let rest$1 = $[1];
        let size2 = bit_array_byte_size(toBitArray([stringBits(char2)]));
        return done$1(new UnexpectedGrapheme(char2), size2, toBitArray([stringBits(rest$1)]));
      }
    } else if (next_byte.bitSize === 0) {
      return new Error2(undefined);
    } else {
      let string$1 = to_string9(raw);
      let _block;
      let _pipe = pop_grapheme(string$1);
      _block = unwrap(_pipe, [string$1, ""]);
      let $ = _block;
      let char2 = $[0];
      let rest$1 = $[1];
      let size2 = bit_array_byte_size(toBitArray([stringBits(char2)]));
      return done$1(new UnexpectedGrapheme(char2), size2, toBitArray([stringBits(rest$1)]));
    }
  }
}
function loop4(loop$raw, loop$offset, loop$acc) {
  while (true) {
    let raw = loop$raw;
    let offset = loop$offset;
    let acc = loop$acc;
    let $ = pop2(raw, offset);
    if ($ instanceof Ok) {
      let token2 = $[0][0];
      let offset$1 = $[0][1];
      let rest = $[0][2];
      loop$raw = rest;
      loop$offset = offset$1;
      loop$acc = prepend(token2, acc);
    } else {
      return reverse(acc);
    }
  }
}
function lex(raw) {
  let bits2 = bit_array_from_string(raw);
  return loop4(bits2, 0, List$Empty$const);
}

// build/dev/javascript/eyg_parser/eyg/parser.mjs
function from_string4(src) {
  let _pipe = src;
  let _pipe$1 = lex(_pipe);
  let _pipe$2 = drop_whitespace(_pipe$1);
  let _pipe$3 = drop_comments(_pipe$2);
  return expression(_pipe$3);
}
function all_from_string(src) {
  return try$(from_string4(src), (_use0) => {
    let source = _use0[0];
    let remaining = _use0[1];
    if (remaining instanceof Empty) {
      return new Ok(source);
    } else {
      let tok = remaining.head[0];
      let at = remaining.head[1];
      return new Error2(new TrailingTokens(tok, at));
    }
  });
}
function render_error(description, hint3, code3, span) {
  let lines = prepend("error: " + description, prepend("hint: " + hint3, List$Empty$const));
  let _block;
  if (span[0] === 0 && span[1] === 0) {
    _block = List$Empty$const;
  } else {
    _block = prepend("", source_context(code3, span));
  }
  let context = _block;
  return join(append3(lines, context), `
`);
}
function reason_position(reason) {
  if (reason instanceof UnexpectEnd) {
    return Option$None$const;
  } else if (reason instanceof UnexpectedToken2) {
    let pos = reason.position;
    return new Some(pos);
  } else if (reason instanceof MissingEquals) {
    let pos = reason.position;
    return new Some(pos);
  } else if (reason instanceof MissingArrow) {
    let pos = reason.position;
    return new Some(pos);
  } else if (reason instanceof UnclosedFunctionBody) {
    let open_at = reason.open_at;
    return new Some(open_at);
  } else if (reason instanceof ExpectedEffectName) {
    let pos = reason.position;
    return new Some(pos);
  } else if (reason instanceof ExpectedBuiltinName) {
    let pos = reason.position;
    return new Some(pos);
  } else if (reason instanceof InvalidCidReference) {
    let pos = reason.position;
    return new Some(pos);
  } else if (reason instanceof InvalidReleaseVersion) {
    let pos = reason.position;
    return new Some(pos);
  } else if (reason instanceof InvalidImportPath) {
    let pos = reason.position;
    return new Some(pos);
  } else if (reason instanceof TrailingTokens) {
    let pos = reason.position;
    return new Some(pos);
  } else if (reason instanceof InvalidCharacter) {
    let pos = reason.position;
    return new Some(pos);
  } else if (reason instanceof UnterminatedStringLiteral) {
    let pos = reason.position;
    return new Some(pos);
  } else if (reason instanceof InvalidEscapeSequence) {
    let pos = reason.position;
    return new Some(pos);
  } else {
    let pos = reason.position;
    return new Some(pos);
  }
}
function format_error(reason, source) {
  let description = describe2(reason);
  let hint3 = hint2(reason);
  let _block;
  let $ = reason_position(reason);
  if ($ instanceof Some) {
    let start = $[0];
    _block = [start, start];
  } else {
    _block = [0, 0];
  }
  let span = _block;
  return render_error(description, hint3, source, span);
}
// build/dev/javascript/envoy/envoy_ffi.mjs
function get3(key3) {
  let value2;
  if (globalThis.Deno) {
    value2 = Deno.env.get(key3);
  } else if (globalThis.process) {
    value2 = process.env[key3];
  }
  if (value2 === undefined) {
    return Result$Error(undefined);
  } else {
    return Result$Ok(value2);
  }
}
// build/dev/javascript/gleam_crypto/gleam_crypto_ffi.mjs
import * as crypto2 from "crypto";
function algorithmName(algorithm) {
  if (algorithm instanceof Sha13) {
    return "sha1";
  } else if (algorithm instanceof Sha224) {
    return "sha224";
  } else if (algorithm instanceof Sha2565) {
    return "sha256";
  } else if (algorithm instanceof Sha3843) {
    return "sha384";
  } else if (algorithm instanceof Sha5123) {
    return "sha512";
  } else if (algorithm instanceof Md52) {
    return "md5";
  } else {
    throw new Error("Unsupported algorithm");
  }
}
function hashInit(algorithm) {
  return crypto2.createHash(algorithmName(algorithm));
}
function hashUpdate2(hasher, hashChunk) {
  hasher.update(hashChunk.rawBuffer);
  return hasher;
}
function digest(hasher) {
  const array3 = new Uint8Array(hasher.digest());
  return new BitArray(array3);
}

// build/dev/javascript/gleam_crypto/gleam/crypto.mjs
class Sha224 extends CustomType {
}
var HashAlgorithm$Sha224$const = new Sha224;
class Sha2565 extends CustomType {
}
var HashAlgorithm$Sha256$const3 = new Sha2565;
class Sha3843 extends CustomType {
}
var HashAlgorithm$Sha384$const3 = new Sha3843;
class Sha5123 extends CustomType {
}
var HashAlgorithm$Sha512$const3 = new Sha5123;
class Md52 extends CustomType {
}
var HashAlgorithm$Md5$const2 = new Md52;
class Sha13 extends CustomType {
}
var HashAlgorithm$Sha1$const3 = new Sha13;
function hash2(algorithm, data) {
  let _pipe = hashInit(algorithm);
  let _pipe$1 = hashUpdate2(_pipe, data);
  return digest(_pipe$1);
}
// build/dev/javascript/gleam_fetch/gleam_fetch_ffi.mjs
async function raw_send(request2) {
  try {
    return Result$Ok(await fetch(request2));
  } catch (error2) {
    return Result$Error(FetchError$NetworkError(error2.toString()));
  }
}
function from_fetch_response(response2) {
  let headers2 = [...response2.headers].reverse();
  return Response$Response(response2.status, arrayToList2(headers2), response2);
}
function request_common(request2) {
  let url = to_string4(to_uri(request2));
  let method2 = method_to_string(request2.method).toUpperCase();
  let options = {
    headers: make_headers(request2.headers),
    method: method2
  };
  return [url, options];
}
function bitarray_request_to_fetch_request(request2) {
  let [url, options] = request_common(request2);
  if (options.method !== "GET" && options.method !== "HEAD")
    options.body = request2.body.rawBuffer;
  return new globalThis.Request(url, options);
}
function make_headers(headersList) {
  let headers2 = new globalThis.Headers;
  for (let [k, v] of headersList)
    headers2.append(k.toLowerCase(), v);
  return headers2;
}
async function read_bytes_body(response2) {
  let body;
  try {
    body = await response2.body.arrayBuffer();
  } catch (error2) {
    return Result$Error(FetchError$UnableToReadBody());
  }
  body = BitArray$BitArray(new Uint8Array(body));
  return Result$Ok(map7(response2, () => body));
}
function arrayToList2(array3) {
  let list3 = List$Empty();
  for (const element of array3) {
    list3 = List$NonEmpty(element, list3);
  }
  return list3;
}

// build/dev/javascript/gleam_fetch/gleam/fetch.mjs
class NetworkError2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
var FetchError$NetworkError = ($0) => new NetworkError2($0);
class UnableToReadBody2 extends CustomType {
}
var FetchError$UnableToReadBody$const2 = new UnableToReadBody2;
var FetchError$UnableToReadBody = () => FetchError$UnableToReadBody$const2;
class InvalidJsonBody extends CustomType {
}
var FetchError$InvalidJsonBody$const = new InvalidJsonBody;
function send_bits(request2) {
  let _pipe = request2;
  let _pipe$1 = bitarray_request_to_fetch_request(_pipe);
  let _pipe$2 = raw_send(_pipe$1);
  return try_await(_pipe$2, (resp) => {
    return resolve2(new Ok(from_fetch_response(resp)));
  });
}

// build/dev/javascript/gleam_x/gleam/fetchx.mjs
function send_bits2(request2) {
  return try_await(send_bits(request2), (response2) => {
    return read_bytes_body(response2);
  });
}

// build/dev/javascript/input/input_ffi.mjs
import fs2 from "fs";
import { Buffer as Buffer2 } from "buffer";
function input(prompt) {
  try {
    process.stdout.write(prompt);
    const buffer = Buffer2.alloc(4096);
    const bytesRead = fs2.readSync(0, buffer, 0, buffer.length, null);
    let input2 = buffer.toString("utf-8", 0, bytesRead);
    input2 = input2.replace(/[\r\n]+$/, "");
    return new Ok(input2);
  } catch {
    return new Error2(undefined);
  }
}
// build/dev/javascript/shellout/shellout_ffi.mjs
import process3 from "process";
function os_exit(status) {
  process3.exit(status);
}

// build/dev/javascript/shellout/shellout.mjs
class LetBeStderr extends CustomType {
}
var CommandOpt$LetBeStderr$const = new LetBeStderr;
class LetBeStdout extends CustomType {
}
var CommandOpt$LetBeStdout$const = new LetBeStdout;
class OverlappedStdio extends CustomType {
}
var CommandOpt$OverlappedStdio$const = new OverlappedStdio;

// build/dev/javascript/untethered/untethered/keypair.mjs
class Keypair extends CustomType {
  constructor(key_id, private_key, public_key) {
    super();
    this.key_id = key_id;
    this.private_key = private_key;
    this.public_key = public_key;
  }
}

// build/dev/javascript/loam/loam/internal/crypto.mjs
var FILEPATH13 = "src/loam/internal/crypto.gleam";
function to_keypair(private_key, public_key) {
  let $ = exportPublicKeyDer(public_key);
  let exported;
  if ($ instanceof Ok) {
    exported = $[0];
  } else {
    throw makeError("let_assert", FILEPATH13, "loam/internal/crypto", 20, "to_keypair", "Pattern match failed, no pattern matched the value.", { value: $, start: 498, end: 559, pattern_start: 509, pattern_end: 521 });
  }
  let key_id = encode(exported);
  return new Keypair(key_id, private_key, public_key);
}
function generate_key() {
  let $ = eddsaGenerateKeyPair(Curve$Ed25519$const);
  let private_key = $[0];
  let public_key = $[1];
  return to_keypair(private_key, public_key);
}

// build/dev/javascript/loam/loam/internal/file_ffi.mjs
import fs3 from "fs";
function readAtOffset(path2, offset, limit) {
  try {
    const fd = fs3.openSync(path2, "r");
    try {
      const buffer = Buffer.alloc(limit);
      const bytesRead = fs3.readSync(fd, buffer, 0, limit, offset);
      return Result$Ok(BitArray$BitArray(buffer.subarray(0, bytesRead)));
    } finally {
      fs3.closeSync(fd);
    }
  } catch (error2) {
    return Result$Error(cast_error2(error2.code));
  }
}
function cast_error2(error_code) {
  switch (error_code) {
    case "EACCES":
      return new Eacces;
    case "EAGAIN":
      return new Eagain;
    case "EBADF":
      return new Ebadf;
    case "EBADMSG":
      return new Ebadmsg;
    case "EBUSY":
      return new Ebusy;
    case "EDEADLK":
      return new Edeadlk;
    case "EDEADLOCK":
      return new Edeadlock;
    case "EDQUOT":
      return new Edquot;
    case "EEXIST":
      return new Eexist;
    case "EFAULT":
      return new Efault;
    case "EFBIG":
      return new Efbig;
    case "EFTYPE":
      return new Eftype;
    case "EINTR":
      return new Eintr;
    case "EINVAL":
      return new Einval;
    case "EIO":
      return new Eio;
    case "EISDIR":
      return new Eisdir;
    case "ELOOP":
      return new Eloop;
    case "EMFILE":
      return new Emfile;
    case "EMLINK":
      return new Emlink;
    case "EMULTIHOP":
      return new Emultihop;
    case "ENAMETOOLONG":
      return new Enametoolong;
    case "ENFILE":
      return new Enfile;
    case "ENOBUFS":
      return new Enobufs;
    case "ENODEV":
      return new Enodev;
    case "ENOLCK":
      return new Enolck;
    case "ENOLINK":
      return new Enolink;
    case "ENOENT":
      return new Enoent;
    case "ENOMEM":
      return new Enomem;
    case "ENOSPC":
      return new Enospc;
    case "ENOSR":
      return new Enosr;
    case "ENOSTR":
      return new Enostr;
    case "ENOSYS":
      return new Enosys;
    case "ENOBLK":
      return new Enotblk;
    case "ENOTDIR":
      return new Enotdir;
    case "ENOTSUP":
      return new Enotsup;
    case "ENXIO":
      return new Enxio;
    case "EOPNOTSUPP":
      return new Eopnotsupp;
    case "EOVERFLOW":
      return new Eoverflow;
    case "EPERM":
      return new Eperm;
    case "EPIPE":
      return new Epipe;
    case "ERANGE":
      return new Erange;
    case "EROFS":
      return new Erofs;
    case "ESPIPE":
      return new Espipe;
    case "ESRCH":
      return new Esrch;
    case "ESTALE":
      return new Estale;
    case "ETXTBSY":
      return new Etxtbsy;
    case "EXDEV":
      return new Exdev;
    case "NOTUTF8":
      return new NotUtf8;
    default:
      return new Unknown2(error_code);
  }
}

// build/dev/javascript/loam/loam/system_ffi.mjs
import fs4 from "fs";
function readStdin() {
  try {
    return Result$Ok(fs4.readFileSync(0, "utf8"));
  } catch (error2) {
    return Result$Error(`failed to read stdin: ${error2.message}`);
  }
}

// build/dev/javascript/loam/loam/system.mjs
var FILEPATH14 = "src/loam/system.gleam";

class Metadata extends CustomType {
  constructor(kind, size2) {
    super();
    this.kind = kind;
    this.size = size2;
  }
}
class Done2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class AppendFileBits extends CustomType {
  constructor($0, $1, $2) {
    super();
    this[0] = $0;
    this[1] = $1;
    this[2] = $2;
  }
}
class CreateDirectory extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class Cwd2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class DeleteFile2 extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class Env3 extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class Exit2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class FileInfo2 extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class Fetch2 extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class GenerateKey extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Hash3 extends CustomType {
  constructor($0, $1, $2) {
    super();
    this[0] = $0;
    this[1] = $1;
    this[2] = $2;
  }
}
class Now2 extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Prompt extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class Random2 extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class ReadDirectory2 extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class ReadFile2 extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class ReadFileRange extends CustomType {
  constructor($0, $1, $2, $3) {
    super();
    this[0] = $0;
    this[1] = $1;
    this[2] = $2;
    this[3] = $3;
  }
}
class SetPermissions extends CustomType {
  constructor($0, $1, $2) {
    super();
    this[0] = $0;
    this[1] = $1;
    this[2] = $2;
  }
}
class Stdin extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Stdout extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class Wait extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class WriteFile2 extends CustomType {
  constructor($0, $1, $2) {
    super();
    this[0] = $0;
    this[1] = $1;
    this[2] = $2;
  }
}
class WriteFileBits extends CustomType {
  constructor($0, $1, $2) {
    super();
    this[0] = $0;
    this[1] = $1;
    this[2] = $2;
  }
}
class WriteStdout extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
class WriteStderr extends CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
function append_file_bits(path2, contents) {
  return new AppendFileBits(path2, contents, (var0) => {
    return new Done2(var0);
  });
}
function delete_file2(path2) {
  return new DeleteFile2(path2, (var0) => {
    return new Done2(var0);
  });
}
function env2(name2) {
  return new Env3(name2, (var0) => {
    return new Done2(var0);
  });
}
function file_info(path2) {
  return new FileInfo2(path2, (var0) => {
    return new Done2(var0);
  });
}
function now2() {
  return new Now2((var0) => {
    return new Done2(var0);
  });
}
function random4(max3) {
  return new Random2(max3, (var0) => {
    return new Done2(var0);
  });
}
function read_file_range(path2, offset, limit) {
  return new ReadFileRange(path2, offset, limit, (var0) => {
    return new Done2(var0);
  });
}
function write_file_bits(path2, contents) {
  return new WriteFileBits(path2, contents, (var0) => {
    return new Done2(var0);
  });
}
function write_stdout(text) {
  return new WriteStdout(text, (var0) => {
    return new Done2(var0);
  });
}
function write_stderr(text) {
  return new WriteStderr(text, (var0) => {
    return new Done2(var0);
  });
}
function wait2(milliseconds) {
  return new Wait(milliseconds, (var0) => {
    return new Done2(var0);
  });
}
function generate_key2() {
  return new GenerateKey((var0) => {
    return new Done2(var0);
  });
}
function fetch4(request2) {
  return new Fetch2(request2, (var0) => {
    return new Done2(var0);
  });
}
function create_directory(path2) {
  return new CreateDirectory(path2, (var0) => {
    return new Done2(var0);
  });
}
function cwd2() {
  return new Cwd2((var0) => {
    return new Done2(var0);
  });
}
function resolve_relative(root, relative2) {
  let _block;
  let $ = is_absolute(relative2);
  if ($) {
    _block = relative2;
  } else {
    _block = join2(root, relative2);
  }
  let joined = _block;
  let _pipe = expand(joined);
  return replace_error(_pipe, FileError$Einval$const);
}
function hash3(algorithm, bytes) {
  return new Hash3(algorithm, bytes, (var0) => {
    return new Done2(var0);
  });
}
function read_directory2(path2) {
  return new ReadDirectory2(path2, (var0) => {
    return new Done2(var0);
  });
}
function read_file2(path2) {
  return new ReadFile2(path2, (var0) => {
    return new Done2(var0);
  });
}
function stdin() {
  return new Stdin((var0) => {
    return new Done2(var0);
  });
}
function then$3(effect, func) {
  if (effect instanceof Done2) {
    let value2 = effect[0];
    return func(value2);
  } else if (effect instanceof AppendFileBits) {
    let path2 = effect[0];
    let bytes = effect[1];
    let resume3 = effect[2];
    return new AppendFileBits(path2, bytes, (result2) => {
      return then$3(resume3(result2), func);
    });
  } else if (effect instanceof CreateDirectory) {
    let path2 = effect[0];
    let resume3 = effect[1];
    return new CreateDirectory(path2, (response2) => {
      return then$3(resume3(response2), func);
    });
  } else if (effect instanceof Cwd2) {
    let resume3 = effect[0];
    return new Cwd2((response2) => {
      return then$3(resume3(response2), func);
    });
  } else if (effect instanceof DeleteFile2) {
    let path2 = effect[0];
    let resume3 = effect[1];
    return new DeleteFile2(path2, (result2) => {
      return then$3(resume3(result2), func);
    });
  } else if (effect instanceof Env3) {
    let name2 = effect[0];
    let resume3 = effect[1];
    return new Env3(name2, (value2) => {
      return then$3(resume3(value2), func);
    });
  } else if (effect instanceof Exit2) {
    return effect;
  } else if (effect instanceof FileInfo2) {
    let path2 = effect[0];
    let resume3 = effect[1];
    return new FileInfo2(path2, (result2) => {
      return then$3(resume3(result2), func);
    });
  } else if (effect instanceof Fetch2) {
    let request2 = effect[0];
    let resume3 = effect[1];
    return new Fetch2(request2, (response2) => {
      return then$3(resume3(response2), func);
    });
  } else if (effect instanceof GenerateKey) {
    let resume3 = effect[0];
    return new GenerateKey((keypair) => {
      return then$3(resume3(keypair), func);
    });
  } else if (effect instanceof Hash3) {
    let algorithm = effect[0];
    let bytes = effect[1];
    let resume3 = effect[2];
    return new Hash3(algorithm, bytes, (output) => {
      return then$3(resume3(output), func);
    });
  } else if (effect instanceof Now2) {
    let resume3 = effect[0];
    return new Now2((value2) => {
      return then$3(resume3(value2), func);
    });
  } else if (effect instanceof Prompt) {
    let text = effect[0];
    let resume3 = effect[1];
    return new Prompt(text, (value2) => {
      return then$3(resume3(value2), func);
    });
  } else if (effect instanceof Random2) {
    let max3 = effect[0];
    let resume3 = effect[1];
    return new Random2(max3, (value2) => {
      return then$3(resume3(value2), func);
    });
  } else if (effect instanceof ReadDirectory2) {
    let path2 = effect[0];
    let resume3 = effect[1];
    return new ReadDirectory2(path2, (response2) => {
      return then$3(resume3(response2), func);
    });
  } else if (effect instanceof ReadFile2) {
    let path2 = effect[0];
    let resume3 = effect[1];
    return new ReadFile2(path2, (response2) => {
      return then$3(resume3(response2), func);
    });
  } else if (effect instanceof ReadFileRange) {
    let path2 = effect[0];
    let offset = effect[1];
    let limit = effect[2];
    let resume3 = effect[3];
    return new ReadFileRange(path2, offset, limit, (result2) => {
      return then$3(resume3(result2), func);
    });
  } else if (effect instanceof SetPermissions) {
    let path2 = effect[0];
    let permissions = effect[1];
    let resume3 = effect[2];
    return new SetPermissions(path2, permissions, (response2) => {
      return then$3(resume3(response2), func);
    });
  } else if (effect instanceof Stdin) {
    let resume3 = effect[0];
    return new Stdin((response2) => {
      return then$3(resume3(response2), func);
    });
  } else if (effect instanceof Stdout) {
    let text = effect[0];
    let resume3 = effect[1];
    return new Stdout(text, (response2) => {
      return then$3(resume3(response2), func);
    });
  } else if (effect instanceof Wait) {
    let timeout = effect[0];
    let resume3 = effect[1];
    return new Wait(timeout, (response2) => {
      return then$3(resume3(response2), func);
    });
  } else if (effect instanceof WriteFile2) {
    let path2 = effect[0];
    let contents = effect[1];
    let resume3 = effect[2];
    return new WriteFile2(path2, contents, (response2) => {
      return then$3(resume3(response2), func);
    });
  } else if (effect instanceof WriteFileBits) {
    let path2 = effect[0];
    let bytes = effect[1];
    let resume3 = effect[2];
    return new WriteFileBits(path2, bytes, (result2) => {
      return then$3(resume3(result2), func);
    });
  } else if (effect instanceof WriteStdout) {
    let text = effect[0];
    let resume3 = effect[1];
    return new WriteStdout(text, (value2) => {
      return then$3(resume3(value2), func);
    });
  } else {
    let text = effect[0];
    let resume3 = effect[1];
    return new WriteStderr(text, (value2) => {
      return then$3(resume3(value2), func);
    });
  }
}
function map10(effect, func) {
  return then$3(effect, (value2) => {
    return new Done2(func(value2));
  });
}
function traverse(items, func) {
  if (items instanceof Empty) {
    return new Done2(List$Empty$const);
  } else {
    let item = items.head;
    let rest = items.tail;
    return then$3(func(item), (value2) => {
      return map10(traverse(rest, func), (values3) => {
        return prepend(value2, values3);
      });
    });
  }
}
function try$3(result2, then$4) {
  if (result2 instanceof Ok) {
    let value2 = result2[0];
    return then$4(value2);
  } else {
    let reason = result2[0];
    return new Done2(new Error2(reason));
  }
}
function do_set_permissions(path2, permissions) {
  let _pipe = setPermissionsOctal(path2, permissions);
  return map_error(_pipe, describe_error);
}
function do_write_file(path2, contents) {
  let _pipe = write(path2, contents);
  return map_error(_pipe, describe_error);
}
function format_file_error(path2, err) {
  let _block;
  if (err instanceof Eacces) {
    _block = [
      "permission denied reading: " + path2,
      "check the file is readable by the current user"
    ];
  } else if (err instanceof Eisdir) {
    _block = [
      "expected a file but found a directory: " + path2,
      "pass the path to a source file, not a directory"
    ];
  } else if (err instanceof Enoent) {
    _block = [
      "no such file: " + path2,
      "check the path and that the file exists, relative to the current working directory"
    ];
  } else {
    _block = [
      "could not read " + path2 + ": " + describe_error(err),
      "check the path is correct and readable"
    ];
  }
  let $ = _block;
  let description = $[0];
  let hint3 = $[1];
  return "error: " + description + `
hint: ` + hint3;
}
function do_read_file(file2) {
  let _pipe = read(file2);
  return map_error(_pipe, (err) => {
    return format_file_error(file2, err);
  });
}
function do_hash(algorithm, bytes) {
  let _block;
  if (algorithm instanceof Sha1) {
    _block = HashAlgorithm$Sha1$const3;
  } else if (algorithm instanceof Sha2562) {
    _block = HashAlgorithm$Sha256$const3;
  } else if (algorithm instanceof Sha384) {
    _block = HashAlgorithm$Sha384$const3;
  } else {
    _block = HashAlgorithm$Sha512$const3;
  }
  let algorithm$1 = _block;
  return hash2(algorithm$1, bytes);
}
function do_cwd() {
  let _pipe = currentDirectory();
  return map_error(_pipe, describe_error);
}
function do_create_directory(path2) {
  let _pipe = create_directory_all(path2);
  return map_error(_pipe, describe_error);
}
function do_fetch(request2) {
  return map_promise(send_bits2(request2), (response2) => {
    return map_error(response2, (reason) => {
      if (reason instanceof NetworkError2) {
        let reason$1 = reason[0];
        return new NetworkError(reason$1);
      } else if (reason instanceof UnableToReadBody2) {
        return FetchError$UnableToReadBody$const;
      } else {
        return FetchError$UnableToReadBody$const;
      }
    });
  });
}
function run2(loop$effect) {
  while (true) {
    let effect = loop$effect;
    if (effect instanceof Done2) {
      let value2 = effect[0];
      return resolve2(value2);
    } else if (effect instanceof AppendFileBits) {
      let path2 = effect[0];
      let bytes = effect[1];
      let resume3 = effect[2];
      loop$effect = resume3(appendBits(path2, bytes));
    } else if (effect instanceof CreateDirectory) {
      let path2 = effect[0];
      let resume3 = effect[1];
      loop$effect = resume3(do_create_directory(path2));
    } else if (effect instanceof Cwd2) {
      let resume3 = effect[0];
      loop$effect = resume3(do_cwd());
    } else if (effect instanceof DeleteFile2) {
      let path2 = effect[0];
      let resume3 = effect[1];
      loop$effect = resume3(delete_(path2));
    } else if (effect instanceof Env3) {
      let name2 = effect[0];
      let resume3 = effect[1];
      loop$effect = resume3((() => {
        let _pipe = get3(name2);
        return from_result(_pipe);
      })());
    } else if (effect instanceof Exit2) {
      let status = effect[0];
      os_exit(status);
      throw makeError("panic", FILEPATH14, "loam/system", 294, "run", "the process did not stop", {});
    } else if (effect instanceof FileInfo2) {
      let path2 = effect[0];
      let resume3 = effect[1];
      let _block;
      let _pipe = fileInfo(path2);
      _block = map4(_pipe, (info) => {
        return new Metadata(file_info_type(info), info.size);
      });
      let result2 = _block;
      loop$effect = resume3(result2);
    } else if (effect instanceof Fetch2) {
      let request2 = effect[0];
      let resume3 = effect[1];
      return then_await(do_fetch(request2), (response2) => {
        return run2(resume3(response2));
      });
    } else if (effect instanceof GenerateKey) {
      let resume3 = effect[0];
      loop$effect = resume3(generate_key());
    } else if (effect instanceof Hash3) {
      let algorithm = effect[0];
      let bytes = effect[1];
      let resume3 = effect[2];
      loop$effect = resume3(do_hash(algorithm, bytes));
    } else if (effect instanceof Now2) {
      let resume3 = effect[0];
      let _block;
      let _pipe = system_time2();
      _block = to_unix_seconds_and_nanoseconds(_pipe);
      let $ = _block;
      let seconds2 = $[0];
      let nanos = $[1];
      loop$effect = resume3(seconds2 * 1000 + globalThis.Math.trunc(nanos / 1e6));
    } else if (effect instanceof Prompt) {
      let text = effect[0];
      let resume3 = effect[1];
      loop$effect = resume3(input(text));
    } else if (effect instanceof Random2) {
      let max3 = effect[0];
      let resume3 = effect[1];
      loop$effect = resume3(random(max3));
    } else if (effect instanceof ReadDirectory2) {
      let path2 = effect[0];
      let resume3 = effect[1];
      loop$effect = resume3(readDirectory(path2));
    } else if (effect instanceof ReadFile2) {
      let path2 = effect[0];
      let resume3 = effect[1];
      loop$effect = resume3(do_read_file(path2));
    } else if (effect instanceof ReadFileRange) {
      let path2 = effect[0];
      let offset = effect[1];
      let limit = effect[2];
      let resume3 = effect[3];
      let _block;
      let $ = offset < 0 || limit < 0;
      if ($) {
        _block = new Error2(FileError$Einval$const);
      } else {
        _block = readAtOffset(path2, offset, limit);
      }
      let result2 = _block;
      loop$effect = resume3(result2);
    } else if (effect instanceof SetPermissions) {
      let path2 = effect[0];
      let permissions = effect[1];
      let resume3 = effect[2];
      loop$effect = resume3(do_set_permissions(path2, permissions));
    } else if (effect instanceof Stdin) {
      let resume3 = effect[0];
      loop$effect = resume3(readStdin());
    } else if (effect instanceof Stdout) {
      let text = effect[0];
      let resume3 = effect[1];
      loop$effect = resume3(console_log(text));
    } else if (effect instanceof Wait) {
      let duration = effect[0];
      let resume3 = effect[1];
      return then_await(wait(duration), (response2) => {
        return run2(resume3(response2));
      });
    } else if (effect instanceof WriteFile2) {
      let path2 = effect[0];
      let contents = effect[1];
      let resume3 = effect[2];
      loop$effect = resume3(do_write_file(path2, contents));
    } else if (effect instanceof WriteFileBits) {
      let path2 = effect[0];
      let bytes = effect[1];
      let resume3 = effect[2];
      loop$effect = resume3(writeBits(path2, bytes));
    } else if (effect instanceof WriteStdout) {
      let text = effect[0];
      let resume3 = effect[1];
      loop$effect = resume3(print(text));
    } else {
      let text = effect[0];
      let resume3 = effect[1];
      loop$effect = resume3(print_error(text));
    }
  }
}

// build/dev/javascript/loam/loam/source.mjs
class File3 extends CustomType {
  constructor(path2) {
    super();
    this.path = path2;
  }
}
class Code extends CustomType {
  constructor(code3) {
    super();
    this.code = code3;
  }
}
class Stdin2 extends CustomType {
}
var Input$Stdin$const = new Stdin2;
class Disk extends CustomType {
  constructor(path2) {
    super();
    this.path = path2;
  }
}
class Pipe extends CustomType {
}
var Origin$Pipe$const = new Pipe;
class Inline extends CustomType {
}
var Origin$Inline$const = new Inline;
class Repl extends CustomType {
}
var Origin$Repl$const = new Repl;
class Content3 extends CustomType {
  constructor(cid2) {
    super();
    this.cid = cid2;
  }
}
class Release3 extends CustomType {
  constructor(package$2, version, cid2) {
    super();
    this.package = package$2;
    this.version = version;
    this.cid = cid2;
  }
}
class Location extends CustomType {
  constructor(origin, source) {
    super();
    this.origin = origin;
    this.source = source;
  }
}
class Text3 extends CustomType {
  constructor(code3, span) {
    super();
    this.code = code3;
    this.span = span;
  }
}
class Json extends CustomType {
}
var Source$Json$const = new Json;
function strip_shebang(code3) {
  let $ = starts_with(code3, "#!");
  if ($) {
    let $1 = split_once(code3, `
`);
    if ($1 instanceof Ok) {
      let rest = $1[0][1];
      return rest;
    } else {
      return "";
    }
  } else {
    return code3;
  }
}
function read_input(input2) {
  if (input2 instanceof File3) {
    let path2 = input2.path;
    return map10(read_file2(path2), (code3) => {
      return map4(code3, strip_shebang);
    });
  } else if (input2 instanceof Code) {
    let code$1 = input2.code;
    return new Done2(new Ok(code$1));
  } else {
    return stdin();
  }
}
function parse5(code3, origin) {
  let $ = parse(code3, decoder(new Location(origin, Source$Json$const)));
  if ($ instanceof Ok) {
    return $;
  } else {
    let $1 = all_from_string(code3);
    if ($1 instanceof Ok) {
      let source = $1[0];
      let source$1 = map_annotation(source, (span) => {
        return new Location(origin, new Text3(code3, span));
      });
      return new Ok(source$1);
    } else {
      let reason = $1[0];
      return new Error2(format_error(reason, code3));
    }
  }
}
function input_origin(input2) {
  if (input2 instanceof File3) {
    let path2 = input2.path;
    return new Disk(path2);
  } else if (input2 instanceof Code) {
    return Origin$Inline$const;
  } else {
    return Origin$Pipe$const;
  }
}
function parse_input(code3, input2) {
  let origin = input_origin(input2);
  return parse5(code3, origin);
}
function resolved_path(root, path2) {
  let _pipe = resolve_relative(root, path2);
  let _pipe$1 = replace_error(_pipe, "invalid relative path outside filesystem");
  return new Done2(_pipe$1);
}
function resolve_filepath(from3, path2) {
  let $ = is_absolute(path2);
  if ($) {
    return resolved_path("", path2);
  } else if (from3 instanceof Disk) {
    let source_path = from3.path;
    return resolved_path(directory_name(source_path), path2);
  } else if (from3 instanceof Pipe) {
    return then$3(cwd2(), (cwd3) => {
      return try$3(cwd3, (cwd4) => {
        return resolved_path(cwd4, path2);
      });
    });
  } else if (from3 instanceof Inline) {
    return then$3(cwd2(), (cwd3) => {
      return try$3(cwd3, (cwd4) => {
        return resolved_path(cwd4, path2);
      });
    });
  } else if (from3 instanceof Repl) {
    return then$3(cwd2(), (cwd3) => {
      return try$3(cwd3, (cwd4) => {
        return resolved_path(cwd4, path2);
      });
    });
  } else {
    return new Done2(new Error2('relative path "' + path2 + '" requires a disk-backed source; use CWD or an absolute path'));
  }
}

// build/dev/javascript/loam/loam/platform/computer.mjs
function cast2(label31, lift30) {
  return cast(effects(), label31, lift30);
}
function effects2() {
  return effects();
}
function write_file2(origin, input2) {
  let path2 = input2.path;
  let contents = input2.contents;
  return then$3(resolve_filepath(origin, path2), (path3) => {
    return try$3(path3, (path4) => {
      return map10(write_file_bits(path4, contents), (result2) => {
        return map_error(result2, describe_error);
      });
    });
  });
}
function sign2(request2) {
  let private_key = request2.private_key;
  let data = request2.data;
  let $ = eddsaPrivateKeyFromBytes(Curve$Ed25519$const, private_key);
  if ($ instanceof Ok) {
    let key3 = $[0][0];
    return new Ok(eddsaSign(key3, data));
  } else {
    return new Error2("invalid Ed25519 private key");
  }
}
function read_file3(origin, input2) {
  let path2 = input2.path;
  let offset = input2.offset;
  let limit = input2.limit;
  return then$3(resolve_filepath(origin, path2), (path3) => {
    return try$3(path3, (path4) => {
      return map10(read_file_range(path4, offset, limit), (contents) => {
        return map_error(contents, describe_error);
      });
    });
  });
}
function read_directory3(origin, path2) {
  return then$3(resolve_filepath(origin, path2), (path3) => {
    return try$3(path3, (path4) => {
      return then$3(read_directory2(path4), (children) => {
        return try$3(map_error(children, describe_error), (children2) => {
          return map10(traverse(children2, (child) => {
            return map10(file_info(join2(path4, child)), (info) => {
              if (info instanceof Ok) {
                let $ = info[0].kind;
                if ($ instanceof File) {
                  let size2 = info[0].size;
                  return new Ok([child, new File2(size2)]);
                } else if ($ instanceof Directory) {
                  return new Ok([child, Entry$Directory$const]);
                } else {
                  return new Error2(undefined);
                }
              } else {
                return new Error2(undefined);
              }
            });
          }), (entries) => {
            let _pipe = entries;
            let _pipe$1 = filter_map(_pipe, (entry2) => {
              return entry2;
            });
            let _pipe$2 = sort(_pipe$1, (a, b) => {
              return compare2(a[0], b[0]);
            });
            return new Ok(_pipe$2);
          });
        });
      });
    });
  });
}
function make_directory2(origin, path2) {
  return then$3(resolve_filepath(origin, path2), (path3) => {
    return try$3(path3, (path4) => {
      return create_directory(path4);
    });
  });
}
function delete_file3(origin, path2) {
  return then$3(resolve_filepath(origin, path2), (path3) => {
    return try$3(path3, (path4) => {
      return map10(delete_file2(path4), (result2) => {
        return map_error(result2, describe_error);
      });
    });
  });
}
function create_key2(request2) {
  return map10(generate_key2(), (keys2) => {
    return new Ok(new EddsaKey(eddsaPublicKeyToBytes(keys2.public_key), eddsaPrivateKeyToBytes(keys2.private_key)));
  });
}
function append_file2(origin, input2) {
  let path2 = input2.path;
  let contents = input2.contents;
  return then$3(resolve_filepath(origin, path2), (path3) => {
    return try$3(path3, (path4) => {
      return map10(append_file_bits(path4, contents), (result2) => {
        return map_error(result2, describe_error);
      });
    });
  });
}
function extrinsic(effect, origin) {
  if (effect instanceof AppendFile) {
    let input2 = effect[0];
    return map10(append_file2(origin, input2), encode13);
  } else if (effect instanceof CreateKey) {
    let request2 = effect[0];
    return map10(create_key2(request2), encode6);
  } else if (effect instanceof Cwd) {
    return map10(cwd2(), encode14);
  } else if (effect instanceof DecodeJson) {
    let encoded = effect[0];
    return new Done2(sync(encoded));
  } else if (effect instanceof DeleteFile) {
    let path2 = effect.path;
    return map10(delete_file3(origin, path2), encode15);
  } else if (effect instanceof Env2) {
    let name2 = effect.name;
    return map10(env2(name2), encode10);
  } else if (effect instanceof Exit) {
    let status = effect.status;
    return new Exit2(status);
  } else if (effect instanceof EygParse) {
    let code3 = effect.source;
    return new Done2((() => {
      let _pipe = parse5(code3, origin);
      return encode11(_pipe);
    })());
  } else if (effect instanceof Fetch) {
    let request2 = effect[0];
    return map10(fetch4(request2), (response2) => {
      let _pipe = response2;
      let _pipe$1 = map_error(_pipe, inspect2);
      return encode12(_pipe$1);
    });
  } else if (effect instanceof Flip) {
    return map10(random4(2), (value2) => {
      return encode20(is_even(value2));
    });
  } else if (effect instanceof Hash) {
    let input2 = effect[0];
    let bytes;
    bytes = input2.bytes;
    return map10(hash3(HashAlgorithm$Sha256$const, bytes), encode7);
  } else if (effect instanceof MakeDirectory) {
    let path2 = effect.path;
    return map10(make_directory2(origin, path2), encode16);
  } else if (effect instanceof Now) {
    return map10(now2(), encode21);
  } else if (effect instanceof Random) {
    let max3 = effect[0];
    return map10(random4(max3), encode22);
  } else if (effect instanceof ReadDirectory) {
    let path2 = effect.path;
    return map10(read_directory3(origin, path2), encode17);
  } else if (effect instanceof ReadFile) {
    let input2 = effect[0];
    return map10(read_file3(origin, input2), encode18);
  } else if (effect instanceof Sign) {
    let request2 = effect[0];
    return new Done2((() => {
      let _pipe = sign2(request2);
      return encode8(_pipe);
    })());
  } else if (effect instanceof Sleep) {
    let milliseconds = effect[0];
    return map10(wait2(milliseconds), encode23);
  } else if (effect instanceof StandardError) {
    let text = effect[0];
    return map10(write_stderr(text), encode24);
  } else if (effect instanceof StandardIn) {
    return map10(stdin(), (input2) => {
      let _pipe = input2;
      let _pipe$1 = map4(_pipe, bit_array_from_string);
      return encode25(_pipe$1);
    });
  } else if (effect instanceof StanardOut) {
    let text = effect[0];
    return map10(write_stdout(text), encode26);
  } else {
    let input2 = effect[0];
    return map10(write_file2(origin, input2), encode19);
  }
}

// build/dev/javascript/loam/loam/execute.mjs
class State extends CustomType {
  constructor(origin, cache) {
    super();
    this.origin = origin;
    this.cache = cache;
  }
}
class Frame extends CustomType {
  constructor(location, arg) {
    super();
    this.location = location;
    this.arg = arg;
  }
}
function abort(reason) {
  return new UnhandledEffect("Abort", new String4(reason));
}
function try_await2(result2, meta, env3, k, then$4) {
  return then$3(result2, (_use0) => {
    let result$1 = _use0[0];
    let state = _use0[1];
    if (result$1 instanceof Ok) {
      let value2 = result$1[0];
      return then$4(value2, state);
    } else {
      let reason = result$1[0];
      return new Done2([new Error2([reason, meta, env3, k]), state]);
    }
  });
}
function apply2(cache, update2) {
  if (update2 instanceof FetchModuleCompleted) {
    let cid2 = update2[0];
    let $ = update(cache, update2, (_) => {
      return new Location(new Content3(cid2), Source$Json$const);
    });
    let cache$1 = $[0];
    return cache$1;
  } else {
    let result2 = update2[0];
    let $ = pull_packages_completed(cache, result2);
    let cache$1 = $[0];
    return cache$1;
  }
}
function do_effect(action, state) {
  return compute(action, state.origin, (request2) => {
    return (_capture) => {
      return new Fetch2(request2, _capture);
    };
  }, (algorithm, bytes) => {
    return (_capture) => {
      return new Hash3(algorithm, bytes, _capture);
    };
  })((var0) => {
    return new Done2(var0);
  });
}
function update2(state) {
  let $ = flush(state.cache);
  let cache = $[0];
  let effects3 = $[1];
  if (effects3 instanceof Empty) {
    return new Done2(new State(state.origin, cache));
  } else {
    return then$3(traverse(effects3, (_capture) => {
      return do_effect(_capture, state);
    }), (applicable) => {
      let cache$1 = fold2(applicable, cache, apply2);
      return update2(new State(state.origin, cache$1));
    });
  }
}
function lookup_reference(cid2, state) {
  let cache = fetch2(state.cache, cid2);
  return map10(update2(new State(state.origin, cache)), (state2) => {
    let _block;
    let $ = module(state2.cache, cid2);
    if ($ instanceof Available) {
      let module2 = $[0];
      _block = new Ok(module2);
    } else if ($ instanceof Unknown) {
      let _pipe = abort("failed to load module #" + to_string2(cid2) + " (the module itself or one of its dependencies could not be fetched from " + "$EYG_ORIGIN)");
      _block = new Error2(_pipe);
    } else {
      let reason = $[0];
      _block = new Error2(reason);
    }
    let result2 = _block;
    return [result2, state2];
  });
}
function lookup_pinned(release2, state) {
  let cache = pull(state.cache);
  return then$3(update2(new State(state.origin, cache)), (state2) => {
    let $ = release(state2.cache, release2);
    if ($ instanceof Available) {
      let resolved = $[0];
      return lookup_reference(resolved, state2);
    } else if ($ instanceof Unknown) {
      return new Done2([
        new Error2(abort("module not found for package: @" + release2.package)),
        state2
      ]);
    } else {
      return new Done2([
        new Error2(new UndefinedReference(new Pinned(release2))),
        state2
      ]);
    }
  });
}
function take_value(in$) {
  return map10(in$, (_use0) => {
    let result2 = _use0[0];
    let state = _use0[1];
    return [map4(result2, (module2) => {
      return module2.value;
    }), state];
  });
}
function lookup_version(package$2, version, state) {
  let cache = pull(state.cache);
  return then$3(update2(new State(state.origin, cache)), (state2) => {
    let $ = unbound_release(state2.cache, package$2, version);
    if ($ instanceof Ok) {
      let module2 = $[0];
      return lookup_reference(module2, state2);
    } else {
      return new Done2([
        new Error2(new UndefinedReference(new Version(package$2, version))),
        state2
      ]);
    }
  });
}
function lookup_package(package$2, state) {
  let cache = pull(state.cache);
  return then$3(update2(new State(state.origin, cache)), (state2) => {
    let $ = package$(state2.cache, package$2);
    if ($ instanceof Ok) {
      let module2 = $[0].module;
      return lookup_reference(module2, state2);
    } else {
      return new Done2([
        new Error2(new UndefinedReference(new Package(package$2))),
        state2
      ]);
    }
  });
}
function pure_loop(return$2, state) {
  if (return$2 instanceof Ok) {
    let return$1 = return$2[0];
    return new Done2([new Ok(return$1), state]);
  } else {
    let reason = return$2[0][0];
    let meta = return$2[0][1];
    let env3 = return$2[0][2];
    let k = return$2[0][3];
    if (reason instanceof UndefinedReference) {
      let reference2 = reason[0];
      return try_await2(lookup2(reference2, meta.origin, state), meta, env3, k, (value2, state2) => {
        return pure_loop(resume(value2, env3, k), state2);
      });
    } else {
      return new Done2([new Error2([reason, meta, env3, k]), state]);
    }
  }
}
function lookup_relative(location, origin, state) {
  return then$3(resolve_filepath(origin, location), (resolved) => {
    if (resolved instanceof Ok) {
      let path2 = resolved[0];
      return then$3(read_file2(path2), (code3) => {
        if (code3 instanceof Ok) {
          let code$1 = code3[0];
          let $ = parse5(code$1, new Disk(path2));
          if ($ instanceof Ok) {
            let source = $[0];
            return then$3(pure_loop(execute(source, List$Empty$const), state), (_use0) => {
              let result2 = _use0[0];
              let state$1 = _use0[1];
              if (result2 instanceof Ok) {
                let value2 = result2[0];
                return new Done2([new Ok(value2), state$1]);
              } else {
                let reason = result2[0][0];
                return new Done2([new Error2(reason), state$1]);
              }
            });
          } else {
            let reason = $[0];
            return new Done2([
              new Error2(abort("failed to parse source from location: " + location + " " + replace(reason, `
`, " "))),
              state
            ]);
          }
        } else {
          return new Done2([
            new Error2(abort("failed to read module from location: " + location)),
            state
          ]);
        }
      });
    } else {
      return new Done2([
        new Error2(new UndefinedReference(new Relative(location))),
        state
      ]);
    }
  });
}
function lookup2(reference2, origin, state) {
  if (reference2 instanceof Content) {
    let cid2 = reference2.cid;
    return take_value(lookup_reference(cid2, state));
  } else if (reference2 instanceof Package) {
    let package$2 = reference2.package;
    return take_value(lookup_package(package$2, state));
  } else if (reference2 instanceof Version) {
    let package$2 = reference2.package;
    let version = reference2.version;
    return take_value(lookup_version(package$2, version, state));
  } else if (reference2 instanceof Pinned) {
    let release2 = reference2.release;
    return take_value(lookup_pinned(release2, state));
  } else {
    let location = reference2.location;
    return lookup_relative(location, origin, state);
  }
}
function loop5(return$2, state) {
  if (return$2 instanceof Ok) {
    let return$1 = return$2[0];
    return new Done2([new Ok(return$1), state]);
  } else {
    let reason = return$2[0][0];
    let meta = return$2[0][1];
    let env3 = return$2[0][2];
    let k = return$2[0][3];
    if (reason instanceof UndefinedReference) {
      let reference2 = reason[0];
      return try_await2(lookup2(reference2, meta.origin, state), meta, env3, k, (value2, state2) => {
        return loop5(resume2(value2, env3, k), state2);
      });
    } else if (reason instanceof UnhandledEffect) {
      let label31 = reason[0];
      let lift30 = reason[1];
      let $ = cast2(label31, lift30);
      if ($ instanceof Ok) {
        let effect = $[0];
        return then$3(extrinsic(effect, meta.origin), (value2) => {
          return loop5(resume2(value2, env3, k), state);
        });
      } else {
        let reason$1 = $[0];
        return new Done2([new Error2([reason$1, meta, env3, k]), state]);
      }
    } else {
      return new Done2([new Error2([reason, meta, env3, k]), state]);
    }
  }
}
function block2(source, scope, state) {
  return loop5(execute2(source, scope), state);
}
function line_at(code3, offset) {
  if (code3 === "") {
    return 0;
  } else {
    let _pipe = slice(code3, 0, offset);
    let _pipe$1 = split2(_pipe, `
`);
    return length2(_pipe$1);
  }
}
function origin_label(origin, cwd3) {
  if (origin instanceof Disk) {
    let path2 = origin.path;
    return replace(path2, cwd3 + "/", "");
  } else if (origin instanceof Pipe) {
    return "<pipe>";
  } else if (origin instanceof Inline) {
    return "<inline>";
  } else if (origin instanceof Repl) {
    return "<repl>";
  } else if (origin instanceof Content3) {
    let cid2 = origin.cid;
    return "#" + to_string2(cid2);
  } else {
    let package$2 = origin.package;
    let version = origin.version;
    return "@" + package$2 + ":" + to_string(version);
  }
}
function render_frame(frame, is_focus, cwd3) {
  let origin;
  let source;
  let arg;
  arg = frame.arg;
  origin = frame.location.origin;
  source = frame.location.source;
  let label31 = origin_label(origin, cwd3);
  let _block;
  if (is_focus) {
    _block = "\u2192 in ";
  } else {
    _block = "  in ";
  }
  let prefix = _block;
  let _block$1;
  if (arg instanceof Some) {
    let value2 = arg[0];
    _block$1 = " (" + inspect3(value2) + ")";
  } else {
    _block$1 = "";
  }
  let suffix = _block$1;
  if (source instanceof Text3) {
    let code3 = source.code;
    let span = source.span;
    let start = span[0];
    let line_no = line_at(code3, start);
    let _block$2;
    if (line_no === 0) {
      _block$2 = prefix + label31 + suffix;
    } else {
      let n = line_no;
      _block$2 = prefix + label31 + ":" + to_string(n) + suffix;
    }
    let header = _block$2;
    if (is_focus) {
      return prepend(header, source_context(code3, span));
    } else {
      return prepend(header, List$Empty$const);
    }
  } else {
    if (is_focus) {
      return prepend(prefix + label31 + " (no source)" + suffix, List$Empty$const);
    } else {
      return prepend(prefix + label31 + suffix, List$Empty$const);
    }
  }
}
function render_frames(loop$frames, loop$focus, loop$i, loop$cwd, loop$acc) {
  while (true) {
    let frames = loop$frames;
    let focus = loop$focus;
    let i = loop$i;
    let cwd3 = loop$cwd;
    let acc = loop$acc;
    if (frames instanceof Empty) {
      return reverse(acc);
    } else {
      let frame = frames.head;
      let rest = frames.tail;
      let is_focus = isEqual(focus, new Some(i));
      let lines = render_frame(frame, is_focus, cwd3);
      loop$frames = rest;
      loop$focus = focus;
      loop$i = i + 1;
      loop$cwd = cwd3;
      loop$acc = fold2(lines, acc, (acc2, line) => {
        return prepend(line, acc2);
      });
    }
  }
}
function find_focus(loop$frames, loop$i) {
  while (true) {
    let frames = loop$frames;
    let i = loop$i;
    if (frames instanceof Empty) {
      return Option$None$const;
    } else {
      let rest = frames.tail;
      let origin = frames.head.location.origin;
      if (origin instanceof Content3) {
        loop$frames = rest;
        loop$i = i + 1;
      } else if (origin instanceof Release3) {
        loop$frames = rest;
        loop$i = i + 1;
      } else {
        return new Some(i);
      }
    }
  }
}
function collect_traces(loop$stack, loop$acc) {
  while (true) {
    let stack = loop$stack;
    let acc = loop$acc;
    if (stack instanceof Stack) {
      let $ = stack[0];
      if ($ instanceof Trace) {
        let meta = stack[1];
        let rest = stack[2];
        let arg = $[0];
        loop$stack = rest;
        loop$acc = prepend(new Frame(meta, new Some(arg)), acc);
      } else {
        let rest = stack[2];
        loop$stack = rest;
        loop$acc = acc;
      }
    } else {
      return reverse(acc);
    }
  }
}
function render_error2(reason, location, stack, cwd3) {
  let frames = prepend(new Frame(location, Option$None$const), collect_traces(stack, List$Empty$const));
  let description = describe(reason);
  let hint3 = hint(reason);
  let header = prepend("error: " + description, prepend("hint: " + hint3, List$Empty$const));
  let focus = find_focus(frames, 0);
  let trace_lines = render_frames(frames, focus, 0, cwd3, List$Empty$const);
  if (trace_lines instanceof Empty) {
    return join(header, `
`);
  } else {
    return join(append3(header, prepend("", trace_lines)), `
`);
  }
}

// build/dev/javascript/eyg_analysis/eyg/analysis/type_/binding/debug.mjs
var default_width2 = 80;
function wrap2(open2, inner, close2) {
  let _pipe = concat4(prepend(from_string2(open2), prepend((() => {
    let _pipe2 = soft_break;
    let _pipe$1 = append5(_pipe2, inner);
    return nest(_pipe$1, 2);
  })(), prepend(soft_break, prepend(from_string2(close2), List$Empty$const)))));
  return group2(_pipe);
}
function separated2(items, open2, close2) {
  if (items instanceof Empty) {
    return from_string2(open2 + close2);
  } else {
    let separator2 = break$(", ", ",");
    let body = join3(items, separator2);
    let _block;
    let _pipe = soft_break;
    let _pipe$1 = append5(_pipe, body);
    _block = nest(_pipe$1, 2);
    let inner = _block;
    let _pipe$2 = concat4(prepend(from_string2(open2), prepend(inner, prepend(break$("", ","), prepend(from_string2(close2), List$Empty$const)))));
    return group2(_pipe$2);
  }
}
function row_docs(r) {
  if (r instanceof Var) {
    let i = r.key;
    return prepend(from_string2(append("..", to_string(i))), List$Empty$const);
  } else if (r instanceof Empty3) {
    return List$Empty$const;
  } else if (r instanceof RowExtend) {
    let label31 = r[0];
    let value2 = r[1];
    let tail = r[2];
    let _block;
    let _pipe = from_string2(label31 + ": ");
    _block = append5(_pipe, to_doc2(value2));
    let field3 = _block;
    return prepend(field3, row_docs(tail));
  } else {
    return prepend(from_string2("not a valid row"), prepend(from_string2(inspect2(r)), List$Empty$const));
  }
}
function effect_doc(label31, lift30, resume3) {
  return concat4(prepend(from_string2(label31 + "(\u2191"), prepend(to_doc2(lift30), prepend(from_string2(" \u2193"), prepend(to_doc2(resume3), prepend(from_string2(")"), List$Empty$const))))));
}
function collect_effect(loop$eff, loop$acc) {
  while (true) {
    let eff = loop$eff;
    let acc = loop$acc;
    if (eff instanceof Var) {
      let i = eff.key;
      return prepend(from_string2(append("..", to_string(i))), acc);
    } else if (eff instanceof Empty3) {
      return acc;
    } else if (eff instanceof EffectExtend) {
      let label31 = eff[0];
      let tail = eff[2];
      let lift30 = eff[1][0];
      let resume3 = eff[1][1];
      loop$eff = tail;
      loop$acc = prepend(effect_doc(label31, lift30, resume3), acc);
    } else {
      console_log("unexpected effect");
      return acc;
    }
  }
}
function effects_doc(effects3) {
  if (effects3 instanceof Var) {
    let i = effects3.key;
    return from_string2(".." + to_string(i));
  } else if (effects3 instanceof Empty3) {
    return from_string2("");
  } else if (effects3 instanceof EffectExtend) {
    let label31 = effects3[0];
    let tail = effects3[2];
    let lift30 = effects3[1][0];
    let resume3 = effects3[1][1];
    let _pipe = collect_effect(tail, prepend(effect_doc(label31, lift30, resume3), List$Empty$const));
    let _pipe$1 = reverse(_pipe);
    return join3(_pipe$1, break$(", ", ","));
  } else {
    return from_string2("not a valid effect");
  }
}
function argument_doc(arg) {
  let arg$1 = arg[0];
  let eff = arg[1];
  if (eff instanceof Empty3) {
    return to_doc2(arg$1);
  } else {
    let _pipe = to_doc2(arg$1);
    let _pipe$1 = append5(_pipe, space);
    return append5(_pipe$1, wrap2("<", effects_doc(eff), ">"));
  }
}
function function_doc(loop$to, loop$acc) {
  while (true) {
    let to2 = loop$to;
    let acc = loop$acc;
    if (to2 instanceof Fun) {
      let from3 = to2[0];
      let eff = to2[1];
      let to$1 = to2[2];
      loop$to = to$1;
      loop$acc = prepend([from3, eff], acc);
    } else {
      let args = reverse(acc);
      let rendered = map2(args, argument_doc);
      let _pipe = separated2(rendered, "(", ")");
      let _pipe$1 = append5(_pipe, from_string2(" -> "));
      return append5(_pipe$1, to_doc2(to2));
    }
  }
}
function to_doc2(typ) {
  if (typ instanceof Var) {
    let i = typ.key;
    return from_string2(to_string(i));
  } else if (typ instanceof Fun) {
    let from3 = typ[0];
    let eff = typ[1];
    let to2 = typ[2];
    return function_doc(to2, prepend([from3, eff], List$Empty$const));
  } else if (typ instanceof Binary2) {
    return from_string2("Binary");
  } else if (typ instanceof Integer2) {
    return from_string2("Integer");
  } else if (typ instanceof String3) {
    return from_string2("String");
  } else if (typ instanceof List2) {
    let el = typ[0];
    return wrap2("List(", to_doc2(el), ")");
  } else if (typ instanceof Record) {
    let row = typ[0];
    return separated2(row_docs(row), "{", "}");
  } else if (typ instanceof Union) {
    let row = typ[0];
    return wrap2("[", (() => {
      let _pipe = row_docs(row);
      return join3(_pipe, break$(" | ", " |"));
    })(), "]");
  } else if (typ instanceof EffectExtend) {
    return wrap2("<", effects_doc(typ), ">");
  } else if (typ instanceof Never) {
    return from_string2("Never");
  } else if (typ instanceof Promise2) {
    let inner = typ[0];
    return wrap2("Promise(", to_doc2(inner), ")");
  } else {
    let row = typ;
    return wrap2("{", (() => {
      let _pipe = row_docs(row);
      return join3(_pipe, from_string2(""));
    })(), "}");
  }
}
function render_effect(label31, lift30, resume3) {
  let _pipe = effect_doc(label31, lift30, resume3);
  return to_string6(_pipe, default_width2);
}
// build/dev/javascript/oas_generator_utils/oas/generator/utils.mjs
class Null2 extends CustomType {
}
var Any$Null$const = new Null2;
// build/dev/javascript/castor/castor.mjs
class AlwaysPasses extends CustomType {
}
var Schema$AlwaysPasses$const = new AlwaysPasses;
class AlwaysFails extends CustomType {
}
var Schema$AlwaysFails$const = new AlwaysFails;
// build/dev/javascript/overlay/overlay/agent.mjs
class UnknownTool extends CustomType {
}
var CastFailure$UnknownTool$const = new UnknownTool;
function describe_effect(effect) {
  let name2 = effect.name;
  let lift_type = effect.lift_type;
  let lower_type = effect.lower_type;
  return render_effect(name2, lift_type, lower_type);
}
function inspect_result(value2) {
  if (value2 instanceof String4) {
    let text = value2.value;
    return text;
  } else {
    return inspect3(value2);
  }
}
// build/dev/javascript/opencode_plugin/opencode_plugin_ffi.mjs
function object4(entries) {
  return Object.fromEntries(entries.toArray());
}
function array3(items) {
  return items.toArray();
}
function identity3(x) {
  return x;
}
function nil2() {
  return null;
}
function is_nullish(x) {
  return x === null || x === undefined;
}
async function call_host(handler, input2, raw) {
  try {
    return new Ok(await handler(input2, raw));
  } catch (error2) {
    return new Error2(error2 instanceof globalThis.Error ? error2.message : String(error2));
  }
}

// build/dev/javascript/opencode_plugin/opencode_plugin/convert.mjs
function to_js(loop$value) {
  while (true) {
    let value2 = loop$value;
    if (value2 instanceof Binary3) {
      let bytes = value2.value;
      return identity3(bytes);
    } else if (value2 instanceof Integer3) {
      let i = value2.value;
      return identity3(i);
    } else if (value2 instanceof String4) {
      let s = value2.value;
      return identity3(s);
    } else if (value2 instanceof LinkedList) {
      let items = value2.elements;
      return array3(map2(items, to_js));
    } else if (value2 instanceof Record2) {
      let fields = value2.fields;
      let _pipe = fields;
      let _pipe$1 = to_list(_pipe);
      let _pipe$2 = map2(_pipe$1, (field4) => {
        return [field4[0], to_js(field4[1])];
      });
      return object4(_pipe$2);
    } else if (value2 instanceof Tagged) {
      let $ = value2.value;
      if ($ instanceof Record2) {
        let $1 = value2.label;
        if ($1 === "True") {
          return identity3(true);
        } else if ($1 === "False") {
          return identity3(false);
        } else if ($1 === "None") {
          return nil2();
        } else if ($1 === "Some") {
          let inner = $;
          loop$value = inner;
        } else {
          let label31 = $1;
          let inner = $;
          return object4(prepend([label31, to_js(inner)], List$Empty$const));
        }
      } else {
        let $1 = value2.label;
        if ($1 === "Some") {
          let inner = $;
          loop$value = inner;
        } else {
          let label31 = $1;
          let inner = $;
          return object4(prepend([label31, to_js(inner)], List$Empty$const));
        }
      }
    } else if (value2 instanceof Closure) {
      return nil2();
    } else {
      return nil2();
    }
  }
}
function decoder3() {
  return one_of((() => {
    let _pipe = int2;
    return map3(_pipe, (var0) => {
      return new Integer3(var0);
    });
  })(), prepend((() => {
    let _pipe = string2;
    return map3(_pipe, (var0) => {
      return new String4(var0);
    });
  })(), prepend((() => {
    let _pipe = bool;
    return map3(_pipe, bool2);
  })(), prepend((() => {
    let _pipe = bit_array2;
    return map3(_pipe, (var0) => {
      return new Binary3(var0);
    });
  })(), prepend((() => {
    let _pipe = list2(dynamic);
    return map3(_pipe, (items) => {
      return new LinkedList(map2(items, from_js));
    });
  })(), prepend((() => {
    let _pipe = dict2(string2, dynamic);
    return map3(_pipe, (fields) => {
      return new Record2(map(fields, (_, field4) => {
        return from_js(field4);
      }));
    });
  })(), prepend((() => {
    let _pipe = float2;
    return map3(_pipe, (_) => {
      return new String4("float");
    });
  })(), List$Empty$const)))))));
}
function from_js(value2) {
  let $ = is_nullish(value2);
  if ($) {
    return unit2();
  } else {
    let $1 = run(value2, decoder3());
    if ($1 instanceof Ok) {
      let value$1 = $1[0];
      return value$1;
    } else {
      return new String4(classify_dynamic(value2));
    }
  }
}

// build/dev/javascript/opencode_plugin/opencode_plugin/policy.mjs
class Policy extends CustomType {
  constructor(gates) {
    super();
    this.gates = gates;
  }
}

class Gated extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Open extends CustomType {
}
var Access$Open$const = new Open;
class Unavailable2 extends CustomType {
}
var Access$Unavailable$const = new Unavailable2;
class Pass extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
class Mock extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
var captured = /* @__PURE__ */ prepend("StandardOut", prepend("StandardError", List$Empty$const));
var unchecked = /* @__PURE__ */ prepend("DecodeJSON", prepend("EYGParse", prepend("Flip", prepend("Hash", prepend("Random", List$Empty$const)))));
function from_value(value2) {
  let $ = as_record(value2);
  if ($ instanceof Ok) {
    let fields$1 = $[0];
    let _pipe = fields$1;
    let _pipe$1 = map(_pipe, (_, gate) => {
      return prepend(gate, List$Empty$const);
    });
    let _pipe$2 = new Policy(_pipe$1);
    return new Ok(_pipe$2);
  } else {
    return new Error2("a policy must be a record of gate functions");
  }
}
function restrict(parent, child) {
  let $ = as_record(child);
  if ($ instanceof Ok) {
    let fields$1 = $[0];
    let _pipe = parent.gates;
    let _pipe$1 = to_list(_pipe);
    let _pipe$2 = filter_map(_pipe$1, (entry2) => {
      let field$1 = entry2[0];
      let gates = entry2[1];
      let $1 = get(fields$1, field$1);
      if ($1 instanceof Ok) {
        let gate = $1[0];
        return new Ok([field$1, prepend(gate, gates)]);
      } else {
        return $1;
      }
    });
    let _pipe$3 = from_list(_pipe$2);
    let _pipe$4 = new Policy(_pipe$3);
    return new Ok(_pipe$4);
  } else {
    return new Error2("a policy must be a record of gate functions");
  }
}
function do_field(loop$letters, loop$previous_lower, loop$acc) {
  while (true) {
    let letters = loop$letters;
    let previous_lower = loop$previous_lower;
    let acc = loop$acc;
    if (letters instanceof Empty) {
      let _pipe = acc;
      let _pipe$1 = reverse(_pipe);
      return concat2(_pipe$1);
    } else {
      let letter = letters.head;
      let rest = letters.tail;
      let lower30 = lowercase(letter);
      let is_upper = lower30 !== letter;
      let _block;
      let $ = is_upper && previous_lower;
      if ($) {
        _block = prepend(lower30, prepend("_", acc));
      } else {
        _block = prepend(lower30, acc);
      }
      let acc$1 = _block;
      loop$letters = rest;
      loop$previous_lower = !is_upper;
      loop$acc = acc$1;
    }
  }
}
function field4(label31) {
  let _pipe = label31;
  let _pipe$1 = graphemes(_pipe);
  return do_field(_pipe$1, false, List$Empty$const);
}
function access(policy, label31) {
  let $ = get(policy.gates, field4(label31));
  if ($ instanceof Ok) {
    let gates = $[0];
    return new Gated(gates);
  } else {
    let $1 = contains(unchecked, label31) || contains(captured, label31);
    if ($1) {
      return Access$Open$const;
    } else {
      return Access$Unavailable$const;
    }
  }
}
function fields(policy) {
  let _pipe = keys(policy.gates);
  return sort(_pipe, compare2);
}
function decision(value2) {
  if (value2 instanceof Tagged) {
    let $ = value2.label;
    if ($ === "Pass") {
      let inner = value2.value;
      return new Ok(new Pass(inner));
    } else if ($ === "Mock") {
      let inner = value2.value;
      return new Ok(new Mock(inner));
    } else {
      return new Error2(undefined);
    }
  } else {
    return new Error2(undefined);
  }
}

// build/dev/javascript/opencode_plugin/opencode_plugin.mjs
class Config extends CustomType {
  constructor(policy, context, agents, readme) {
    super();
    this.policy = policy;
    this.context = context;
    this.agents = agents;
    this.readme = readme;
  }
}
var Config$Config = (policy, context, agents, readme) => new Config(policy, context, agents, readme);
var Config$isConfig = (value2) => value2 instanceof Config;
var Config$Config$policy = (value2) => value2.policy;
var Config$Config$0 = (value2) => value2.policy;
var Config$Config$context = (value2) => value2.context;
var Config$Config$1 = (value2) => value2.context;
var Config$Config$agents = (value2) => value2.agents;
var Config$Config$2 = (value2) => value2.agents;
var Config$Config$readme = (value2) => value2.readme;
var Config$Config$3 = (value2) => value2.readme;

class Host extends CustomType {
  constructor(label31, lift30, lower30, handler) {
    super();
    this.label = label31;
    this.lift = lift30;
    this.lower = lower30;
    this.handler = handler;
  }
}
var Host$Host = (label31, lift30, lower30, handler) => new Host(label31, lift30, lower30, handler);
var Host$isHost = (value2) => value2 instanceof Host;
var Host$Host$label = (value2) => value2.label;
var Host$Host$0 = (value2) => value2.label;
var Host$Host$lift = (value2) => value2.lift;
var Host$Host$1 = (value2) => value2.lift;
var Host$Host$lower = (value2) => value2.lower;
var Host$Host$2 = (value2) => value2.lower;
var Host$Host$handler = (value2) => value2.handler;
var Host$Host$3 = (value2) => value2.handler;

class Report extends CustomType {
  constructor(ok2, output, value2, effects3) {
    super();
    this.ok = ok2;
    this.output = output;
    this.value = value2;
    this.effects = effects3;
  }
}
var Report$Report = (ok2, output, value2, effects3) => new Report(ok2, output, value2, effects3);
var Report$isReport = (value2) => value2 instanceof Report;
var Report$Report$ok = (value2) => value2.ok;
var Report$Report$0 = (value2) => value2.ok;
var Report$Report$output = (value2) => value2.output;
var Report$Report$1 = (value2) => value2.output;
var Report$Report$value = (value2) => value2.value;
var Report$Report$2 = (value2) => value2.value;
var Report$Report$effects = (value2) => value2.effects;
var Report$Report$3 = (value2) => value2.effects;

class Run extends CustomType {
  constructor(policy, hosts, directory, output, effects3, state) {
    super();
    this.policy = policy;
    this.hosts = hosts;
    this.directory = directory;
    this.output = output;
    this.effects = effects3;
    this.state = state;
  }
}
function host(label31, lift30, lower30, handler) {
  return new Host(label31, lift30, lower30, handler);
}
function hub_origin() {
  return https("eyg.run");
}
function new_state() {
  return new State(hub_origin(), empty());
}
function cast_config(value2) {
  return try$((() => {
    let $ = field2("policy", (var0) => {
      return new Ok(var0);
    }, value2);
    if ($ instanceof Ok) {
      let policy = $[0];
      return from_value(policy);
    } else {
      return new Error2("the configuration must have a policy field");
    }
  })(), (policy) => {
    let _block;
    let _pipe = field2("context", (var0) => {
      return new Ok(var0);
    }, value2);
    _block = unwrap(_pipe, unit2());
    let context = _block;
    let _block$1;
    let _pipe$1 = field2("agents", as_record, value2);
    _block$1 = unwrap(_pipe$1, make());
    let agents = _block$1;
    let _block$2;
    let _pipe$2 = field2("readme", as_string, context);
    _block$2 = unwrap(_pipe$2, "");
    let readme = _block$2;
    return new Ok(new Config(policy, context, agents, readme));
  });
}
function evaluate_source(code3, path2) {
  let $ = parse_input(code3, new File3(path2));
  if ($ instanceof Ok) {
    let code$1 = $[0];
    return map_promise(run2(block2(code$1, List$Empty$const, new_state())), (_use0) => {
      let result2 = _use0[0];
      if (result2 instanceof Ok) {
        let $1 = result2[0][0];
        if ($1 instanceof Some) {
          let value2 = $1[0];
          return new Ok(value2);
        } else {
          return new Error2(path2 + " has no final expression");
        }
      } else {
        let reason = result2[0][0];
        let location = result2[0][1];
        let k = result2[0][3];
        return new Error2(render_error2(reason, location, k, path2));
      }
    });
  } else {
    let reason = $[0];
    return resolve2(new Error2(reason));
  }
}
function evaluate(path2) {
  let input2 = new File3(path2);
  return then_await(run2(read_input(input2)), (code3) => {
    if (code3 instanceof Ok) {
      let code$1 = code3[0];
      return evaluate_source(code$1, path2);
    } else {
      let reason = code3[0];
      return resolve2(new Error2(reason));
    }
  });
}
function load(path2) {
  return map_promise(evaluate(path2), (value2) => {
    return try$(value2, cast_config);
  });
}
function load_source(code3, path2) {
  return map_promise(evaluate_source(code3, path2), (value2) => {
    return try$(value2, cast_config);
  });
}
function config_policy(config) {
  return config.policy;
}
function config_context(config) {
  return config.context;
}
function config_readme(config) {
  return config.readme;
}
function agent_policy(config, name2) {
  let $ = get(config.agents, name2);
  if ($ instanceof Ok) {
    let value2 = $[0];
    let _pipe = from_value(value2);
    return replace_error(_pipe, undefined);
  } else {
    return $;
  }
}
function restrict2(parent, child) {
  return restrict(parent, child);
}
function replace4(child) {
  return from_value(child);
}
function field5(value2, name2) {
  let _pipe = field2(name2, (var0) => {
    return new Ok(var0);
  }, value2);
  return replace_error(_pipe, undefined);
}
function inspect4(value2) {
  return inspect_result(value2);
}
function available(policy, label31) {
  let $ = access(policy, label31);
  if ($ instanceof Unavailable2) {
    return false;
  } else {
    return label31 !== "Exit" && label31 !== "StandardIn";
  }
}
function describe3(policy, hosts) {
  let _block;
  let _pipe = effects2();
  let _pipe$1 = filter(_pipe, (i) => {
    return available(policy, i.name);
  });
  _block = map2(_pipe$1, describe_effect);
  let computer = _block;
  let _block$1;
  let _pipe$2 = hosts;
  let _pipe$3 = filter(_pipe$2, (h) => {
    return available(policy, h.label);
  });
  _block$1 = map2(_pipe$3, (h) => {
    return h.label + ": " + h.lift + " -> Result(" + h.lower + ", String)";
  });
  let hosts$1 = _block$1;
  let _pipe$4 = append3(computer, hosts$1);
  let _pipe$5 = sort(_pipe$4, compare2);
  return join(_pipe$5, `
`);
}
function fields2(policy) {
  return fields(policy);
}
function report_ok(report) {
  return report.ok;
}
function report_text(report) {
  let output = report.output;
  let value2 = report.value;
  if (output === "") {
    return value2;
  } else {
    return `Output:
` + output + `
Result:
` + value2;
  }
}
function report_effects(report) {
  return report.effects;
}
function denied(reason, policy, hosts) {
  if (reason instanceof UnhandledEffect) {
    let label31 = reason[0];
    let $ = available(policy, label31);
    if ($) {
      return "";
    } else {
      let known = any(effects2(), (i) => {
        return i.name === label31;
      }) || any(hosts, (h) => {
        return h.label === label31;
      });
      if (known) {
        return "The effect " + label31 + " is not allowed by your policy, it has no `" + field4(label31) + "` gate.\n";
      } else {
        return "There is no effect called " + label31 + `.
`;
      }
    }
  } else {
    return "";
  }
}
function do_lookup(reference2, meta, run3) {
  return map_promise(run2(lookup2(reference2, meta.origin, run3.state)), (_use0) => {
    let result2 = _use0[0];
    let state = _use0[1];
    return [
      result2,
      new Run(run3.policy, run3.hosts, run3.directory, run3.output, run3.effects, state)
    ];
  });
}
function unavailable(label31, lift30) {
  return new UnhandledEffect(label31, lift30);
}
function gate(gates, lift30, meta, run3) {
  if (gates instanceof Empty) {
    return resolve2([new Ok(new Pass(lift30)), run3]);
  } else {
    let first = gates.head;
    let rest = gates.tail;
    let return$2 = call2(first, prepend([lift30, meta], List$Empty$const));
    return then_await(run2(pure_loop(return$2, run3.state)), (_use0) => {
      let result2 = _use0[0];
      let state = _use0[1];
      let run$1 = new Run(run3.policy, run3.hosts, run3.directory, run3.output, run3.effects, state);
      if (result2 instanceof Ok) {
        let value2 = result2[0];
        let $ = decision(value2);
        if ($ instanceof Ok) {
          let $1 = $[0];
          if ($1 instanceof Pass) {
            let lift$1 = $1[0];
            return gate(rest, lift$1, meta, run$1);
          } else {
            let value$1 = $1[0];
            return resolve2([new Ok(new Mock(value$1)), run$1]);
          }
        } else {
          return resolve2([
            new Error2(new IncorrectTerm("Pass(lift) or Mock(lower)", value2)),
            run$1
          ]);
        }
      } else {
        let reason = result2[0][0];
        return resolve2([new Error2(reason), run$1]);
      }
    });
  }
}
function lookup3(reference2, meta, run3) {
  if (reference2 instanceof Relative) {
    let path2 = reference2.location;
    let request2 = new Record2(from_list(prepend(["path", new String4(path2)], prepend(["offset", new Integer3(0)], prepend(["limit", new Integer3(1e8)], List$Empty$const)))));
    let $ = access(run3.policy, "ReadFile");
    if ($ instanceof Gated) {
      let gates = $[0];
      return then_await(gate(gates, request2, meta, run3), (_use0) => {
        let decision2 = _use0[0];
        let run$1 = _use0[1];
        if (decision2 instanceof Ok) {
          let $1 = decision2[0];
          if ($1 instanceof Pass) {
            let request$1 = $1[0];
            let $2 = field2("path", as_string, request$1);
            if ($2 instanceof Ok) {
              let path$1 = $2[0];
              return do_lookup(new Relative(path$1), meta, run$1);
            } else {
              let reason = $2[0];
              return resolve2([new Error2(reason), run$1]);
            }
          } else {
            let value2 = $1[0];
            return resolve2([
              new Error2(new UnhandledEffect("Abort", new String4("import of " + path2 + " denied by policy: " + inspect3(value2)))),
              run$1
            ]);
          }
        } else {
          let reason = decision2[0];
          return resolve2([new Error2(reason), run$1]);
        }
      });
    } else {
      return resolve2([new Error2(unavailable("ReadFile", request2)), run3]);
    }
  } else {
    return do_lookup(reference2, meta, run3);
  }
}
function perform3(label31, lift30, meta, run3) {
  let $ = find(run3.hosts, (h) => {
    return h.label === label31;
  });
  if ($ instanceof Ok) {
    let host$1 = $[0];
    return map_promise(call_host(host$1.handler, to_js(lift30), lift30), (result2) => {
      let _block;
      if (result2 instanceof Ok) {
        let value3 = result2[0];
        _block = ok(from_js(value3));
      } else {
        let reason = result2[0];
        _block = error(new String4(reason));
      }
      let value2 = _block;
      return [new Ok(value2), run3];
    });
  } else {
    let $1 = cast2(label31, lift30);
    if ($1 instanceof Ok) {
      let effect = $1[0];
      if (effect instanceof Cwd) {
        return resolve2([new Ok(encode14(new Ok(run3.directory))), run3]);
      } else if (effect instanceof Exit) {
        return resolve2([new Error2(unavailable(label31, lift30)), run3]);
      } else if (effect instanceof StandardError) {
        let text = effect[0];
        return resolve2([
          new Ok(encode24(undefined)),
          new Run(run3.policy, run3.hosts, run3.directory, prepend(text, run3.output), run3.effects, run3.state)
        ]);
      } else if (effect instanceof StandardIn) {
        return resolve2([
          new Ok(encode25(new Error2("no standard input in opencode"))),
          run3
        ]);
      } else if (effect instanceof StanardOut) {
        let text = effect[0];
        return resolve2([
          new Ok(encode26(undefined)),
          new Run(run3.policy, run3.hosts, run3.directory, prepend(text, run3.output), run3.effects, run3.state)
        ]);
      } else {
        return map_promise(run2(extrinsic(effect, meta.origin)), (value2) => {
          return [new Ok(value2), run3];
        });
      }
    } else {
      let reason = $1[0];
      return resolve2([new Error2(reason), run3]);
    }
  }
}
function absolute3(label31, lift30, directory) {
  let resolve4 = (path2) => {
    let _pipe = resolve_relative(directory, path2);
    return unwrap(_pipe, path2);
  };
  if (lift30 instanceof String4) {
    if (label31 === "ReadDirectory") {
      let path2 = lift30.value;
      return new String4(resolve4(path2));
    } else if (label31 === "DeleteFile") {
      let path2 = lift30.value;
      return new String4(resolve4(path2));
    } else if (label31 === "MakeDirectory") {
      let path2 = lift30.value;
      return new String4(resolve4(path2));
    } else {
      return lift30;
    }
  } else if (lift30 instanceof Record2) {
    if (label31 === "ReadFile") {
      let fields$1 = lift30.fields;
      let $ = get(fields$1, "path");
      if ($ instanceof Ok) {
        let $1 = $[0];
        if ($1 instanceof String4) {
          let path2 = $1.value;
          return new Record2(insert(fields$1, "path", new String4(resolve4(path2))));
        } else {
          return lift30;
        }
      } else {
        return lift30;
      }
    } else if (label31 === "WriteFile") {
      let fields$1 = lift30.fields;
      let $ = get(fields$1, "path");
      if ($ instanceof Ok) {
        let $1 = $[0];
        if ($1 instanceof String4) {
          let path2 = $1.value;
          return new Record2(insert(fields$1, "path", new String4(resolve4(path2))));
        } else {
          return lift30;
        }
      } else {
        return lift30;
      }
    } else if (label31 === "AppendFile") {
      let fields$1 = lift30.fields;
      let $ = get(fields$1, "path");
      if ($ instanceof Ok) {
        let $1 = $[0];
        if ($1 instanceof String4) {
          let path2 = $1.value;
          return new Record2(insert(fields$1, "path", new String4(resolve4(path2))));
        } else {
          return lift30;
        }
      } else {
        return lift30;
      }
    } else {
      return lift30;
    }
  } else {
    return lift30;
  }
}
function decide(label31, lift30, meta, run3) {
  let lift$1 = absolute3(label31, lift30, run3.directory);
  let $ = access(run3.policy, label31);
  if ($ instanceof Gated) {
    let gates = $[0];
    return then_await(gate(gates, lift$1, meta, run3), (_use0) => {
      let decision2 = _use0[0];
      let run$1 = _use0[1];
      if (decision2 instanceof Ok) {
        let $1 = decision2[0];
        if ($1 instanceof Pass) {
          let lift$2 = $1[0];
          return perform3(label31, lift$2, meta, run$1);
        } else {
          let value2 = $1[0];
          return resolve2([new Ok(value2), run$1]);
        }
      } else {
        let reason = decision2[0];
        return resolve2([new Error2(reason), run$1]);
      }
    });
  } else if ($ instanceof Open) {
    return perform3(label31, lift$1, meta, run3);
  } else {
    return resolve2([new Error2(unavailable(label31, lift$1)), run3]);
  }
}
function loop6(return$2, run3) {
  if (return$2 instanceof Ok) {
    let value2 = return$2[0];
    return resolve2([new Ok(value2), run3]);
  } else {
    let error2 = return$2;
    let reason = return$2[0][0];
    let meta = return$2[0][1];
    let env3 = return$2[0][2];
    let k = return$2[0][3];
    if (reason instanceof UndefinedReference) {
      let reference2 = reason[0];
      return then_await(lookup3(reference2, meta, run3), (_use0) => {
        let result2 = _use0[0];
        let run$1 = _use0[1];
        if (result2 instanceof Ok) {
          let value2 = result2[0];
          return loop6(resume2(value2, env3, k), run$1);
        } else {
          let reason$1 = result2[0];
          return resolve2([new Error2([reason$1, meta, env3, k]), run$1]);
        }
      });
    } else if (reason instanceof UnhandledEffect) {
      let label31 = reason[0];
      let lift30 = reason[1];
      let run$1 = new Run(run3.policy, run3.hosts, run3.directory, run3.output, prepend(label31, run3.effects), run3.state);
      return then_await(decide(label31, lift30, meta, run$1), (_use0) => {
        let result2 = _use0[0];
        let run$2 = _use0[1];
        if (result2 instanceof Ok) {
          let value2 = result2[0];
          return loop6(resume2(value2, env3, k), run$2);
        } else {
          let reason$1 = result2[0];
          return resolve2([new Error2([reason$1, meta, env3, k]), run$2]);
        }
      });
    } else {
      return resolve2([error2, run3]);
    }
  }
}
function run3(code3, policy, context, directory, hosts) {
  let origin = new Disk(join2(directory, "eyg"));
  let $ = parse5(code3, origin);
  if ($ instanceof Ok) {
    let code$1 = $[0];
    let run$1 = new Run(policy, hosts, directory, List$Empty$const, List$Empty$const, new_state());
    return map_promise(loop6(execute2(code$1, prepend(["context", context], List$Empty$const)), run$1), (_use0) => {
      let result2 = _use0[0];
      let run$2 = _use0[1];
      let _block;
      let _pipe = run$2.output;
      let _pipe$1 = reverse(_pipe);
      _block = concat2(_pipe$1);
      let output = _block;
      let effects3 = reverse(run$2.effects);
      if (result2 instanceof Ok) {
        let $1 = result2[0][0];
        if ($1 instanceof Some) {
          let value2 = $1[0];
          return new Report(true, output, inspect_result(value2), effects3);
        } else {
          return new Report(true, output, "", effects3);
        }
      } else {
        let reason = result2[0][0];
        let location = result2[0][1];
        let k = result2[0][3];
        return new Report(false, output, denied(reason, policy, hosts) + render_error2(reason, location, k, directory), effects3);
      }
    });
  } else {
    let reason = $[0];
    return resolve2(new Report(false, "", reason, List$Empty$const));
  }
}
function agent_names(config) {
  let _pipe = keys(config.agents);
  return sort(_pipe, compare2);
}
export {
  toList,
  run3 as run,
  restrict2 as restrict,
  report_text,
  report_ok,
  report_effects,
  replace4 as replace,
  load_source,
  load,
  inspect4 as inspect,
  host,
  fields2 as fields,
  field5 as field,
  evaluate_source,
  evaluate,
  describe3 as describe,
  config_readme,
  config_policy,
  config_context,
  agent_policy,
  agent_names,
  Report$isReport,
  Report$Report$value,
  Report$Report$output,
  Report$Report$ok,
  Report$Report$effects,
  Report$Report$3,
  Report$Report$2,
  Report$Report$1,
  Report$Report$0,
  Report$Report,
  Report,
  Host$isHost,
  Host$Host$lower,
  Host$Host$lift,
  Host$Host$label,
  Host$Host$handler,
  Host$Host$3,
  Host$Host$2,
  Host$Host$1,
  Host$Host$0,
  Host$Host,
  Host,
  Config$isConfig,
  Config$Config$readme,
  Config$Config$policy,
  Config$Config$context,
  Config$Config$agents,
  Config$Config$3,
  Config$Config$2,
  Config$Config$1,
  Config$Config$0,
  Config$Config,
  Config
};
