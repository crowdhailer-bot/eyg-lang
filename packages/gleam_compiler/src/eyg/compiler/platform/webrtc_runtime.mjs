// Experimental WebRTC effects, the types are in `platform/webrtc.gleam`.
//
// - mirror: peers and channels are handles, each step of the offer and answer
//   exchange is an effect. ICE candidates are gathered before an offer or
//   answer is returned so a description is a single string.
// - session: an offer and an answer are opaque tokens, the program only moves
//   them between peers, by copy and paste, a QR code or a Fetch.
// - batch: the mirror design with sending and receiving many messages in one effect.
//
// Messages are binaries.

import * as b from "../runtime/builtins.mjs";

const message = (reason) => String(reason && reason.message ? reason.message : reason);
const attempt = (f) => {
  try {
    return b.ok(f());
  } catch (reason) {
    return b.error(message(reason));
  }
};
const attemptAsync = async (f) => {
  try {
    return b.ok(await f());
  } catch (reason) {
    return b.error(message(reason));
  }
};

class Inbox {
  constructor(channel) {
    this.queue = [];
    this.waiting = [];
    this.closed = false;
    channel.binaryType = "arraybuffer";
    channel.addEventListener("message", (event) => {
      const data = typeof event.data === "string" ? new TextEncoder().encode(event.data) : new Uint8Array(event.data);
      this.queue.push(data);
      this.wake();
    });
    channel.addEventListener("close", () => {
      this.closed = true;
      this.wake();
    });
  }
  wake() {
    const waiting = this.waiting;
    this.waiting = [];
    for (const check of waiting) check();
  }
  take(min) {
    return new Promise((resolve, reject) => {
      const check = () => {
        if (this.queue.length >= min) {
          resolve(this.queue.splice(0, this.queue.length));
        } else if (this.closed) {
          reject(new Error("channel closed"));
        } else {
          this.waiting.push(check);
        }
      };
      check();
    });
  }
}

function gathered(pc) {
  if (pc.iceGatheringState === "complete") return Promise.resolve();
  return new Promise((resolve) => {
    const check = () => {
      if (pc.iceGatheringState === "complete") {
        pc.removeEventListener("icegatheringstatechange", check);
        resolve();
      }
    };
    pc.addEventListener("icegatheringstatechange", check);
  });
}

function opened(channel) {
  if (channel.readyState === "open") return Promise.resolve();
  return new Promise((resolve, reject) => {
    channel.addEventListener("open", () => resolve(), { once: true });
    channel.addEventListener("close", () => reject(new Error("channel closed")), { once: true });
  });
}

function state(options) {
  const RTC = options.RTCPeerConnection ?? globalThis.RTCPeerConnection;
  let next = 1;
  const peers = new Map();
  const channels = new Map();
  const add = (map, value) => {
    const id = next++;
    map.set(id, value);
    return id;
  };
  const get = (map, id, kind) => {
    const value = map.get(id);
    if (value === undefined) throw new Error("unknown " + kind + " " + id);
    return value;
  };
  const peer = (id) => get(peers, id, "peer");
  const channel = (id) => get(channels, id, "channel");
  const addPeer = () => {
    const pc = new RTC({ iceServers: options.iceServers ?? [] });
    const incoming = [];
    const waiting = [];
    pc.addEventListener("datachannel", (event) => {
      const resolve = waiting.shift();
      if (resolve) resolve(event.channel);
      else incoming.push(event.channel);
    });
    const accept = () =>
      incoming.length ? Promise.resolve(incoming.shift()) : new Promise((resolve) => waiting.push(resolve));
    return add(peers, { pc, accept });
  };
  const addChannel = (dc) => add(channels, { dc, inbox: new Inbox(dc) });
  return { peers, channels, peer, channel, addPeer, addChannel };
}

