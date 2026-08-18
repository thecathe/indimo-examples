-module(boundary).

%% The negative space around family 35.
%%
%% Family 8's boundary module found that three of its four look-alikes came
%% apart under observation and one did not. This one goes the other way, and the
%% result is worth stating up front: NONE of family 35's neighbours separate
%% from it. Six scenarios, three observable classes, no family recovered.
%%
%% The reason is structural rather than a gap in the oracle. Family 35 is a
%% mismatch between two intervals -- the one a timer measures, M, and the one
%% the code means to bound, I. An observer can recover M perfectly well: watch
%% when the process runs and read the gaps (observe:pulses/3). I is nowhere. It
%% is not in the runtime and it is not in the code either -- in all three
%% confirmed members it survives only as a comment, a test name or an exit
%% reason. A mismatch with an unobservable operand is an unobservable mismatch.
%%
%% So every row below is a pair: a family 35 scenario and something from another
%% family that produces the identical reading.
%%
%%    8  awaited message never arrives   vs  35 with its timer discarded
%%       healthy, merely slow            vs  35 with its timer re-armed
%%   31  transient failure as permanent  vs  35 having given up early
%%
%% Run table/0. Then sweep/0, which is the one thing family 8's version
%% asserted and this one measures.

-export([table/0, sweep/0]).
-export([family8/0, slow/0, transient/0]).

-define(WINDOW_MS, 1200).
-define(SETTLE_MS, 200).

%% ---------------------------------------------------------------------------
%% The neighbours
%% ---------------------------------------------------------------------------

%% Family 8. apache/couchdb's middle man: a peer that is alive and simply never
%% sends, awaited by a receive with no monitor and no bound.
family8() ->
    Peer = spawn(fun forever/0),
    W = spawn(fun() -> receive {Peer, done} -> ok end end),
    #{pids => [W, Peer], watch => W}.

%% Not a failure at all. A process doing real work in steps, which will finish,
%% but not inside the window someone chose to watch it for.
%%
%% This is the row that makes the point cheapest. Against `rearmed` it is a
%% correct program and a security advisory, and they read the same.
%%
%% Its step is 250ms against the re-armed scenario's 200ms, deliberately: the
%% two are not being passed off as identical readings. They are different
%% readings, and neither of them says anything about whether the interval it
%% shows is the right one. That is the weaker and more uncomfortable claim.
slow() ->
    W = spawn(fun() -> step(30) end),
    #{pids => [W], watch => W}.

step(0) -> done;
step(N) ->
    timer:sleep(250),
    _ = lists:seq(1, 2000),
    step(N - 1).

%% Family 31, Transient Failure Treated as Permanent. A bound that is measured
%% exactly right and is simply too small for a peer that was about to answer;
%% the caller treats the timeout as final.
%%
%% Note what this is NOT. M = I here -- the timer measures precisely the wait it
%% was meant to measure. There is no family 35 defect anywhere in it. It is the
%% control for `suspended_abs`, which has M /= I and produces the same reading.
transient() ->
    Runner = self(),
    W = spawn(fun() ->
                  Peer = receive {peer, P} -> P end,
                  Runner ! {self(), receive {Peer, done} -> got_reply
                                    after 200 -> exit({error, timeout})
                                    end}
              end),
    Peer = spawn(fun() ->
                     Waiter = receive {waiter, X} -> X end,
                     timer:sleep(400),           %% would have answered
                     Waiter ! {self(), done},
                     forever()
                 end),
    Peer ! {waiter, W},
    W ! {peer, Peer},
    #{pids => [W, Peer], watch => W}.

forever() -> receive _ -> forever() end.

%% ---------------------------------------------------------------------------
%% The comparison
%% ---------------------------------------------------------------------------

table() ->
    io:format("~n  family 35 next to its neighbours, ~wms each.~n~n", [?WINDOW_MS]),
    io:format("  ~-42s ~-9s ~-10s ~-10s ~s~n",
              ["scenario", "family", "class", "wakeups", "gaps between them"]),
    io:format("  ~s~n", [lists:duplicate(108, $-)]),
    Rows = [row(L, F, S) || {L, F, S} <- specs()],
    io:format("~n"),
    report(Rows),
    Rows.

specs() ->
    [{"timer discarded (114)",             "35", fun() -> tbwi:scenario(discarded) end},
     {"awaited message never arrives",     "8",  fun family8/0},
     {"timer re-armed per chunk (26)",     "35", fun() -> tbwi:scenario(rearmed) end},
     {"healthy, just slower than the window", "-", fun slow/0},
     {"gave up early, M /= I (44)",        "35", fun() -> tbwi:scenario(suspended_abs) end},
     {"gave up early, M = I, bound too small", "31", fun transient/0}].

row(Label, Family, Make) ->
    S = Make(),
    Pid = maps:get(watch, S),
    timer:sleep(?SETTLE_MS),
    Pulses = observe:pulses(Pid, ?WINDOW_MS),
    V = observe:vector(Pid, 0),
    tbwi:cleanup(S),
    Class = classify(V, Pulses),
    io:format("  ~-42s ~-9s ~-10s ~-10w ~w~n",
              [Label, Family, Class, length(Pulses), observe:gaps(Pulses)]),
    {Label, Family, Class}.

