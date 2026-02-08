#!/usr/bin/env escript
%% Gleam/Erlang interop script: generates and verifies CBOR fixtures using gleebor

main(Args) ->
    %% Add gleebor's build output to the code path
    ScriptDir = filename:dirname(escript:script_name()),
    ProjectDir = filename:dirname(ScriptDir),
    code:add_pathsz(filelib:wildcard(ProjectDir ++ "/build/dev/erlang/*/ebin")),

    case Args of
        ["generate", Dir] -> generate(Dir);
        ["generate"]      -> generate("fixtures/gleam");
        ["verify", Dir, Source] -> verify(Dir, Source);
        ["verify", Dir]   -> verify(Dir, Dir);
        _ ->
            io:format("Usage: gleam_interop.escript <generate|verify> [dir] [source]~n"),
            halt(1)
    end.

generate(Dir) ->
    filelib:ensure_dir(Dir ++ "/x"),
    Write = fun(Name, Bytes) ->
        file:write_file(Dir ++ "/" ++ Name ++ ".cbor", Bytes)
    end,

    Write("int_zero",      gleebor:encode_int(0)),
    Write("int_small",     gleebor:encode_int(23)),
    Write("int_u8",        gleebor:encode_int(200)),
    Write("int_u16",       gleebor:encode_int(1000)),
    Write("int_u32",       gleebor:encode_int(1000000)),
    Write("int_neg_small", gleebor:encode_int(-10)),
    Write("int_neg_500",   gleebor:encode_int(-500)),

    Write("float_1_5", gleebor:encode_float(1.5)),
    Write("float_neg",  gleebor:encode_float(-273.15)),

    Write("string_empty", gleebor:encode_string(<<"">>)),
    Write("string_hello", gleebor:encode_string(<<"hello">>)),

    Write("bytes_empty", gleebor:encode_bytes(<<>>)),
    Write("bytes_small", gleebor:encode_bytes(<<1,2,3,4,5>>)),

    Write("bool_true",  gleebor:encode_bool(true)),
    Write("bool_false", gleebor:encode_bool(false)),
    Write("null",        gleebor:encode_null()),

    Write("array_ints",  gleebor:encode_list([1, 2, 3], fun gleebor:encode_int/1)),
    Write("array_empty", gleebor:encode_list([], fun gleebor:encode_int/1)),
    Write("array_strings", gleebor:encode_list([<<"hello">>, <<"world">>],
                                               fun gleebor:encode_string/1)),
    %% [[1,2],[3,4]]
    Write("array_nested",
          gleebor:encode_list(
              [[1,2], [3,4]],
              fun(Inner) -> gleebor:encode_list(Inner, fun gleebor:encode_int/1) end)),

    Write("map_simple", gleebor:encode_map(
        [{<<"a">>, 1}, {<<"b">>, 2}],
        fun gleebor:encode_string/1,
        fun gleebor:encode_int/1
    )),
    Write("map_empty", gleebor:encode_map(
        [],
        fun gleebor:encode_string/1,
        fun gleebor:encode_int/1
    )),
    %% {"outer": {"inner": 42}}
    Write("map_nested", gleebor:encode_map(
        [{<<"outer">>, [{<<"inner">>, 42}]}],
        fun gleebor:encode_string/1,
        fun(InnerPairs) ->
            gleebor:encode_map(InnerPairs,
                fun gleebor:encode_string/1,
                fun gleebor:encode_int/1)
        end
    )),
    %% {"nums": [1,2,3]}
    Write("map_array_vals", gleebor:encode_map(
        [{<<"nums">>, [1, 2, 3]}],
        fun gleebor:encode_string/1,
        fun(Vals) -> gleebor:encode_list(Vals, fun gleebor:encode_int/1) end
    )),

    %% Tag 1 wrapping integer 1000000
    TagEpoch = <<(gleebor:encode_tag(1))/binary, (gleebor:encode_int(1000000))/binary>>,
    Write("tag_epoch", TagEpoch),
    %% Tag 32 wrapping string
    TagUri = <<(gleebor:encode_tag(32))/binary,
               (gleebor:encode_string(<<"https://example.com">>))/binary>>,
    Write("tag_uri", TagUri),
    %% Tag 1000 wrapping array [1,2,3]
    TagArray = <<(gleebor:encode_tag(1000))/binary,
                 (gleebor:encode_list([1,2,3], fun gleebor:encode_int/1))/binary>>,
    Write("tag_array", TagArray),

    io:format("  Generated fixtures in ~s/~n", [Dir]).