export function mirror(options = {}, s = state(options)) {
  return {
    CreatePeer: { sync: () => s.addPeer() },
    CreateChannel: {
      sync: ({ peer, label }) => attempt(() => s.addChannel(s.peer(peer).pc.createDataChannel(label))),
    },
    AcceptChannel: {
      async: (peer) => attemptAsync(async () => s.addChannel(await s.peer(peer).accept())),
    },
    CreateOffer: {
      async: (peer) =>
        attemptAsync(async () => {
          const { pc } = s.peer(peer);
          await pc.setLocalDescription(await pc.createOffer());
          await gathered(pc);
          return pc.localDescription.sdp;
        }),
    },
    CreateAnswer: {
      async: ({ peer, offer }) =>
        attemptAsync(async () => {
          const { pc } = s.peer(peer);
          await pc.setRemoteDescription({ type: "offer", sdp: offer });
          await pc.setLocalDescription(await pc.createAnswer());
          await gathered(pc);
          return pc.localDescription.sdp;
        }),
    },
    SetAnswer: {
      async: ({ peer, answer }) =>
        attemptAsync(async () => {
          await s.peer(peer).pc.setRemoteDescription({ type: "answer", sdp: answer });
          return b.unit;
        }),
    },
    WaitOpen: {
      async: (channel) =>
        attemptAsync(async () => {
          await opened(s.channel(channel).dc);
          return b.unit;
        }),
    },
    Send: {
      sync: ({ channel, data }) =>
        attempt(() => {
          s.channel(channel).dc.send(data);
          return b.unit;
        }),
    },
    Receive: {
      async: (channel) => attemptAsync(async () => (await s.channel(channel).inbox.take(1)).shift()),
    },
    Close: {
      sync: (id) => {
        const peer = s.peers.get(id);
        if (peer) peer.pc.close();
        const channel = s.channels.get(id);
        if (channel) channel.dc.close();
        return b.unit;
      },
    },
  };
}

/// Mirror, with many messages sent or received in one effect.
export function batch(options = {}) {
  const s = state(options);
  return {
    ...mirror(options, s),
    SendAll: {
      sync: ({ channel, messages }) =>
        attempt(() => {
          const dc = s.channel(channel).dc;
          while (messages.length !== 0) {
            dc.send(messages[0]);
            messages = messages[1];
          }
          return b.unit;
        }),
    },
    ReceiveAll: {
      async: ({ channel, min }) => attemptAsync(async () => b.list(await s.channel(channel).inbox.take(min))),
    },
  };
}

/// Offers and answers are tokens, the description with every candidate.
export function session(options = {}) {
  const s = state(options);
  const sessions = new Map();
  let next = 1;
  const encode = (sdp) => btoa(sdp);
  const decode = (token) => atob(token);
  const get = (id) => {
    const value = sessions.get(id);
    if (value === undefined) throw new Error("unknown session " + id);
    return value;
  };
  return {
    Offer: {
      async: (label) =>
        attemptAsync(async () => {
          const peer = s.peer(s.addPeer());
          const dc = peer.pc.createDataChannel(label);
          const id = next++;
          sessions.set(id, { pc: peer.pc, dc, inbox: new Inbox(dc) });
          await peer.pc.setLocalDescription(await peer.pc.createOffer());
          await gathered(peer.pc);
          return { session: id, token: encode(peer.pc.localDescription.sdp) };
        }),
    },
    Accept: {
      async: (token) =>
        attemptAsync(async () => {
          const peer = s.peer(s.addPeer());
          const id = next++;
          const entry = { pc: peer.pc, dc: null, inbox: null };
          sessions.set(id, entry);
          entry.ready = peer.accept().then((dc) => {
            entry.dc = dc;
            entry.inbox = new Inbox(dc);
          });
          await peer.pc.setRemoteDescription({ type: "offer", sdp: decode(token) });
          await peer.pc.setLocalDescription(await peer.pc.createAnswer());
          await gathered(peer.pc);
          return { session: id, token: encode(peer.pc.localDescription.sdp) };
        }),
    },
    Connect: {
      async: ({ session, token }) =>
        attemptAsync(async () => {
          await get(session).pc.setRemoteDescription({ type: "answer", sdp: decode(token) });
          return b.unit;
        }),
    },
    Ready: {
      async: (session) =>
        attemptAsync(async () => {
          const entry = get(session);
          if (entry.ready) await entry.ready;
          await opened(entry.dc);
          return b.unit;
        }),
    },
    Send: {
      sync: ({ session, data }) =>
        attempt(() => {
          const entry = get(session);
          if (entry.dc === null) throw new Error("session not ready");
          entry.dc.send(data);
          return b.unit;
        }),
    },
    Receive: {
      async: (session) =>
        attemptAsync(async () => {
          const entry = get(session);
          if (entry.ready) await entry.ready;
          return (await entry.inbox.take(1)).shift();
        }),
    },
  };
}
