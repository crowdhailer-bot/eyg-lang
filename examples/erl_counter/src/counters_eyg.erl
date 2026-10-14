%% Native shell conveniences delegate runtime logic to Gleam.
-module(counters_eyg).
-export([check/1, check/2, run/1, run/2]).

check(Source) -> print(check(Source, eyg@hub@cache:empty()), type).
check(Source, Cache) -> counters_scripts:check(unicode:characters_to_binary(Source), Cache).
run(Source) -> print(run(Source, eyg@hub@cache:empty()), value).
run(Source, Cache) -> counters_scripts:run(unicode:characters_to_binary(Source), Cache).

print({Result, _Cache} = Return, Kind) ->
    Text = case {Result, Kind} of
        {{ok, Value}, value} -> eyg@embedding@runtime:inspect(Value);
        {{ok, Type}, type} -> Type;
        {{error, Message}, _} -> Message
    end,
    io:format("~ts~n", [Text]),
    Return.