verify(Dir, Source) ->
    case filelib:is_dir(Dir) of
        false ->
            io:format("  Skipping ~s fixtures (not found: ~s)~n", [Source, Dir]),
            ok;
        true ->
            {Passed, Failed} = run_checks(Dir, 0, 0),
            io:format("  Verified ~s fixtures: ~p passed, ~p failed~n", [Source, Passed, Failed]),
            case Failed > 0 of
                true -> halt(1);
                false -> ok
            end
    end.

run_checks(Dir, P, F) ->
    Checks = [
        {"int_zero",      fun(B) -> expect_int(B, 0) end},
        {"int_small",     fun(B) -> expect_int(B, 23) end},
        {"int_u8",        fun(B) -> expect_int(B, 200) end},
        {"int_u16",       fun(B) -> expect_int(B, 1000) end},
        {"int_u32",       fun(B) -> expect_int(B, 1000000) end},
        {"int_neg_small", fun(B) -> expect_int(B, -10) end},
        {"int_neg_500",   fun(B) -> expect_int(B, -500) end},
        {"float_1_5",     fun(B) -> expect_float(B, 1.5) end},
        {"float_neg",     fun(B) -> expect_float(B, -273.15) end},
        {"string_empty",  fun(B) -> expect_string(B, <<"">>) end},
        {"string_hello",  fun(B) -> expect_string(B, <<"hello">>) end},
        {"bytes_empty",   fun(B) -> expect_bytes(B, <<>>) end},
        {"bytes_small",   fun(B) -> expect_bytes(B, <<1,2,3,4,5>>) end},
        {"bool_true",     fun(B) -> expect_bool(B, true) end},
        {"bool_false",    fun(B) -> expect_bool(B, false) end},
        {"null",          fun(B) -> expect_null(B) end},
        {"array_ints",    fun(B) -> expect_flat_int_list(B, [1,2,3]) end},
        {"array_empty",   fun(B) -> expect_flat_int_list(B, []) end},
        {"array_strings", fun(B) -> expect_flat_string_list(B, [<<"hello">>,<<"world">>]) end},
        {"array_nested",  fun(B) -> expect_nested_int_lists(B, [[1,2],[3,4]]) end},
        {"map_simple",    fun(B) -> expect_map_simple(B) end},
        {"map_empty",     fun(B) -> expect_map_empty(B) end},
        {"map_nested",    fun(B) -> expect_map_nested(B) end},
        {"map_array_vals",fun(B) -> expect_map_array_vals(B) end},
        {"tag_epoch",     fun(B) -> expect_tag(B, 1, fun(R) -> expect_int_val(R, 1000000) end) end},
        {"tag_uri",       fun(B) -> expect_tag(B, 32, fun(R) -> expect_string_val(R, <<"https://example.com">>) end) end},
        {"tag_array",     fun(B) -> expect_tag(B, 1000, fun(R) -> expect_flat_int_list(R, [1,2,3]) end) end}
    ],
    lists:foldl(
        fun({Name, CheckFun}, {PAcc, FAcc}) ->
            Path = Dir ++ "/" ++ Name ++ ".cbor",
            case file:read_file(Path) of
                {ok, Data} ->
                    case CheckFun(Data) of
                        ok -> {PAcc + 1, FAcc};
                        {error, Reason} ->
                            io:format("  FAIL ~s: ~p~n", [Name, Reason]),
                            {PAcc, FAcc + 1}
                    end;
                {error, enoent} ->
                    io:format("  SKIP ~s: file not found~n", [Name]),
                    {PAcc, FAcc}
            end
        end,
        {P, F},
        Checks
    ).

%% ---------------------------------------------------------------------------
%% Scalar expectations
%% ---------------------------------------------------------------------------

expect_int(Bin, Expected) ->
    case gleebor:decode_int(Bin) of
        {ok, {Expected, <<>>}} -> ok;
        {ok, {Got, _}} -> {error, {expected, Expected, got, Got}};
        {error, E} -> {error, E}
    end.

expect_int_val(Bin, Expected) ->
    case gleebor:decode_int(Bin) of
        {ok, {Expected, Rest}} -> {ok, Rest};
        {ok, {Got, _}} -> {error, {expected, Expected, got, Got}};
        {error, E} -> {error, E}
    end.

expect_float(Bin, Expected) ->
    case gleebor:decode_float(Bin) of
        {ok, {Val, <<>>}} when abs(Val - Expected) < 0.001 -> ok;
        {ok, {Got, _}} -> {error, {expected, Expected, got, Got}};
        {error, E} -> {error, E}
    end.

