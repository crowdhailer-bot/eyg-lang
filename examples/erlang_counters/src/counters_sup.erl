%% A dynamic supervisor, every child is a counter started on demand.
-module(counters_sup).
-behaviour(supervisor).

-export([start_link/0, start_child/1]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_child(Name) ->
    supervisor:start_child(?MODULE, [Name]).

init([]) ->
    Flags = #{strategy => simple_one_for_one},
    Counter = #{
        id => counter,
        start => {counter, start_link, []},
        restart => transient
    },
    {ok, {Flags, [Counter]}}.
