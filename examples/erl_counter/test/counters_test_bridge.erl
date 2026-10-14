%% Native test lifecycle and sys inspection; test decisions are Gleam.
-module(counters_test_bridge).
-export([start_app/0, set_fixture/1, clear_fixture/0, stop_session/1, timer/1]).

start_app() -> {ok, _} = application:ensure_all_started(erl_counter), nil.
set_fixture(Fetch) ->
    application:set_env(erl_counter, hub, <<"https://hub.test">>),
    application:set_env(erl_counter, package_fetch, Fetch), nil.
clear_fixture() ->
    application:unset_env(erl_counter, hub),
    application:unset_env(erl_counter, package_fetch), nil.
stop_session(Pid) -> gen_server:stop(Pid), nil.
timer(Name) ->
    {Name, Pid, worker, _} = lists:keyfind(Name, 1, supervisor:which_children(counters_sup)),
    {ok, {Pid, maps:get(timer, sys:get_state(Pid))}}.
