%% Act only on as much as you observed.
%%
%% Shape of vernemq/vernemq#509: a server persists the keys marked dirty by folding over a
%% table, then clears the table. A key marked while the fold was running was not seen by the
%% fold, but the clear removed it too. The fix makes each mark a counter, and after persisting
%% a key subtracts exactly the count the fold saw.
-module(act_only_on_what_you_saw).
-export([buggy_flush/2, fixed_flush/2, demo/0]).

%% BUGGY: "everything in the table was persisted" is believed, not known.
buggy_flush(Tab, Persist) ->
    [Persist(K) || {K} <- ets:tab2list(Tab)],     % the fold: what the server saw
    %% ... another process may call mark/2 here ...
    ets:delete_all_objects(Tab).                  % the act: acts on everything now present

%% FIXED: remember how much was seen, and discard only that much.
fixed_flush(Tab, Persist) ->
    [begin
         Persist(K),
         ets:update_counter(Tab, K, -N)            % N = marks seen by the fold
     end || {K, N} <- ets:tab2list(Tab)],
    ets:match_delete(Tab, {'_', 0}),
    ok.

mark_buggy(Tab, K) -> ets:insert(Tab, {K}).
mark_fixed(Tab, K) -> ets:update_counter(Tab, K, 1, {K, 0}).

demo() ->
    %% A mark for key `late` arrives while the server is persisting `early`.
    Buggy = ets:new(buggy, [public, set]),
    mark_buggy(Buggy, early),
    buggy_flush(Buggy, fun(early) -> mark_buggy(Buggy, late) end),
    Fixed = ets:new(fixed, [public, set]),
    mark_fixed(Fixed, early),
    fixed_flush(Fixed, fun(early) -> mark_fixed(Fixed, early) end),   % a second mark of the same key
    #{buggy_dirty_keys_left => ets:tab2list(Buggy),     % [] : `late` was never persisted
      fixed_dirty_keys_left => ets:tab2list(Fixed)}.    % [{early,1}]: persisted again next round
