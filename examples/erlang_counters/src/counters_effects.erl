%% EYG effects for the counters API.
%% Each effect has the type of the value lifted from a program and the type
%% of the reply, then a clause in `handle/2` that implements it.
-module(counters_effects).

-export([effects/0, handle/2]).

-define(UNIT, {record, empty}).

effects() ->
    Reply = eyg_beam:result_type(?UNIT, string),
    [
        {<<"StartCounter">>, {string, Reply}},
        {<<"SetTickRate">>, {eyg_beam:record_type([{<<"name">>, string}, {<<"seconds">>, integer}]), Reply}},
        {<<"GetValue">>, {string, eyg_beam:result_type(integer, string)}},
        {<<"Shutdown">>, {string, Reply}}
    ].

handle(<<"StartCounter">>, {string, Name}) ->
    reply(Name, counters_api:start_counter(Name));
handle(<<"SetTickRate">>, {record, #{<<"name">> := {string, Name}, <<"seconds">> := {integer, Seconds}}}) ->
    reply(Name, counters_api:set_tick_rate(Name, Seconds));
handle(<<"GetValue">>, {string, Name}) ->
    reply(Name, counters_api:get_value(Name));
handle(<<"Shutdown">>, {string, Name}) ->
    reply(Name, counters_api:shutdown(Name)).

reply(_Name, ok) -> {tagged, <<"Ok">>, {record, #{}}};
reply(_Name, {ok, Value}) -> {tagged, <<"Ok">>, {integer, Value}};
reply(Name, {error, Reason}) -> {tagged, <<"Error">>, {string, message(Name, Reason)}}.

message(Name, already_started) -> <<"counter ", Name/binary, " is already started">>;
message(Name, not_found) -> <<"no counter named ", Name/binary>>;
message(_Name, invalid_rate) -> <<"seconds must be a positive integer">>.
