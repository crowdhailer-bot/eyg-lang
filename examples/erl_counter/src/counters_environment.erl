%% Application configuration is native OTP glue; loading is implemented in Gleam.
-module(counters_environment).
-export([loader/0]).

loader() ->
    Hub = unicode:characters_to_binary(application:get_env(erl_counter, hub, <<"https://eyg.run">>)),
    {loader, Hub, Fetch, Hash} = eyg@embedding@beam:loader(Hub),
    {loader, Hub, application:get_env(erl_counter, package_fetch, Fetch), Hash}.
