import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

export function hook(mounted) {
  return {
    mounted() { this.gleamCleanup = mounted(this); },
    destroyed() { this.gleamCleanup?.(); },
  };
}
export const element = hook => hook.el;
export const handleEvent = (hook, name, handler) => { hook.handleEvent(name, handler); };
export const newSocket = (path, csrf, fallback, hooks) => new LiveSocket(path, Socket, {
  params: { _csrf_token: csrf }, longPollFallbackMs: fallback, hooks: Object.fromEntries(hooks),
});
export const connect = socket => { socket.connect(); };
export const disconnect = socket => { socket.disconnect(); };
