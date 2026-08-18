-module(tbwi).

%% Family 35 -- Timeout Bounds the Wrong Interval.
%%
%%   invariant: correspondence between a timer and the interval it bounds
%%
%% Every timeout has two intervals. There is the one the code MEANS to bound --
%% "the whole response", "two seconds of waiting for a reply" -- and there is
%% the one the timer ACTUALLY measures. Call them I and M. This family is M /= I.
%%
%% Family 8 was one symptom reachable from many causes, so its matrix held the
%% symptom fixed and varied the cause. That shape does not transfer, because
%% here the discrepancy is SIGNED and the two signs give opposite symptoms:
%%
%%   M subset I    the timer is restarted by an event inside I, so it only ever
%%                 measures a piece of it. Never fires. Runs forever despite
%%                 having a timeout.                      -- hackney, id 26
%%
%%   M superset I  the timer is charged for time outside I -- time the process
%%                 could not have received in anyway. Fires early. Gives up
%%                 without having waited.                 -- otp/erts, id 44
%%
%%   M empty       the timer is discarded outright by an unrelated event.
%%                 No bound at all.                       -- otp gen_server, 114
%%
%% So the axis is direction x remedy, and the interesting result is that the two
%% remedies form an ANTI-DIAGONAL: each one repairs its own direction and CAUSES
%% the other. Run cross/0. Neither remedy dominates, which is a sharper result
%% than family 8's, where bounding dominated monitoring outright.
%%
%%   ledger()          the five scenarios, each declaring its I and its M
%%   cross()           direction x remedy, measured
%%   run(Scenario)     one scenario, with the timings
%%   scenarios()       the names

-export([run/1, ledger/0, cross/0, cleanup/1]).
-export([scenarios/0, scenario/1, describe/1, intended/1, measured/1]).

%% hackney's bound, scaled down. The real one was 30s; what matters is the
%% relationship to ?DRIBBLE_MS, not the magnitude.
-define(BOUND_MS, 300).

%% One chunk just inside every deadline. Under ?BOUND_MS, so the timer is always
%% re-armed before it can fire.
-define(DRIBBLE_MS, 200).

%% How long to let a re-armed scenario run before conceding it never fires.
%% Several times ?BOUND_MS -- see finding 4 on why this number is not innocent.
-define(WINDOW_MS, 1200).

%% id 44's suspension. Comfortably longer than ?BOUND_MS so a wall-clock timer
%% expires entirely while the process is not running.
-define(SUSPEND_MS, 900).

scenarios() -> [rearmed, deadline, discarded, suspended, suspended_abs].

describe(rearmed) ->
    "26  per-chunk timer, peer dribbles      (hackney, the bug)";
describe(deadline) ->
    "26  absolute deadline                   (hackney's fix)";
describe(discarded) ->
    "114 bound dropped on an unrelated event (gen_server, the bug)";
describe(suspended) ->
    "44  wall-clock timer, process suspended (erts, the symptom)";
describe(suspended_abs) ->
    "44  the same, with hackney's remedy     (the anti-diagonal)".

%% I -- what the code means to bound. Nowhere in the code; recorded here because
%% it has to be recorded somewhere, which is finding 4.
intended(rearmed)       -> "the whole response";
intended(deadline)      -> "the whole response";
intended(discarded)     -> integer_to_list(?BOUND_MS) ++ "ms of waiting";
intended(suspended)     -> integer_to_list(?BOUND_MS) ++ "ms of waiting";
intended(suspended_abs) -> integer_to_list(?BOUND_MS) ++ "ms of waiting".

%% M -- what the timer measures.
measured(rearmed)       -> "the gap between chunks";
measured(deadline)      -> "the whole response";
measured(discarded)     -> "nothing -- discarded";
measured(suspended)     -> "wall-clock, suspension included";
measured(suspended_abs) -> "wall-clock, unpausable".

%% ---------------------------------------------------------------------------
%% M subset I -- the timer is restarted from inside the interval it bounds
%% ---------------------------------------------------------------------------

%% benoitc/hackney, GHSA-jq4m. await_response_loop carried a bound and the bound
%% was useless: every chunk restarted it, so it measured the gap between chunks
%% rather than the length of the response. A peer that dribbles one chunk just
%% inside each deadline holds the process forever.
%%
%% hackney's own comment said so, in as many words, before the fix:
%%
%%   %% Timeout is per-chunk - resets each time data is received.
%%   %% This allows large responses to complete as long as data keeps flowing.
%%
%% Read that second line again. It is not a mistake -- it is the intended
%% interval, written down, and it is genuinely wanted behaviour for a large
%% download. The bug is that a peer gets to choose whether "data keeps flowing"
%% means a megabyte or one byte. What the fix had to give up is the property the
%% comment describes; the size cap that came with it is the compensation.
rearmed() ->
    Peer = spawn_dribbler(),
    W = spawn(fun() -> rearmed_loop(receive {peer, P} -> P end, 0) end),
    Peer ! {waiter, W},
    W ! {peer, Peer},
    #{pids => [W, Peer], watch => W}.

