//// OpenTUI's shared TreeSitterClient and native asynchronous methods.

import gleam/dynamic.{type Dynamic}
import gleam/javascript/promise.{type Promise}

pub type TreeSitterClient

@external(javascript, "../tree_sitter.ffi.mjs", "initialize")
pub fn initialize(client: TreeSitterClient) -> Promise(Result(Nil, String))

@external(javascript, "../tree_sitter.ffi.mjs", "get")
pub fn get() -> Result(TreeSitterClient, String)

@external(javascript, "../tree_sitter.ffi.mjs", "preloadParser")
pub fn preload_parser(
  client: TreeSitterClient,
  filetype: String,
) -> Promise(Result(Bool, String))

@external(javascript, "../tree_sitter.ffi.mjs", "getPerformance")
pub fn get_performance(
  client: TreeSitterClient,
) -> Promise(Result(Dynamic, String))