%% Everything an observer gets. Not a rich vocabulary, and that is the finding:
%% six scenarios from four families land in three buckets.
classify(#{alive := false}, _)      -> exited;
classify(_, [])                     -> silent;
classify(_, _)                      -> bursts.

report(Rows) ->
    Classes = lists:usort([C || {_, _, C} <- Rows]),
    io:format("  what an observer can tell apart:~n~n"),
    [begin
         Members = [{L, F} || {L, F, C} <- Rows, C =:= Class],
         io:format("    ~-8w ~s~n", [Class, hd([fmt_member(M) || M <- Members])]),
         [io:format("    ~-8s ~s~n", ["", fmt_member(M)]) || M <- tl(Members)],
         io:format("~n")
     end || Class <- Classes],
    Families = lists:usort([F || {_, F, _} <- Rows]),
    io:format("  ~w families, ~w scenarios, ~w observable classes. every class~n"
              "  holds a family 35 scenario and something that is not one, and~n"
              "  in the `bursts` row one of the two is not a bug at all.~n~n",
              [length(Families), length(Rows), length(Classes)]),
    io:format("  the missing operand is I. M is right there in the gaps column,~n"
              "  recovered from outside with no cooperation from the process --~n"
              "  and the two `bursts` rows show different intervals, neither of~n"
              "  which says whether it is the interval that was wanted.~n~n").

fmt_member({Label, "-"})    -> io_lib:format("~s  (not a failure)", [Label]);
fmt_member({Label, Family}) -> io_lib:format("~s  (family ~s)", [Label, Family]).

%% ---------------------------------------------------------------------------
%% The window sweep
%% ---------------------------------------------------------------------------

%% Family 8's boundary table separated family 35 on the grounds that "it runs",
%% and its finding 4 conceded that this only works because the observation
%% window outlasts the re-arm interval -- then left it there. Here it is
%% measured rather than conceded.
%%
%% The re-arm interval is 200ms. Watch what happens either side of it.
%%
%% What an observer needs is not one wakeup but TWO -- a single wakeup is not an
%% interval, and a process that woke once inside the window is exactly as
%% inscrutable as one that never woke at all. So the window has to SPAN a full
%% interval, and whether a given window does depends on where in the cycle the
%% observer happened to start looking, which it also does not control.
%%
%% That second part is easy to lose, and losing it moves the answer. The first
%% version of this sweep settled for exactly one dribble interval before opening
%% the window, which phase-locked every run to the same point in the cycle. It
%% produced a beautifully sharp threshold at 200ms -- 0 of 3 below, 3 of 3 at
%% and above, five times running -- and the sharpness was entirely an artifact
%% of the harness. Unlock the phase and the threshold moves out to 400ms: TWICE
%% the interval, because a window of 200ms only ever spans two chunks if it
%% happens to start between them, and a real observer does not get to choose.
%%
%% So a window equal to the whole re-arm interval reads as family 8 every single
%% time. The rule is 2x, and it is 2x an interval nobody can see.
-define(SWEEP_RUNS, 5).

sweep() ->
    io:format("~n  the same re-armed process, watched for different lengths of~n"
              "  time. its chunks arrive every 200ms. nothing tells the observer~n"
              "  that, and nothing tells it what the 200ms was meant to bound.~n~n"),
    io:format("  ~-12s ~-16s ~-14s ~s~n",
              ["window", "saw an interval", "typical gap", "reads as"]),
    io:format("  ~s~n", [lists:duplicate(76, $-)]),
    Rows = [sweep_row(WindowMs) || WindowMs <- [50, 100, 150, 200, 300, 400, 800]],
    io:format("~n  the threshold is not the re-arm interval, it is twice it: a~n"
              "  200ms window on a 200ms cycle reads as family 8 every time,~n"
              "  because spanning two chunks needs luck with the phase and the~n"
              "  observer does not pick the phase either.~n~n"
              "  under a short enough window a family 35 bug IS a family 8 bug.~n"
              "  no care in the oracle fixes that: the window has to be chosen~n"
              "  against an interval that is not visible, and choosing it wrong~n"
              "  does not announce itself.~n~n"),
    Rows.

sweep_row(WindowMs) ->
    Gs = [sweep_once(WindowMs) || _ <- lists:seq(1, ?SWEEP_RUNS)],
    Seen = [G || G <- Gs, G =/= []],
    Typical = case lists:sort(lists:append(Seen)) of
                  []  -> "-";
                  All -> integer_to_list(lists:nth(1 + length(All) div 2, All)) ++ "ms"
              end,
    io:format("  ~-12s ~-16s ~-14s ~s~n",
              [integer_to_list(WindowMs) ++ "ms",
               io_lib:format("~w of ~w", [length(Seen), ?SWEEP_RUNS]),
               Typical,
               reads_as(length(Seen))]),
    {WindowMs, length(Seen)}.

reads_as(0)               -> "family 8 -- one wakeup at most, no interval";
reads_as(?SWEEP_RUNS)     -> "35 -- an interval is visible";
reads_as(_)               -> "either, depending on the run".

sweep_once(WindowMs) ->
    S = tbwi:scenario(rearmed),
    Pid = maps:get(watch, S),
    %% Settle, then a random fraction of a cycle on top, so the window does not
    %% always open at the same point between two chunks. See the note above.
    timer:sleep(?SETTLE_MS + rand:uniform(200)),
    Pulses = observe:pulses(Pid, WindowMs, poll_for(WindowMs)),
    tbwi:cleanup(S),
    observe:gaps(Pulses).

%% Poll fast enough that a short window still takes several readings; otherwise
%% the sweep would be measuring its own sampling rate.
poll_for(WindowMs) -> max(10, WindowMs div 8).