rearmed_loop(Peer, N) ->
    receive
        {Peer, done}   -> {ok, N};
        {Peer, _Chunk} -> rearmed_loop(Peer, N + 1)     %% and the clock restarts
    after ?BOUND_MS ->
        exit(timeout)
    end.

%% The fix: one deadline, computed once, with the remaining time derived at each
%% receive. This is hackney's remaining/1 verbatim in spirit, and it is what
%% OTP's {timeout, T, Msg, [{abs, true}]} gives you for free.
deadline() ->
    Peer = spawn_dribbler(),
    W = spawn(fun() ->
                  P = receive {peer, Q} -> Q end,
                  deadline_loop(P, erlang:monotonic_time(millisecond) + ?BOUND_MS, 0)
              end),
    Peer ! {waiter, W},
    W ! {peer, Peer},
    #{pids => [W, Peer], watch => W}.

deadline_loop(Peer, Deadline, N) ->
    receive
        {Peer, done}   -> {ok, N};
        {Peer, _Chunk} -> deadline_loop(Peer, Deadline, N + 1)
    after remaining(Deadline) ->
        exit(timeout)
    end.

remaining(Deadline) -> max(0, Deadline - erlang:monotonic_time(millisecond)).

%% One chunk just inside every deadline, forever.
spawn_dribbler() ->
    spawn(fun() -> dribble(receive {waiter, W} -> W end) end).

dribble(W) ->
    timer:sleep(?DRIBBLE_MS),
    W ! {self(), chunk},
    dribble(W).

%% ---------------------------------------------------------------------------
%% M empty -- the timer is discarded
%% ---------------------------------------------------------------------------

%% erlang/otp#9615. gen_server's plain timeout lived in the `after` of the main
%% receive. A system message came out of that receive like any other, went off
%% to sys:handle_system_msg, and the loop it came back to had no idea a timeout
%% had been pending -- so the process resumed with `infinity`. A sys:get_status
%% from an observer, an appmon connecting, anything at all, and the bound was
%% simply gone.
%%
%% Distilled: a bounded wait, re-entered after handling something the code
%% considers none of its business, with the bound not carried across. Nothing
%% here is gen_server-specific; this is what the shape looks like anywhere.
%%
%% The real one is worth running rather than distilling, because the fix is live
%% in the runtime you are on and did something interesting -- see otp_timeout.erl.
discarded() ->
    Peer = spawn_poker(),
    W = spawn(fun() -> discarded_loop(receive {peer, P} -> P end) end),
    Peer ! {waiter, W},
    W ! {peer, Peer},
    #{pids => [W, Peer], watch => W}.

discarded_loop(Peer) ->
    receive
        {Peer, done} -> ok;
        {poke, _}    -> unbounded_loop(Peer)            %% and the bound is gone
    after ?BOUND_MS ->
        exit(timeout)
    end.

unbounded_loop(Peer) ->
    receive
        {Peer, done} -> ok;
        {poke, _}    -> unbounded_loop(Peer)
    end.

%% The unrelated event. Arrives once, early, and never again -- the point is not
%% that it keeps coming, it is that one of them is enough.
spawn_poker() ->
    spawn(fun() ->
              W = receive {waiter, X} -> X end,
              timer:sleep(?BOUND_MS div 3),
              W ! {poke, self()},
              forever()
          end).

%% ---------------------------------------------------------------------------
%% M superset I -- the timer is charged for time outside the interval
%% ---------------------------------------------------------------------------

%% erlang/otp#8670. erlang:suspend_process/2 did not pause the suspended
%% process's timer, so a `receive ... after T` kept counting while its process
%% was not running -- and could expire entirely during the suspension. On resume
%% the process gave up immediately, having waited for none of its own T. OTP's
%% own test names the symptom: exit(timer_not_paused).
%%
%% The fix is in C (ErtsPausedProcTimer, erts_pause_proc_timer), so what is
%% distilled here is the symptom, which needs no C at all. Note what this means
%% for the row: on a runtime carrying the fix, this scenario PASSES. That is the
%% honest result and the table says so rather than pretending otherwise.
suspended() ->
    suspension(fun() ->
                   receive {_, done} -> got_reply
                   after ?BOUND_MS -> gave_up
                   end
               end).

