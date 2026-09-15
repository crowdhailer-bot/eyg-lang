// Browser implementations of the effects in `touch_grass/harness/browser`.
//
// Values use the representation of compiled programs, see runtime/builtins.mjs.
// Pass the result of `effects` as the platform to `run` of either runtime.

import * as b from "../runtime/builtins.mjs";

export class Abort extends Error {
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}

const tag = (label, value = b.unit) => ({ $T: label, $V: value });

/// Options:
/// - print(text) where Print writes, defaults to console.log
/// - window, defaults to globalThis
/// - fetch, defaults to globalThis.fetch
/// - spotless: {token(service): Promise(String), hub: origin of the eyg hub}
export function effects(options = {}) {
  const win = options.window ?? globalThis;
  const doFetch = options.fetch ?? ((...args) => globalThis.fetch(...args));
  const print = options.print ?? ((text) => console.log(text));

  const spotless = (service) => ({
    async: async (operation) => {
      const config = options.spotless;
      if (!config) return b.error("no spotless token provider for " + service);
      let token;
      try {
        token = await config.token(service);
      } catch (reason) {
        return b.error(String(reason && reason.message ? reason.message : reason));
      }
      const base = serviceBase(service, config.hub ?? "https://eyg.run");
      const query = option(operation.query);
      const url = base + operation.path + (query === undefined ? "" : "?" + query);
      const hs = headers(operation.headers);
      hs.push(["authorization", "Bearer " + token]);
      return send(doFetch, url, init(operation.method, hs, operation.body));
    },
  });

  return {
    Abort: {
      sync: (reason) => {
        throw new Abort(reason);
      },
    },
    Alert: {
      sync: (message) => {
        win.alert(message);
        return b.unit;
      },
    },
    Copy: {
      async: (text) =>
        win.navigator.clipboard.writeText(text).then(
          () => b.ok(b.unit),
          (reason) => b.error(String(reason)),
        ),
    },
    DecodeJSON: { sync: (bytes) => decodeJson(bytes) },
    Download: {
      sync: ({ name, content }) => {
        const doc = win.document;
        const url = win.URL.createObjectURL(new win.Blob([content]));
        const a = doc.createElement("a");
        a.href = url;
        a.download = name;
        doc.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => win.URL.revokeObjectURL(url), 0);
        return b.unit;
      },
    },
    Fetch: {
      async: (request) =>
        send(doFetch, requestUrl(request), init(request.method, headers(request.headers), request.body)),
    },
    Flip: { sync: () => b.bool(Math.random() < 0.5) },
    Now: { sync: () => Date.now() },
    Paste: {
      async: () =>
        win.navigator.clipboard.readText().then(
          (text) => b.ok(text),
          (reason) => b.error(String(reason)),
        ),
    },
    Print: {
      sync: (message) => {
        print(message);
        return b.unit;
      },
    },
    Prompt: {
      sync: (question) => {
        const answer = win.prompt(question);
        return answer === null ? b.error(b.unit) : b.ok(answer);
      },
    },
    Random: { sync: (max) => Math.floor(Math.random() * max) },
    Visit: {
      sync: (uri) => {
        const opened = win.open(uriToString(uri));
        return opened ? b.ok(b.unit) : b.error("unable to open window");
      },
    },
    DNSimple: spotless("DNSimple"),
    GitHub: spotless("GitHub"),
    Vimeo: spotless("Vimeo"),
  };
}

/// Effects defined only in the compiler, see `platform/browser.gleam`.
export function extensions(options = {}) {
  const win = options.window ?? globalThis;
  const storage = (f) => {
    try {
      return b.ok(f(win.localStorage));
    } catch (reason) {
      return b.error(String(reason && reason.message ? reason.message : reason));
    }
  };
  return {
    Sleep: { async: (ms) => new Promise((resolve) => setTimeout(() => resolve(b.unit), ms)) },
    Hash: {
      async: async ({ algorithm, bytes }) =>
        new Uint8Array(await win.crypto.subtle.digest(hashName(algorithm), bytes)),
    },
    CreateKey: { async: (algorithm) => createKey(win.crypto, algorithm) },
    Sign: { async: ({ key, data }) => sign(win.crypto, key, data) },
    StorageGet: {
      sync: (key) =>
        storage((store) => {
          const value = store.getItem(key);
          return value === null ? tag("None") : tag("Some", value);
        }),
    },
    StorageSet: {
      sync: ({ key, value }) =>
        storage((store) => {
          store.setItem(key, value);
          return b.unit;
        }),
    },
    StorageDelete: {
      sync: (key) =>
        storage((store) => {
          store.removeItem(key);
          return b.unit;
        }),
    },
    Location: { sync: () => locationUri(win.location) },
  };
}

