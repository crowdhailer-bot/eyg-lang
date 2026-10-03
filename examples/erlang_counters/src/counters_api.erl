%% The public API of the counters application.
%% Counters are named, the name is registered across the cluster.
-module(counters_api).

-export([start_counter/1, set_tick_rate/2, get_value/1, shutdown/1]).

start_counter(Name) ->
    case counters_sup:start_child(Name) of
        {ok, _Pid} -> ok;
        {error, {already_started, _Pid}} -> {error, already_started}
    end.

%% Tick every `Seconds` seconds.
set_tick_rate(_Name, Seconds) when not is_integer(Seconds); Seconds < 1 ->
    {error, invalid_rate};
set_tick_rate(Name, Seconds) ->
    with_counter(Name, fun(Pid) -> gen_server:call(Pid, {set_tick_rate, Seconds}) end).

get_value(Name) ->
    with_counter(Name, fun(Pid) -> gen_server:call(Pid, get_value) end).

shutdown(Name) ->
    with_counter(Name, fun(Pid) -> supervisor:terminate_child(counters_sup, Pid) end).

with_counter(Name, Fun) ->
    case global:whereis_name({counter, Name}) of
        undefined -> {error, not_found};
        Pid -> Fun(Pid)
    end.