%% The same wait, with hackney's remedy applied to it.
%%
%% This is the cell the whole family turns on. The absolute deadline is correct
%% for id 26 and it is exactly wrong here: erts_pause_proc_timer can pause a
%% timer THE RUNTIME OWNS, and an absolute deadline computed in Erlang is not a
%% timer, it is arithmetic on a wall clock. The runtime cannot pause arithmetic.
%%
%% So the process comes back from a suspension it had no say in, re-enters the
%% receive, computes remaining(Deadline) = 0 and gives up on a peer that was
%% responsive the whole time. The fix for one direction of this family is the
%% cause of the other, and no runtime fix can cover it.
suspended_abs() ->
    suspension(fun() ->
                   D = erlang:monotonic_time(millisecond) + ?BOUND_MS,
                   abs_wait(D)
               end).

abs_wait(D) ->
    receive
        {_, done}  -> got_reply;
        {_, chunk} -> abs_wait(D)
    after remaining(D) ->
        gave_up
    end.

%% Suspend the waiter for longer than its own bound, resume it, and only then
%% let the peer speak. A correct bound is untouched by this: the peer replies
%% well inside ?BOUND_MS of the waiter actually being able to hear it.
suspension(Wait) ->
    Runner = self(),
    W = spawn(fun() -> Runner ! {self(), ready}, Runner ! {self(), Wait()} end),
    receive {W, ready} -> ok end,
    ok = await_waiting(W),
    Peer = spawn(fun() ->
                     true = erlang:suspend_process(W),
                     timer:sleep(?SUSPEND_MS),
                     true = erlang:resume_process(W),
                     %% A chunk first, so a deadline-based loop re-enters its
                     %% receive and recomputes. Without a re-entry the stale
                     %% deadline is never consulted and the bug stays hidden.
                     W ! {self(), chunk},
                     timer:sleep(?BOUND_MS div 3),
                     W ! {self(), done},
                     forever()
                 end),
    #{pids => [W, Peer], watch => W, collect => W}.

%% suspend_process/2 on a process that has not reached its receive yet would
%% freeze it mid-setup and measure the wrong thing.
await_waiting(Pid) ->
    case process_info(Pid, status) of
        {status, waiting} -> ok;
        undefined         -> ok;
        _                 -> timer:sleep(10), await_waiting(Pid)
    end.

forever() -> receive _ -> forever() end.

%% ---------------------------------------------------------------------------
%% Running one scenario
%% ---------------------------------------------------------------------------

%% Returns a map. Scenarios that report a result do so through `collect`; the
%% rest are judged by whether they were still running at the end of the window.
run(Name) ->
    T0 = erlang:monotonic_time(millisecond),
    S = scenario(Name),
    Watch = maps:get(watch, S),
    {Outcome, Elapsed} = settle(S, T0),
    Pulses = case Outcome of
                 still_running -> observe:pulses(Watch, ?WINDOW_MS);
                 _             -> []
             end,
    S#{name    => Name,
       outcome => Outcome,
       elapsed => Elapsed,
       pulses  => Pulses,
       gaps    => observe:gaps(Pulses)}.

%% Spawns and returns immediately, leaving everything running. run/1 settles it;
%% boundary.erl wants to observe it instead, and the shell wants to poke at it.
scenario(rearmed)       -> rearmed();
scenario(deadline)      -> deadline();
scenario(discarded)     -> discarded();
scenario(suspended)     -> suspended();
scenario(suspended_abs) -> suspended_abs().

%% Wait for the scenario to declare itself, up to the window. Three endings:
%% it returned a value, it exited, or it is still going.
settle(S, T0) ->
    W = maps:get(watch, S),
    MRef = erlang:monitor(process, W),
    Deadline = T0 + ?WINDOW_MS,
    R = collect(W, MRef, Deadline),
    erlang:demonitor(MRef, [flush]),
    {R, erlang:monotonic_time(millisecond) - T0}.

collect(W, MRef, Deadline) ->
    Left = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {W, Result} ->
            {returned, Result};
        {'DOWN', MRef, process, W, Reason} ->
            {exited, Reason}
    after Left ->
        still_running
    end.

