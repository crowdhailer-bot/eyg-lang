import ash_eyg/actions
import ash_eyg/runtime
import ash_eyg/type_
import eyg/hub/cache
import eyg/interpreter/state
import eyg/parser/parser.{type Span}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import midas/effect

pub type AshError

@external(erlang, "Elixir.AshEyg.Test.Native", "effects")
pub fn effects() -> List(runtime.NativeEffect)

@external(erlang, "Elixir.AshEyg.Test.Native", "named")
pub fn named() -> List(runtime.NativeEffect)

@external(erlang, "Elixir.AshEyg.Test.Native", "label")
pub fn label(effect: runtime.NativeEffect) -> String

@external(erlang, "Elixir.AshEyg.Test.Native", "action")
pub fn action(effect: runtime.NativeEffect) -> String

@external(erlang, "Elixir.AshEyg.Test.Native", "check")
pub fn check(
  source: String,
  cache: cache.Cache(Span),
  effects: List(runtime.NativeEffect),
) -> #(Result(String, String), cache.Cache(Span))

@external(erlang, "Elixir.AshEyg.Test.Native", "run")
pub fn run(
  source: String,
  cache: cache.Cache(Span),
  effects: List(runtime.NativeEffect),
  actor: Dynamic,
) -> #(Result(state.Value(Span), String), cache.Cache(Span))

@external(erlang, "Elixir.AshEyg.Test.Native", "admin")
pub fn admin() -> Dynamic

@external(erlang, "Elixir.AshEyg.Test.Native", "no_actor")
pub fn no_actor() -> Dynamic

@external(erlang, "Elixir.AshEyg.Test.Native", "option")
pub fn options(effects: List(runtime.NativeEffect)) -> runtime.Options

@external(erlang, "Elixir.AshEyg.Test.Native", "session")
pub fn session() -> Result(process.Pid, Dynamic)

@external(erlang, "Elixir.AshEyg.Test.Native", "stop")
pub fn stop(pid: process.Pid) -> Nil

@external(erlang, "Elixir.AshEyg.Test.Native", "check_session")
pub fn check_session(
  pid: process.Pid,
  source: String,
  effects: List(runtime.NativeEffect),
) -> Result(String, String)

@external(erlang, "Elixir.AshEyg.Test.Native", "run_session")
pub fn run_session(
  pid: process.Pid,
  source: String,
  effects: List(runtime.NativeEffect),
) -> Result(state.Value(Span), String)

@external(erlang, "Elixir.AshEyg.Test.Native", "generic")
pub fn generic(source: String, actor: Dynamic) -> Result(String, AshError)

@external(erlang, "Elixir.AshEyg.Test.Native", "invalid_argument")
pub fn invalid_argument(error: AshError) -> #(String, String)

@external(erlang, "Elixir.AshEyg.Test.Native", "fixture")
pub fn fixture(fetch: effect.Fetch(Nil)) -> Nil

@external(erlang, "Elixir.AshEyg.Test.Native", "clear_fixture")
pub fn clear_fixture() -> Nil

@external(erlang, "Elixir.AshEyg.Native", "effect")
pub fn effect(effect: runtime.NativeEffect) -> actions.Effect(m, context)

@external(erlang, "Elixir.AshEyg.Test.Native", "raw")
pub fn raw(value: a) -> type_.HostValue

@external(erlang, "Elixir.AshEyg.Test.Native", "host_effect")
pub fn host_effect(value: actions.Effect(m, context)) -> runtime.NativeEffect