expect_string(Bin, Expected) ->
    case gleebor:decode_string(Bin) of
        {ok, {Expected, <<>>}} -> ok;
        {ok, {Got, _}} -> {error, {expected, Expected, got, Got}};
        {error, E} -> {error, E}
    end.

expect_string_val(Bin, Expected) ->
    case gleebor:decode_string(Bin) of
        {ok, {Expected, Rest}} -> {ok, Rest};
        {ok, {Got, _}} -> {error, {expected, Expected, got, Got}};
        {error, E} -> {error, E}
    end.

expect_bytes(Bin, Expected) ->
    case gleebor:decode_bytes(Bin) of
        {ok, {Expected, <<>>}} -> ok;
        {ok, {Got, _}} -> {error, {expected, Expected, got, Got}};
        {error, E} -> {error, E}
    end.

expect_bool(Bin, Expected) ->
    case gleebor:decode_bool(Bin) of
        {ok, {Expected, <<>>}} -> ok;
        {ok, {Got, _}} -> {error, {expected, Expected, got, Got}};
        {error, E} -> {error, E}
    end.

expect_null(Bin) ->
    case gleebor:decode_null(Bin) of
        {ok, {nil, <<>>}} -> ok;
        {error, E} -> {error, E}
    end.

%% ---------------------------------------------------------------------------
%% Collect a yielder into a list of values (discarding per-element rest bytes).
%% Returns the remaining bytes from the last element, or the bytes after an
%% empty-list header (extracted by re-parsing the header manually).
%% ---------------------------------------------------------------------------

yielder_collect(Yielder) ->
    Items = 'gleam@yielder':to_list(Yielder),
    collect_results(Items, []).

collect_results([], Acc) -> {ok, lists:reverse(Acc)};
collect_results([{ok, {Val, _Rest}} | T], Acc) -> collect_results(T, [Val | Acc]);
collect_results([{error, E} | _], _) -> {error, E}.

%% ---------------------------------------------------------------------------
%% Array expectations
%% ---------------------------------------------------------------------------

expect_flat_int_list(Bin, Expected) ->
    case gleebor:decode_list(Bin, fun gleebor:decode_int/1) of
        {ok, Yielder} ->
            case yielder_collect(Yielder) of
                {ok, Expected} -> ok;
                {ok, Got} -> {error, {expected, Expected, got, Got}};
                {error, E} -> {error, E}
            end;
        {error, E} -> {error, E}
    end.

expect_flat_string_list(Bin, Expected) ->
    case gleebor:decode_list(Bin, fun gleebor:decode_string/1) of
        {ok, Yielder} ->
            case yielder_collect(Yielder) of
                {ok, Expected} -> ok;
                {ok, Got} -> {error, {expected, Expected, got, Got}};
                {error, E} -> {error, E}
            end;
        {error, E} -> {error, E}
    end.

%% For nested arrays like [[1,2],[3,4]], we need a callback that decodes an
%% inner int list and returns {ok, {CollectedList, RemainingBytes}}.
%% Since decode_list returns a Yielder (not DecodeResult), we manually parse
%% the inner array header and items.
decode_inner_int_list(Bin) ->
    case parse_array_header(Bin) of
        {ok, {Count, Rest}} -> decode_n_ints(Count, Rest, []);
        {error, E} -> {error, E}
    end.

parse_array_header(<<4:3, V:5, Rest/bits>>) when V < 24 ->
    {ok, {V, Rest}};
parse_array_header(<<4:3, 24:5, V:8, Rest/bits>>) ->
    {ok, {V, Rest}};
parse_array_header(<<4:3, 25:5, V:16, Rest/bits>>) ->
    {ok, {V, Rest}};
parse_array_header(<<4:3, 26:5, V:32, Rest/bits>>) ->
    {ok, {V, Rest}};
parse_array_header(<<4:3, 27:5, V:64, Rest/bits>>) ->
    {ok, {V, Rest}};
parse_array_header(_) ->
    {error, bad_array_header}.

decode_n_ints(0, Rest, Acc) -> {ok, {lists:reverse(Acc), Rest}};
decode_n_ints(N, Bin, Acc) ->
    case gleebor:decode_int(Bin) of
        {ok, {Val, Rest}} -> decode_n_ints(N - 1, Rest, [Val | Acc]);
        {error, E} -> {error, E}
    end.

expect_nested_int_lists(Bin, Expected) ->
    case gleebor:decode_list(Bin, fun decode_inner_int_list/1) of
        {ok, Yielder} ->
            case yielder_collect(Yielder) of
                {ok, Expected} -> ok;
                {ok, Got} -> {error, {expected, Expected, got, Got}};
                {error, E} -> {error, E}
            end;
        {error, E} -> {error, E}
    end.

