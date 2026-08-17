-module(boundary).

%% The negative space around family 8.
%%
%% Every scenario here produces a process that is alive and never finishes --
%% the same thing a user reports. If the taxonomy is worth anything, the
%% families have to come apart under observation, so this module runs the
%% look-alikes next to a family 8 reference and prints what separates them.
%%
%% Three of the four do separate. One does not, and that is the useful result:
%%
%%   11  Selective Receive Starvation      separates: the process is running
%%   13  Loop Progress Failure             separates: the process is running
%%   35  Timeout Bounds the Wrong Interval separates: runs in bursts
%%    7  Mutual Blocking                   DOES NOT separate, unless the waits
%%                                         were monitored -- see mutual/0
%%
%% Run table/0.

-export([reference/0, starvation/0, mutual/0, mutual_monitored/0,
         rearmed/0, spinning/0]).
-export([table/0, cleanup/1]).

-define(WINDOW_MS, 1200).
-define(SETTLE_MS, 200).
%% family 35's bound. Kept well under ?WINDOW_MS on purpose -- see dribble/1.
-define(REARM_MS, 300).

%% ---------------------------------------------------------------------------
%% family 8 -- the reference case
%% ---------------------------------------------------------------------------

%% Peer alive, simply never sends. apache/couchdb's middle man.
reference() ->
    Peer = spawn(fun forever/0),
    W = spawn(fun() -> receive {Peer, done} -> ok end end),
    #{label => "8  awaited message (reference)", kind => reference,
      pids => [W, Peer], watch => W}.

%% ---------------------------------------------------------------------------
%% family 11 -- Selective Receive Starvation
%% ---------------------------------------------------------------------------

%% The distinction family 8's own text draws is that "nothing is burying the
%% wanted message -- the mailbox is typically empty". Here something is: one
%% {low, work} message is sent first and then never reached, because the receive
%% only ever matches {high, _} and high keeps arriving. The starved message sits
%% in the mailbox for good.
%%
%% Note what this costs to detect. The process is NOT blocked -- it is working
%% hard, on the wrong thing. Mailbox length alone would not have told them
%% apart, because family 8's cause `c` also leaves a message sitting unmatched.
starvation() ->
    W = spawn(fun starve_loop/0),
    W ! {low, work},                            %% sent first, never served
    Flood = spawn(fun() -> flood(W) end),
    #{label => "11 selective receive starvation", pids => [W, Flood], watch => W}.

%% Only ever matches {high, _}. The {low, work} sitting in front of every high
%% message is scanned past, forever.
starve_loop() ->
    receive {high, _} -> starve_loop() end.

%% Throttled, so the demo starves the low branch without also demonstrating
%% Unbounded Mailbox Growth. At full tilt it would do both.
flood(W) ->
    W ! {high, erlang:monotonic_time()},
    timer:sleep(1),
    flood(W).

%% ---------------------------------------------------------------------------
%% family 13 -- Loop Progress Failure
%% ---------------------------------------------------------------------------

%% erlang/otp diameter_dist, OTP-20242: an AVP whose declared length is zero
%% consumes nothing, so the measure that should decrease -- bytes remaining --
%% never does. The fix was a guard, `Len >= 8`, on the dispatch.
spinning() ->
    W = spawn(fun() -> decode(<<0:32, 0:32, 1, 2, 3, 4>>, 0) end),
    #{label => "13 loop progress failure", pids => [W], watch => W}.

decode(<<>>, Acc) ->
    Acc;
decode(Bin, Acc) ->
    {_Avp, Rest} = take(Bin),
    decode(Rest, Acc + 1).

%% Returns Rest =:= Bin when the length field is zero. That is the whole bug.
take(<<_Code:32, Len:32, _/binary>> = Bin) when Len < 8 -> {zero_length_avp, Bin};
take(<<_Code:32, Len:32, Rest/binary>>) ->
    Take = Len - 8,
    <<_Body:Take/binary, Tail/binary>> = Rest,
    {avp, Tail}.

%% ---------------------------------------------------------------------------
%% family 35 -- Timeout Bounds the Wrong Interval
%% ---------------------------------------------------------------------------

%% benoitc/hackney, GHSA-jq4m. The receive DOES carry a bound, and the bound is
%% useless: every chunk that arrives restarts it, so it measures the gap between
%% chunks rather than the length of the response. A peer that dribbles one chunk
%% just inside each deadline holds the process forever. hackney's own comment
%% said so before the fix -- "Timeout is per-chunk - resets each time data is
%% received" -- and the fix replaced it with an absolute deadline.
%%
%% This is the sharp edge of the family boundary: couchdb fixed family 8 by
%% ADDING an `after`, and hackney's family 35 bug IS an `after`. The construct
%% is identical; which side of the line it falls on depends on whether the timer
%% bounds the interval the code means to bound.
rearmed() ->
    W = spawn(fun() -> Peer = receive {peer, P} -> P end, rearmed_loop(Peer, 0) end),
    Peer = spawn(fun() -> dribble(W) end),
    W ! {peer, Peer},
    #{label => "35 timeout bounds wrong interval", pids => [W, Peer], watch => W}.

