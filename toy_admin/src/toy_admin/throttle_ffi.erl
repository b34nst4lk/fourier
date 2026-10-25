%% The throttle's ETS layer (rationale in throttle.gleam: ETS, not an actor).
%%
%% These are the operations Gleam cannot express cleanly:
%%
%%   setup/0  creates the named, public table exactly once — and tolerates the
%%            badarg a concurrent creator would raise (the loser of the race is
%%            not an error: the winner made the same table);
%%   hit/1    one atomic insert-or-increment via ets:update_counter/4 with a
%%            default object, so two concurrent requests for the same key can
%%            never lose a count and no lock is needed;
%%   sweep/1  drops every row from a window older than the current one with a
%%            match spec (ets:select_delete/2), so the sweep does not copy the
%%            table out to Gleam and back.
%%
%% Rows are {{Key, WindowBucket}, Count}; the window the key was counted in is
%% part of the key, which is what makes "the counters reset per window" fall out
%% of the key rather than out of any timer.
-module(throttle_ffi).

-export([setup/0, hit/1, sweep/1, size/0, clear/0]).

-define(TABLE, toy_admin_throttle).

setup() ->
    case ets:whereis(?TABLE) of
        undefined ->
            try ets:new(?TABLE, [
                set, public, named_table, {write_concurrency, true}
            ]) of
                _ -> ok
            catch
                error:badarg -> ok
            end;
        _ ->
            ok
    end.

%% The table name is fixed here rather than passed in: ETS wants an atom and a
%% Gleam String is a binary, so handing the name across the boundary would mean
%% converting it back on every call (and inviting a badarg on the day someone
%% passes a tid).
hit(Key) ->
    ets:update_counter(?TABLE, Key, 1, {Key, 0}).

sweep(Window) ->
    %% Objects are {{Key, WindowBucket}, Count}: match the bucket inside the key
    %% and drop every row from a window before this one.
    ets:select_delete(?TABLE, [{{{'$1', '$2'}, '_'}, [{'<', '$2', Window}], [true]}]),
    ok.

size() ->
    ets:info(?TABLE, size).

clear() ->
    try ets:delete_all_objects(?TABLE) of
        _ -> ok
    catch
        error:badarg -> ok
    end.