%% ---------------------------------------------------------------------------
%% Map expectations
%% ---------------------------------------------------------------------------

expect_map_simple(Bin) ->
    case gleebor:decode_map(Bin, fun gleebor:decode_string/1, fun gleebor:decode_int/1) of
        {ok, Yielder} ->
            case yielder_collect(Yielder) of
                {ok, Pairs} ->
                    HasA = lists:member({<<"a">>, 1}, Pairs),
                    HasB = lists:member({<<"b">>, 2}, Pairs),
                    case HasA andalso HasB andalso length(Pairs) == 2 of
                        true -> ok;
                        false -> {error, {unexpected_pairs, Pairs}}
                    end;
                {error, E} -> {error, E}
            end;
        {error, E} -> {error, E}
    end.

expect_map_empty(Bin) ->
    case gleebor:decode_map(Bin, fun gleebor:decode_string/1, fun gleebor:decode_int/1) of
        {ok, Yielder} ->
            case yielder_collect(Yielder) of
                {ok, []} -> ok;
                {ok, Got} -> {error, {expected_empty, got, Got}};
                {error, E} -> {error, E}
            end;
        {error, E} -> {error, E}
    end.

%% {"outer": {"inner": 42}} — value decoder must handle inner map
decode_inner_string_int_map(Bin) ->
    case parse_map_header(Bin) of
        {ok, {Count, Rest}} -> decode_n_string_int_pairs(Count, Rest, []);
        {error, E} -> {error, E}
    end.

parse_map_header(<<5:3, V:5, Rest/bits>>) when V < 24 ->
    {ok, {V, Rest}};
parse_map_header(<<5:3, 24:5, V:8, Rest/bits>>) ->
    {ok, {V, Rest}};
parse_map_header(<<5:3, 25:5, V:16, Rest/bits>>) ->
    {ok, {V, Rest}};
parse_map_header(<<5:3, 26:5, V:32, Rest/bits>>) ->
    {ok, {V, Rest}};
parse_map_header(<<5:3, 27:5, V:64, Rest/bits>>) ->
    {ok, {V, Rest}};
parse_map_header(_) ->
    {error, bad_map_header}.

decode_n_string_int_pairs(0, Rest, Acc) -> {ok, {lists:reverse(Acc), Rest}};
decode_n_string_int_pairs(N, Bin, Acc) ->
    case gleebor:decode_string(Bin) of
        {ok, {Key, Rest}} ->
            case gleebor:decode_int(Rest) of
                {ok, {Val, Rest2}} ->
                    decode_n_string_int_pairs(N - 1, Rest2, [{Key, Val} | Acc]);
                {error, E} -> {error, E}
            end;
        {error, E} -> {error, E}
    end.

expect_map_nested(Bin) ->
    %% Decode outer map with string keys and inner-map values
    case gleebor:decode_map(Bin, fun gleebor:decode_string/1,
                            fun decode_inner_string_int_map/1) of
        {ok, Yielder} ->
            case yielder_collect(Yielder) of
                {ok, [{<<"outer">>, [{<<"inner">>, 42}]}]} -> ok;
                {ok, Got} -> {error, {expected_nested, got, Got}};
                {error, E} -> {error, E}
            end;
        {error, E} -> {error, E}
    end.

%% {"nums": [1,2,3]} — value decoder must handle inner array
expect_map_array_vals(Bin) ->
    case gleebor:decode_map(Bin, fun gleebor:decode_string/1,
                            fun decode_inner_int_list/1) of
        {ok, Yielder} ->
            case yielder_collect(Yielder) of
                {ok, [{<<"nums">>, [1,2,3]}]} -> ok;
                {ok, Got} -> {error, {expected_map_array, got, Got}};
                {error, E} -> {error, E}
            end;
        {error, E} -> {error, E}
    end.

%% ---------------------------------------------------------------------------
%% Tag expectations
%% ---------------------------------------------------------------------------

expect_tag(Bin, ExpectedTag, PayloadCheck) ->
    case gleebor:decode_tag(Bin) of
        {ok, {ExpectedTag, Rest}} ->
            case PayloadCheck(Rest) of
                ok -> ok;
                {ok, <<>>} -> ok;
                {ok, _Trailing} -> ok;
                {error, E} -> {error, E}
            end;
        {ok, {Tag, _}} -> {error, {expected_tag, ExpectedTag, got, Tag}};
        {error, E} -> {error, E}
    end.
