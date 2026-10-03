-module(counters_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    counters_eyg:load_packages(),
    counters_sup:start_link().

stop(_State) ->
    ok.
