%% A retry layer cannot see the layer above it, or the context it runs in.
%%
%% Shapes of oban-bg/oban@cbd74ab (a transaction retry inside the caller's own transaction)
%% and elixir-horde/horde@74820c2 (a wrapper supervisor with its own restart budget around an
%% inner supervisor that has just used up its budget). Attempts multiply instead of adding.
-module(nested_retry_layers).
-export([retry/2, attempts_buggy/2, attempts_context_known/2, demo/0]).

%% retry(Fun, MaxRetries): call Fun; on `conflict` call it again, up to MaxRetries more times.
retry(Fun, Max) ->
    try Fun()
    catch error:conflict when Max > 0 -> retry(Fun, Max - 1)
    end.

%% The operation. A caller already holds the lock behind the conflict, so it can never
%% succeed until the OUTER layer gives up; the inner layer cannot see that. We count only
%% attempts at the operation itself.
operation(Counter) -> counters:add(Counter, 1, 1), error(conflict).

%% BUGGY: both layers retry blindly: (Outer+1) * (Inner+1) attempts.
attempts_buggy(Outer, Inner) ->
    C = counters:new(1, []),
    catch retry(fun() -> retry(fun() -> operation(C) end, Inner) end, Outer),
    counters:get(C, 1).

%% FIXED (oban's `retry: false`): the caller tells the inner layer that it is nested, which
%% is information only the caller has. The inner layer then makes one attempt per outer attempt.
attempts_context_known(Outer, _Inner) ->
    C = counters:new(1, []),
    catch retry(fun() -> retry(fun() -> operation(C) end, 0) end, Outer),
    counters:get(C, 1).

demo() ->
    #{outer_retries => 3, inner_retries => 5,
      attempts_when_blind => attempts_buggy(3, 5),                 % 4 * 6 = 24
      attempts_when_inner_told => attempts_context_known(3, 5)}.   % 4
