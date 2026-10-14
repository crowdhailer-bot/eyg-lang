%% Marshal OTP return values into Gleam Results. No interpreter or policy logic.
-module(counters_bridge).
-export([start_counter/1, set_tick_rate/2, get_value/1, shutdown/1]).

start_counter(Name) -> unit(counters_api:start_counter(Name)).
set_tick_rate(Name, Seconds) -> unit(counters_api:set_tick_rate(Name, Seconds)).
get_value(Name) -> counters_api:get_value(Name).
shutdown(Name) -> unit(counters_api:shutdown(Name)).

unit(ok) -> {ok, nil};
unit(Error) -> Error.
