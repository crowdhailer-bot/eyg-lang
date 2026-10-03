%% Check and run EYG scripts that use only the counters effects.
-module(counters_eyg).

-export([check/1, run/1, load_packages/0]).

%% Type check a script, print its type or any errors.
check(Source) ->
    case eyg_beam:check(to_binary(Source), counters_effects:effects(), packages()) of
        {ok, Type} -> io:format("~ts~n", [Type]), ok;
        {error, Errors} -> io:format("~ts~n", [Errors]), error
    end.

%% Type check a script then run it, effects are handled by `counters_effects`.
run(Source) ->
    Handler = fun counters_effects:handle/2,
    case eyg_beam:run(to_binary(Source), counters_effects:effects(), packages(), Handler) of
        {ok, Value} -> io:format("~ts~n", [eyg_beam:inspect(Value)]), {ok, Value};
        {error, Errors} -> io:format("~ts~n", [Errors]), error
    end.

%% Make `@standard` available to scripts.
load_packages() ->
    Path = application:get_env(counters, standard, "../../eyg_packages/standard/index.eyg.json"),
    {ok, Json} = file:read_file(Path),
    {ok, Standard} = eyg_beam:load_package(Json),
    persistent_term:put({?MODULE, packages}, #{<<"standard">> => Standard}).

packages() ->
    persistent_term:get({?MODULE, packages}).

to_binary(Source) ->
    unicode:characters_to_binary(Source).
