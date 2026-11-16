%% Two parties apply different thresholds to the same signal.
%%
%% Shape of emqx/emqx@5d0ec03: the caller of a channel health check waited a fixed 5 s, while
%% the probe itself was allowed longer. A slow but healthy probe read as a failure. This is
%% the earlier survey's definition of a grey failure ("the detector and the client observe the
%% component through different paths, or apply a different threshold to the same signal").
-module(timeout_vs_probe).
-export([check/3, demo/0]).

%% A probe that answers `healthy`, after Latency ms.
probe(Latency) ->
    spawn(fun() -> receive {probe, From, Ref} -> timer:sleep(Latency), From ! {Ref, healthy} end end).

%% The caller's verdict: healthy if the answer arrives within Wait, otherwise down.
check(Probe, Wait, _Budget) ->
    Ref = make_ref(),
    Probe ! {probe, self(), Ref},
    receive {Ref, healthy} -> healthy after Wait -> down end.

stale_replies() -> receive {_, healthy} -> 1 + stale_replies() after 0 -> 0 end.

demo() ->
    Latency = 200, Budget = 500,      % the probe is slow, and allowed 500 ms
    V1 = check(probe(Latency), 50, Budget),          % BUGGY: the caller's bound is 50 ms
    timer:sleep(300),
    Late = stale_replies(),                          % the healthy answer arrives after the verdict
    V2 = check(probe(Latency), Budget, Budget),      % FIXED: the caller uses the probe's own budget
    #{buggy_verdict => V1, late_healthy_answers_nobody_reads => Late, fixed_verdict => V2}.