function hashName(algorithm) {
  switch (algorithm.$T) {
    case "SHA256":
      return "SHA-256";
  }
}

const base64url = {
  encode: (bytes) =>
    btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, ""),
  decode: (text) =>
    Uint8Array.from(atob(text.replaceAll("-", "+").replaceAll("_", "/")), (c) => c.charCodeAt(0)),
};

async function createKey(crypto, algorithm) {
  if (algorithm.$T !== "Eddsa") return b.error("unsupported algorithm " + algorithm.$T);
  try {
    const pair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
    const jwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
    return b.ok(
      tag("Eddsa", {
        kty: "OKP",
        crv: "Ed25519",
        x: base64url.decode(jwk.x),
        d: base64url.decode(jwk.d),
      }),
    );
  } catch (reason) {
    return b.error(String(reason && reason.message ? reason.message : reason));
  }
}

async function sign(crypto, key, data) {
  if (key.$T !== "Eddsa") return b.error("unsupported key " + key.$T);
  try {
    const jwk = {
      kty: "OKP",
      crv: "Ed25519",
      x: base64url.encode(key.$V.x),
      d: base64url.encode(key.$V.d),
    };
    const privateKey = await crypto.subtle.importKey("jwk", jwk, { name: "Ed25519" }, false, ["sign"]);
    return b.ok(new Uint8Array(await crypto.subtle.sign("Ed25519", privateKey, data)));
  } catch (reason) {
    return b.error(String(reason && reason.message ? reason.message : reason));
  }
}

function locationUri(location) {
  const query = [];
  new URLSearchParams(location.search).forEach((value, key) => query.push({ key, value }));
  return {
    scheme: tag(location.protocol === "https:" ? "HTTPS" : "HTTP"),
    host: location.hostname,
    port: location.port === "" ? tag("None") : tag("Some", location.port),
    path: location.pathname,
    query: b.list(query),
  };
}

function serviceBase(service, hub) {
  switch (service) {
    case "DNSimple":
      return hub + "/proxy/dnsimple";
    case "GitHub":
      return "https://api.github.com";
    case "Vimeo":
      return "https://api.vimeo.com";
  }
}

// --- http

export function option(value) {
  return value.$T === "Some" ? value.$V : undefined;
}

function method(value) {
  return value.$T === "OTHER" ? value.$V : value.$T;
}

function headers(list) {
  return b.array(list).map(({ key, value }) => [key, value]);
}

export function requestUrl(request) {
  const scheme = request.scheme.$T === "HTTPS" ? "https" : "http";
  const port = option(request.port);
  const query = option(request.query);
  return (
    scheme +
    "://" +
    request.host +
    (port === undefined ? "" : ":" + port) +
    request.path +
    (query === undefined ? "" : "?" + query)
  );
}

function init(m, hs, body) {
  const verb = method(m);
  const init = { method: verb, headers: hs };
  if (verb !== "GET" && verb !== "HEAD") init.body = body;
  return init;
}

async function send(doFetch, url, init) {
  let response;
  try {
    response = await doFetch(url, init);
  } catch (reason) {
    return b.error("network error: " + (reason && reason.message ? reason.message : String(reason)));
  }
  try {
    const body = new Uint8Array(await response.arrayBuffer());
    const hs = [];
    response.headers.forEach((value, key) => hs.push({ key, value }));
    return b.ok({ status: response.status, headers: b.list(hs), body });
  } catch {
    return b.error("unable to read body");
  }
}