cleanup(#{pids := Pids}) ->
    [exit(P, kill) || P <- Pids],
    ok.

%% ---------------------------------------------------------------------------
%% The ledger
%% ---------------------------------------------------------------------------

%% One row per scenario, with both intervals written out. The two interval
%% columns are the point: they are the only place either one is recorded, and
%% only one of them was ever recoverable from the running system.
ledger() ->
    io:format("~n  family 35 -- Timeout Bounds the Wrong Interval~n"),
    io:format("  invariant: correspondence between a timer and the interval~n"
              "             it bounds~n~n"),
    io:format("  every scenario below has a timeout of ~wms and a peer that~n"
              "  is responsive. observed for ~wms.~n~n", [?BOUND_MS, ?WINDOW_MS]),
    io:format("  ~-16s ~-22s ~-32s ~-8s ~s~n",
              ["scenario", "I -- means to bound", "M -- actually measures",
               "M vs I", "outcome"]),
    io:format("  ~s~n", [lists:duplicate(112, $-)]),
    Rows = [ledger_row(N) || N <- scenarios()],
    io:format("~n  I is not in the code, in any of them. it is in a comment~n"
              "  (26), a test name (114) or an exit reason (44). M is the only~n"
              "  one an observer can recover -- see the gaps below.~n~n"),
    [io:format("  ~-16s pulses at ~w~n"
               "  ~-16s gaps      ~w~n", [N, P, "", G])
     || #{name := N, pulses := P, gaps := G} <- Rows, P =/= []],
    io:format("~n"),
    Rows.

ledger_row(Name) ->
    S = run(Name),
    cleanup(S),
    io:format("  ~-16w ~-22s ~-32s ~-8s ~s~n",
              [Name, intended(Name), measured(Name), relation(Name),
               fmt_outcome(S)]),
    S.

relation(rearmed)       -> "M in I";
relation(deadline)      -> "M = I";
relation(discarded)     -> "M = 0";
relation(suspended)     -> "I in M";
relation(suspended_abs) -> "I in M".

fmt_outcome(#{outcome := still_running, elapsed := E}) ->
    io_lib:format("still running after ~wms -- never fired", [E]);
fmt_outcome(#{outcome := {exited, timeout}, elapsed := E}) ->
    io_lib:format("fired at ~wms", [E]);
fmt_outcome(#{outcome := {returned, gave_up}, elapsed := E}) ->
    io_lib:format("GAVE UP at ~wms, peer was responsive", [E]);
fmt_outcome(#{outcome := {returned, got_reply}, elapsed := E}) ->
    io_lib:format("got the reply at ~wms", [E]);
fmt_outcome(#{outcome := {returned, R}, elapsed := E}) ->
    io_lib:format("returned ~w at ~wms", [R, E]);
fmt_outcome(#{outcome := {exited, R}, elapsed := E}) ->
    io_lib:format("exited ~w at ~wms", [R, E]).

%% ---------------------------------------------------------------------------
%% The cross
%% ---------------------------------------------------------------------------

%% Direction x remedy. Two directions, two remedies, and the off-diagonal cells
%% are the result: applying a remedy to the wrong direction is not a no-op, it
%% is the other bug.
cross() ->
    io:format("~n  direction x remedy~n~n"),
    io:format("    abs     one deadline at entry, remaining time derived at~n"
              "            each receive. hackney's fix; otp's {abs, true}.~n"),
    io:format("    paused  the timer does not run while the process could not~n"
              "            have received. otp's erts_pause_proc_timer.~n~n"),
    io:format("  ~-30s ~-26s ~-26s ~s~n",
              ["direction", "no remedy", "abs", "paused"]),
    io:format("  ~s~n", [lists:duplicate(112, $-)]),

    Rearmed  = cell(rearmed),
    Deadline = cell(deadline),
    Susp     = cell(suspended),
    SuspAbs  = cell(suspended_abs),

    io:format("  ~-30s ~-26s ~-26s ~s~n",
              ["M in I  (26, hackney)", Rearmed, Deadline,
               "no effect -- the re-arm"]),
    io:format("  ~-30s ~-26s ~-26s ~s~n",
              ["", "", "", "is the problem"]),
    io:format("  ~-30s ~-26s ~-26s ~s~n",
              ["I in M  (44, suspension)", Susp, SuspAbs,
               "erts-only, and in place"]),
    io:format("~n"),

    io:format("  read the two `abs` cells together. the remedy that repairs~n"
              "  hackney is the one that breaks the suspended wait, against a~n"
              "  peer that answered on time. neither remedy dominates.~n~n"),
    io:format("  the empty cell is not missing work. erts_pause_proc_timer can~n"
              "  pause a timer the RUNTIME owns; an absolute deadline computed~n"
              "  in erlang is arithmetic on a wall clock, and no runtime fix~n"
              "  reaches it. every codebase that took hackney's remedy has~n"
              "  re-opened 44 for itself, on a runtime where 44 is fixed.~n~n"),
    ok.

cell(Name) ->
    S = run(Name),
    cleanup(S),
    lists:flatten(cell_text(S)).

cell_text(#{outcome := still_running})            -> "runs forever";
cell_text(#{outcome := {exited, timeout}, elapsed := E}) ->
    io_lib:format("bounded, fired ~wms", [E]);
cell_text(#{outcome := {returned, got_reply}})    -> "survived, got the reply";
cell_text(#{outcome := {returned, gave_up}})      -> "GAVE UP, peer was fine";
cell_text(#{outcome := O})                        -> io_lib:format("~w", [O]).