rearmed_loop(Peer, N) ->
    receive
        {Peer, done}   -> {ok, N};
        {Peer, _Chunk} -> rearmed_loop(Peer, N + 1)   %% and the clock restarts
    after ?REARM_MS ->
        exit(timeout)
    end.

%% One chunk just inside every deadline, forever. Note what this means for
%% detection: the process only looks different from family 8 while it is awake,
%% so it separates only if the observation window spans a wakeup. Nothing tells
%% an observer what the re-arm interval is, so under a short enough window a
%% family 35 bug reads as family 8. The window here is deliberately several
%% times ?REARM_MS; shorten it and this row flips to "looks exactly like".
dribble(W) ->
    timer:sleep(?REARM_MS - 100),
    W ! {self(), chunk},
    dribble(W).

%% ---------------------------------------------------------------------------
%% family 7 -- Mutual Blocking
%% ---------------------------------------------------------------------------

%% Each side sends only once it has heard from the other, so neither ever sends.
%% kafka4beam/brod's client <-> producers_sup at startup is this with cycle
%% length 2; webmachine's log_close -> log_info -> gen_event:sync_notify ->
%% log_close is the same thing with cycle length 1.
%%
%% Observed one process at a time this is INDISTINGUISHABLE from family 8: both
%% sides are alive, in a receive, with an empty mailbox and no reductions. The
%% difference is not a property of either process, it is a property of the
%% relation between them -- and a bare `receive` records no relation. The
%% runtime cannot tell you what it is waiting for because it was never told.
mutual() ->
    {A, B} = pair(fun bare/0),
    #{label => "7  mutual blocking (bare)", pids => [A, B], watch => A}.

bare() ->
    Peer = receive {peer, P} -> P end,
    receive {Peer, hello} -> Peer ! {self(), hello} end.

%% The same deadlock, with each side monitoring the other first -- which is what
%% gen_server:call does on your behalf. Now the wait-for edge is in
%% process_info(Pid, monitors) and an observer can walk it and find the cycle.
%%
%% So the wait-for graph is recoverable exactly when the waiter arranged to
%% observe its peer, which is the first clause of family 8's invariant. Code
%% that satisfies the invariant is also code you can diagnose from outside.
mutual_monitored() ->
    {A, B} = pair(fun monitored/0),
    #{label => "7  mutual blocking (monitored)", pids => [A, B], watch => A}.

monitored() ->
    Peer = receive {peer, P} -> P end,
    _MRef = erlang:monitor(process, Peer),
    receive {Peer, hello} -> Peer ! {self(), hello} end.

pair(Fun) ->
    A = spawn(Fun),
    B = spawn(Fun),
    A ! {peer, B},
    B ! {peer, A},
    {A, B}.

%% ---------------------------------------------------------------------------

forever() -> receive _ -> forever() end.

%% ---------------------------------------------------------------------------
%% The comparison
%% ---------------------------------------------------------------------------

table() ->
    io:format("~n  every process below is alive and will never finish.~n"
              "  observed for ~wms each.~n~n", [?WINDOW_MS]),
    io:format("  ~-34s ~-9s ~-4s ~-11s ~-10s ~s~n",
              ["scenario", "status", "q", "net-red", "waits-for", "separates from family 8?"]),
    io:format("  ~s~n", [lists:duplicate(108, $-)]),
    Scenarios = [reference(), starvation(), spinning(), rearmed(),
                 mutual(), mutual_monitored()],
    Rows = [row(S) || S <- Scenarios],
    [cleanup(S) || S <- Scenarios],
    io:format("~n  net-red is reductions with the observer's own cost removed;~n"
              "  see the note at the top of observe.erl.~n"
              "~n  two of these separations are weaker than they look:~n"
              "    35 separates only because the window (~wms) outlasts the~n"
              "       re-arm interval (~wms). nothing reveals that interval to~n"
              "       an observer, so a short enough window reads it as family 8.~n"
              "     7 separates only when the waits were monitored. a bare~n"
              "       receive records nothing, so the cycle is not observable~n"
              "       -- it is a property of the relation, not of a process.~n~n",
              [?WINDOW_MS, ?REARM_MS]),
    Rows.

row(#{label := Label, watch := Pid} = S) ->
    timer:sleep(?SETTLE_MS),
    W = observe:watch(Pid, ?WINDOW_MS),
    V = observe:vector(Pid, 0),
    Waits = observe:wait_for(V),
    Verdict = separates(maps:get(kind, S, lookalike), W, Waits),
    io:format("  ~-34s ~-9w ~-4w ~-11w ~-10s ~s~n",
              [Label,
               maps:get(status, W, dead),
               maps:get(max_mailbox, W, 0),
               maps:get(total_reductions, W, 0),
               case Waits of [] -> "-"; _ -> "yes" end,
               Verdict]),
    {Label, W, Waits}.

%% The only two signals available: did it ever run, and did it record what it
%% waits for. Anything that neither runs nor records is, from outside, family 8.
separates(reference, _, _)          -> "(this one IS family 8)";
separates(_, #{ever_ran := true}, _) -> "yes -- it runs";
separates(_, _, Waits) when Waits =/= [] -> "yes -- wait-for edge visible";
separates(_, _, _)                   -> "NO  -- looks exactly like family 8".

cleanup(#{pids := Pids}) ->
    [exit(P, kill) || P <- Pids],
    ok.
