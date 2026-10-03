-module(counters_eyg_test).
-include_lib("eunit/include/eunit.hrl").

counters_test_() ->
    {setup,
        fun() -> {ok, Apps} = application:ensure_all_started(counters), Apps end,
        fun(Apps) -> [application:stop(App) || App <- lists:reverse(Apps)] end,
        [
            fun check_accepts_counter_effects/0,
            fun check_rejects_other_effects/0,
            fun run_single_effect/0,
            fun run_many_effects/0,
            fun run_with_standard_library/0,
            fun run_does_not_start_badly_typed_scripts/0
        ]}.

check_accepts_counter_effects() ->
    ?assertEqual(ok, counters_eyg:check("perform GetValue(\"x\")")).

check_rejects_other_effects() ->
    ?assertEqual(error, counters_eyg:check("perform Log(\"x\")")).

run_single_effect() ->
    ?assertEqual({ok, ok_unit()}, counters_eyg:run("perform StartCounter(\"one\")")),
    ?assertMatch([_], supervisor:which_children(counters_sup)),
    ?assertEqual({ok, ok_unit()}, counters_eyg:run("perform Shutdown(\"one\")")),
    ?assertEqual([], supervisor:which_children(counters_sup)).

run_many_effects() ->
    Script =
        "let _ = perform StartCounter(\"two\")\n"
        "let _ = perform SetTickRate({name: \"two\", seconds: 1})\n"
        "perform GetValue(\"two\")",
    ?assertEqual({ok, {tagged, <<"Ok">>, {integer, 0}}}, counters_eyg:run(Script)),
    timer:sleep(1100),
    ?assertEqual({ok, 1}, counters_api:get_value(<<"two">>)),
    ok = counters_api:shutdown(<<"two">>).

run_with_standard_library() ->
    Script =
        "@standard.list.map([\"a\", \"b\", \"c\"], (name) -> {\n"
        "  perform StartCounter(name)\n"
        "})",
    ?assertEqual({ok, {linked_list, [ok_unit(), ok_unit(), ok_unit()]}}, counters_eyg:run(Script)),
    ?assertMatch([_, _, _], supervisor:which_children(counters_sup)),
    [ok = counters_api:shutdown(Name) || Name <- [<<"a">>, <<"b">>, <<"c">>]].

run_does_not_start_badly_typed_scripts() ->
    ?assertEqual(error, counters_eyg:run("let _ = perform StartCounter(\"three\")\nperform GetValue(3)")),
    ?assertEqual({error, not_found}, counters_api:get_value(<<"three">>)).

ok_unit() ->
    {tagged, <<"Ok">>, {record, #{}}}.
