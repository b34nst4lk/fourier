%% The environment as Gleam Strings (see env.gleam: Erlang's os:getenv/putenv
%% speak charlists, Gleam Strings are binaries, and mixing them raises badarg).
-module(env_ffi).

-export([get/1, set/2]).

get(Key) ->
    case os:getenv(binary_to_list(Key)) of
        false -> none;
        Value -> {some, list_to_binary(Value)}
    end.

set(Key, Value) ->
    true = os:putenv(binary_to_list(Key), binary_to_list(Value)),
    nil.
