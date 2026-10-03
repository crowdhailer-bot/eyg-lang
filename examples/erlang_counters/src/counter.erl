%% A counter that adds one to its value on every tick.
-module(counter).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(DEFAULT_SECONDS, 10).

start_link(Name) ->
    gen_server:start_link(via(Name), ?MODULE, Name, []).

via(Name) ->
    {via, global, {counter, Name}}.

init(Name) ->
    State = #{name => Name, value => 0, seconds => ?DEFAULT_SECONDS, timer => undefined},
    {ok, schedule(State)}.

handle_call(get_value, _From, State = #{value := Value}) ->
    {reply, {ok, Value}, State};
handle_call({set_tick_rate, Seconds}, _From, State = #{timer := Timer}) ->
    erlang:cancel_timer(Timer),
    {reply, ok, schedule(State#{seconds := Seconds})}.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info(tick, State = #{value := Value}) ->
    {noreply, schedule(State#{value := Value + 1})}.

schedule(State = #{seconds := Seconds}) ->
    State#{timer := erlang:send_after(Seconds * 1000, self(), tick)}.
