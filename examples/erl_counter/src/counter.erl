%% One supervised counter. Timer references make cancelled, queued ticks harmless.
-module(counter).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link(Name) ->
    gen_server:start_link(?MODULE, Name, []).

init(Name) ->
    {ok, schedule(#{model => counter_state:new(Name)})}.

handle_call(get_value, _From, State = #{model := Model}) ->
    {reply, {ok, counter_state:value(Model)}, State};
handle_call({set_tick_rate, Seconds}, _From, State = #{timer := Timer, model := Model}) ->
    erlang:cancel_timer(Timer),
    {reply, ok, schedule(State#{model := counter_state:with_rate(Model, Seconds)})}.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info({timeout, Timer, tick}, State = #{timer := Timer, model := Model}) ->
    {noreply, schedule(State#{model := counter_state:tick(Model)})};
handle_info(_Message, State) ->
    {noreply, State}.

schedule(State = #{model := Model}) ->
    Seconds = counter_state:seconds(Model),
    State#{timer => erlang:start_timer(Seconds * 1000, self(), tick)}.
