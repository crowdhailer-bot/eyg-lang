//// Phoenix hooks marshal native lifecycle callbacks; application behavior is Gleam.

import gleam/dynamic.{type Dynamic}
import plinthx/browser/node

pub type LiveSocket

pub type Hook

pub type HookDefinition

@external(javascript, "./phoenix_ffi.mjs", "hook")
pub fn hook(mounted: fn(Hook) -> fn() -> Nil) -> HookDefinition

@external(javascript, "./phoenix_ffi.mjs", "element")
pub fn element(hook: Hook) -> node.Node

@external(javascript, "./phoenix_ffi.mjs", "handleEvent")
pub fn handle_event(
  hook: Hook,
  name: String,
  handler: fn(Dynamic) -> Nil,
) -> Nil

@external(javascript, "./phoenix_ffi.mjs", "newSocket")
pub fn new_socket(
  path: String,
  csrf: String,
  fallback_ms: Int,
  hooks: List(#(String, HookDefinition)),
) -> LiveSocket

@external(javascript, "./phoenix_ffi.mjs", "connect")
pub fn connect(socket: LiveSocket) -> Nil

@external(javascript, "./phoenix_ffi.mjs", "disconnect")
pub fn disconnect(socket: LiveSocket) -> Nil