export function uriToString(uri) {
  const scheme = uri.scheme.$T === "HTTPS" ? "https" : "http";
  const port = option(uri.port);
  const query = b
    .array(uri.query)
    .map(({ key, value }) => encodeURIComponent(key) + "=" + encodeURIComponent(value))
    .join("&");
  return (
    scheme +
    "://" +
    uri.host +
    (port === undefined ? "" : ":" + port) +
    uri.path +
    (query === "" ? "" : "?" + query)
  );
}

// --- JSON
// A port of the julienne tokeniser used by touch_grass/decode_json,
// a flat list of terms each with the depth of nesting.

const decoder = new TextDecoder("utf-8", { fatal: true });
const encoder = new TextEncoder();

class JsonError {
  constructor(description) {
    this.description = description;
  }
}

function describe(bytes) {
  try {
    return decoder.decode(bytes);
  } catch {
    return "<<" + Array.from(bytes).join(", ") + ">>";
  }
}

const END = () => new JsonError("unexpected end of JSON");

export function decodeJson(bytes) {
  try {
    return b.ok(b.list(tokenise(bytes)));
  } catch (reason) {
    if (reason instanceof JsonError) return b.error(reason.description);
    throw reason;
  }
}

function tokenise(bytes) {
  const n = bytes.length;
  const out = [];
  const stack = [];
  let i = 0;
  let state = "value";

  const unexpected = (at) => new JsonError(describe(bytes.subarray(at)));
  const push = (term) => out.push({ term, depth: stack.length });
  const ws = (c) => c === 13 || c === 10 || c === 32 || c === 9;
  const startsWith = (text) => {
    if (i + text.length > n) return false;
    for (let j = 0; j < text.length; j++) if (bytes[i + j] !== text.charCodeAt(j)) return false;
    return true;
  };
  const digits = (value, size) => {
    while (i < n && bytes[i] >= 48 && bytes[i] <= 57) {
      value = value * 10 + (bytes[i] - 48);
      size++;
      i++;
    }
    return [value, size];
  };

  const exponent = (sign, integer, decimal) => {
    let expSign = 1;
    if (bytes[i] === 43) i++;
    else if (bytes[i] === 45) {
      expSign = -1;
      i++;
    }
    const [e, size] = digits(0, 0);
    if (size === 0) throw new JsonError("missing digits in number");
    push(number(sign, integer, decimal, expSign * e));
  };
  const decimalPart = (sign, integer) => {
    const [d, size] = digits(0, 0);
    if (size === 0) throw new JsonError("missing digits in number");
    if (bytes[i] === 101 || bytes[i] === 69) {
      i++;
      exponent(sign, integer, [d, size]);
    } else {
      push(number(sign, integer, [d, size], 0));
    }
  };
  const string = () => {
    // i is after the opening quote
    const acc = [];
    while (true) {
      if (i >= n) throw END();
      const c = bytes[i];
      if (c === 34) {
        i++;
        const raw = new Uint8Array(acc);
        try {
          return decoder.decode(raw);
        } catch {
          throw new JsonError(describe(raw));
        }
      }
      if (c === 92) {
        if (i + 1 >= n) throw unexpected(i);
        const e = bytes[i + 1];
        const simple = { 34: 34, 92: 92, 47: 47, 98: 8, 102: 12, 110: 10, 114: 13, 116: 9 }[e];
        if (simple !== undefined) {
          acc.push(simple);
          i += 2;
          continue;
        }
        if (e === 117) {
          const start = i;
          i += 2;
          let point = hex4(start);
          if (point >= 0xd800 && point <= 0xdbff) {
            if (bytes[i] !== 92 || bytes[i + 1] !== 117) throw unexpected(start);
            i += 2;
            const low = hex4(start);
            if (low < 0xdc00 || low > 0xdfff) throw unexpected(start);
            point = 0x10000 + (point - 0xd800) * 0x400 + (low - 0xdc00);
          } else if (point >= 0xdc00 && point <= 0xdfff) {
            throw unexpected(start);
          }
          for (const byte of encoder.encode(String.fromCodePoint(point))) acc.push(byte);
          continue;
        }
        throw unexpected(i);
      }
      acc.push(c);
      i++;
    }
  };
  const hex4 = (start) => {
    if (i + 4 > n) throw END();
    let value = 0;
    for (let j = 0; j < 4; j++) {
      const c = bytes[i + j];
      let v;
      if (c >= 48 && c <= 57) v = c - 48;
      else if (c >= 65 && c <= 70) v = c - 55;
      else if (c >= 97 && c <= 102) v = c - 87;
      else throw unexpected(start);
      value = value * 16 + v;
    }
    i += 4;
    return value;
  };

  while (true) {
    if (state === "value") {
      while (i < n && ws(bytes[i])) i++;
      if (i >= n) throw END();
      const c = bytes[i];
      const top = stack[stack.length - 1];
      if (startsWith("true")) {
        i += 4;
        push(b.True);
        state = "continue";
      } else if (startsWith("false")) {
        i += 5;
        push(b.False);
        state = "continue";
      } else if (startsWith("null")) {
        i += 4;
        push(tag("Null"));
        state = "continue";
      } else if (c === 91) {
        i++;
        push(tag("Array"));
        stack.push("A");
      } else if (c === 123) {
        i++;
        push(tag("Object"));
        stack.push("O");
        state = "key";
      } else if (c === 93 && top === "A") {
        i++;
        stack.pop();
        state = "continue";
      } else if (c === 34) {
        i++;
        const depth = stack.length;
        out.push({ term: tag("String", string()), depth });
        state = "continue";
      } else if (startsWith("0.")) {
        i += 2;
        decimalPart(1, 0);
        state = "continue";
      } else if (startsWith("-0.")) {
        i += 3;
        decimalPart(-1, 0);
        state = "continue";
      } else if (startsWith("0e") || startsWith("0E")) {
        i += 2;
        exponent(1, 0, [0, 0]);
        state = "continue";
      } else if (startsWith("-0e") || startsWith("-0E")) {
        i += 3;
        exponent(-1, 0, [0, 0]);
        state = "continue";
      } else if (c === 48 || startsWith("-0")) {
        i += c === 48 ? 1 : 2;
        push(tag("Integer", 0));
        state = "continue";
      } else if ((c >= 49 && c <= 57) || (c === 45 && bytes[i + 1] >= 49 && bytes[i + 1] <= 57)) {
        const sign = c === 45 ? -1 : 1;
        if (c === 45) i++;
        const [integer] = digits(0, 0);
        if (bytes[i] === 46) {
          i++;
          decimalPart(sign, integer);
        } else if (bytes[i] === 101 || bytes[i] === 69) {
          i++;
          exponent(sign, integer, [0, 0]);
        } else {
          push(tag("Integer", sign * integer));
        }
        state = "continue";
      } else {
        throw unexpected(i);
      }
    } else if (state === "key") {
      while (i < n && ws(bytes[i])) i++;
      if (i >= n) throw END();
      if (bytes[i] === 34) {
        i++;
        const depth = stack.length;
        out.push({ term: tag("Field", string()), depth });
        while (i < n && ws(bytes[i])) i++;
        if (i >= n) throw END();
        if (bytes[i] !== 58) throw unexpected(i);
        i++;
        state = "value";
      } else if (bytes[i] === 125) {
        i++;
        stack.pop();
        state = "continue";
      } else {
        throw unexpected(i);
      }
    } else {
      while (i < n && ws(bytes[i])) i++;
      if (stack.length === 0) return out;
      if (i >= n) throw END();
      const c = bytes[i];
      const top = stack[stack.length - 1];
      if (c === 93 && top === "A") {
        i++;
        stack.pop();
      } else if (c === 44 && top === "A") {
        i++;
        state = "value";
      } else if (c === 125 && top === "O") {
        i++;
        stack.pop();
      } else if (c === 44 && top === "O") {
        i++;
        state = "key";
      } else {
        throw unexpected(i);
      }
    }
  }
}

function number(sign, integer, decimal, exponent) {
  return tag("Number", {
    sign: tag(sign < 0 ? "Negative" : "Positive"),
    integer,
    decimal: { numerator: decimal[0], size: decimal[1] },
    exponent,
  });
}
