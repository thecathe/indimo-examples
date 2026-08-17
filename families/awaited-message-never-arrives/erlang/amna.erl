-module(amna).

%% Family 8 -- Awaited Message Never Arrives.
%%
%%   invariant: every wait on a peer either observes that peer's death
%%              or bounds itself
%%
%% The shape below is what is left of two confirmed fixes once the project
%% detail is stripped out. Both were a selective receive on messages from
%% exactly ONE peer, with no monitor and no `after`:
%%
%%   erlang/otp   lib/ssl/src/inet_tls_dist.erl   do_accept/7      (GH-5332)
%%       receive {AcceptPid, controller} -> ...; {AcceptPid, exit} -> ... end
%%
%%   apache/couchdb  src/fabric_doc_attachments.erl  write_chunks/2
%%       receive {MiddleMan, ChunkRecord} -> ..., write_chunks(...) end
%%
%% They were fixed differently, and that difference is the point of this module.
%% OTP added `erlang:monitor` and a {'DOWN',...} clause; couchdb added
%% `after 600000 -> exit(timeout)`. The invariant offers those two escape
%% hatches joined by OR, which invites the reading that they are alternatives.
%%
%% They are not. Run matrix/0.
%%
%%   run(Cause, Remedy)  Cause  :: a | b | c
%%                       Remedy :: none | r1 | r2
%%   matrix()            all nine cells as a table
%%   verdict(Pid)        stuck | progressing | gone

-export([run/1, run/2, matrix/0, verdict/1, verdict/2, cleanup/1]).
-export([causes/0, remedies/0, describe/1]).

%% r2's bound. couchdb used ten minutes; 500ms keeps the demo interactive.
%% The interval is arbitrary -- what matters is that one exists.
-define(BOUND_MS, 500).

%% How long a process must make zero progress before we call it stuck. Must
%% comfortably exceed ?BOUND_MS so a fired remedy is never mistaken for a stall.
-define(WINDOW_MS, 1200).

%% Spawning the waiter, handing it the peer and entering the receive all cost
%% reductions. Measuring from t=0 would count that startup as progress and call
%% every scenario `progressing`, so the window opens only once things settle.
-define(SETTLE_MS, 200).

causes()   -> [a, b, c].
remedies() -> [none, r1, r2].

describe(a)    -> "peer exits before sending          (erlang/otp, GH-5332)";
describe(b)    -> "peer stays alive, never sends      (apache/couchdb)";
describe(c)    -> "peer sends an unmatched shape";
describe(none) -> "no monitor, no bound               (the bug)";
describe(r1)   -> "erlang:monitor + {'DOWN',...}      (otp's fix)";
describe(r2)   -> "after " ++ integer_to_list(?BOUND_MS) ++ " -> exit(timeout)"
                  "         (couchdb's fix)".

%% ---------------------------------------------------------------------------
%% The waiter -- the distilled shape
%% ---------------------------------------------------------------------------

%% Every clause below waits on messages from exactly one peer. They differ only
%% in what else they are prepared to hear.

%% The bug. Nothing but Peer's messages will ever wake this process.
wait(Peer, none) ->
    receive
        {Peer, done}   -> ok;
        {Peer, _Chunk} -> wait(Peer, none)
    end;

%% Remedy 1, after otp: arrange to be told that the peer is gone.
wait(Peer, r1) ->
    MRef = erlang:monitor(process, Peer),
    wait_r1(Peer, MRef);

%% Remedy 2, after couchdb: bound the wait, whatever the peer is doing.
wait(Peer, r2) ->
    receive
        {Peer, done}   -> ok;
        {Peer, _Chunk} -> wait(Peer, r2)
    after ?BOUND_MS ->
        exit(timeout)
    end.

wait_r1(Peer, MRef) ->
    receive
        {Peer, done} ->
            erlang:demonitor(MRef, [flush]),
            ok;
        {Peer, _Chunk} ->
            wait_r1(Peer, MRef);
        {'DOWN', MRef, process, _, Reason} ->
            {peer_down, Reason}
    end.

%% ---------------------------------------------------------------------------
%% The peers -- three ways to violate the invariant, one symptom
%% ---------------------------------------------------------------------------

%% a: dies before sending anything. This is otp's GH-5332 -- a handshake process
%%    crashing between TLS completion and dist handshake start.
peer(_Waiter, a) ->
    exit(normal);

%% b: perfectly healthy, simply stops sending. This is couchdb's middle man.
%%    A monitor learns nothing here: there is nothing to learn.
peer(_Waiter, b) ->
    forever();

%% c: sends, but shaped so the receive cannot match it -- the first element is
%%    some other process. The message lands in the mailbox and stays there.
peer(Waiter, c) ->
    Other = spawn(fun forever/0),
    Waiter ! {Other, done},
    forever().

forever() ->
    receive _ -> forever() end.

%% ---------------------------------------------------------------------------
%% Running one cell
%% ---------------------------------------------------------------------------

run(Cause) -> run(Cause, none).

%% Returns a map; the waiter and peer are LEFT RUNNING so they can be poked at
%% from the shell. cleanup/1 kills them.
run(Cause, Remedy) ->
    Runner = self(),
    Waiter = spawn(fun() ->
                       Peer = receive {peer, P} -> P end,
                       Runner ! {self(), wait(Peer, Remedy)}
                   end),
    MRef = erlang:monitor(process, Waiter),
    Peer = spawn(fun() -> peer(Waiter, Cause) end),
    Waiter ! {peer, Peer},
    Verdict = verdict(Waiter),
    #{cause    => Cause,
      remedy   => Remedy,
      waiter   => Waiter,
      peer     => Peer,
      mref     => MRef,
      verdict  => Verdict,
      outcome  => outcome(Waiter, MRef),
      mailbox  => mailbox_of(Waiter)}.

%% Note what this uses: a monitor, to find out how the waiter ended. It is the
%% same technique remedy 1 applies, one level up -- an observer cannot learn
%% that a process died either, unless it asked to be told.
outcome(Waiter, MRef) ->
    receive
        {Waiter, Result} ->
            erlang:demonitor(MRef, [flush]),
            {returned, Result};
        {'DOWN', MRef, process, Waiter, Reason} ->
            {exited, Reason}
    after 0 ->
        still_waiting
    end.

mailbox_of(Pid) ->
    case process_info(Pid, message_queue_len) of
        {message_queue_len, N} -> N;
        undefined              -> gone
    end.

%% Killing the waiter fires the monitor run/2 took out, so drop it with [flush]
%% -- otherwise matrix/0 leaves nine stray 'DOWN' messages in the caller's
%% mailbox, which is a mildly embarrassing thing for this example to do.
cleanup(#{waiter := W, peer := P, mref := MRef}) ->
    erlang:demonitor(MRef, [flush]),
    exit(W, kill),
    exit(P, kill),
    ok.

%% ---------------------------------------------------------------------------
%% The verdict
%% ---------------------------------------------------------------------------

%% Deliberately narrow. It answers "did this process advance at all", which is
%% all a single process can tell you -- see boundary.erl for what that leaves
%% undecided, and why some of it is undecidable from outside.
%%
%% `stuck` is always relative to the observation window. couchdb's real bound
%% was ten minutes, so a ten-minute window would have called the fixed version
%% stuck too. There is no window-free version of this question.
verdict(Pid) -> verdict(Pid, ?WINDOW_MS).

verdict(Pid, WindowMs) ->
    timer:sleep(?SETTLE_MS),
    W = observe:watch(Pid, WindowMs),
    case {observe:alive(W), maps:get(ever_ran, W, false)} of
        {false, _}    -> gone;
        {true, false} -> stuck;
        {true, true}  -> progressing
    end.

%% ---------------------------------------------------------------------------
%% The matrix
%% ---------------------------------------------------------------------------

matrix() ->
    io:format("~n  family 8 -- Awaited Message Never Arrives~n"),
    io:format("  invariant: every wait on a peer either observes that peer's~n"
              "             death or bounds itself~n~n"),
    io:format("  causes~n"),
    [io:format("    ~-5w ~s~n", [C, describe(C)]) || C <- causes()],
    io:format("~n  remedies~n"),
    [io:format("    ~-5w ~s~n", [R, describe(R)]) || R <- remedies()],
    io:format("~n  ~-8s", [""]),
    [io:format("~-22w", [R]) || R <- remedies()],
    io:format("~n"),
    Rows = [{C, [cell(C, R) || R <- remedies()]} || C <- causes()],
    [begin
         io:format("  ~-8w", [C]),
         [io:format("~-22s", [fmt_cell(Cell)]) || Cell <- Cells],
         io:format("~n")
     end || {C, Cells} <- Rows],
    io:format("~n  q=N is the waiter's mailbox length.~n~n"),
    Rows.

cell(Cause, Remedy) ->
    S = run(Cause, Remedy),
    cleanup(S),
    S.

fmt_cell(#{verdict := stuck, mailbox := Q}) ->
    lists:flatten(io_lib:format("stuck  q=~w", [Q]));
fmt_cell(#{verdict := gone, outcome := {exited, Reason}}) ->
    lists:flatten(io_lib:format("escaped ~w", [Reason]));
fmt_cell(#{verdict := gone, outcome := {returned, {peer_down, _}}}) ->
    "escaped peer_down";
fmt_cell(#{verdict := gone, outcome := {returned, R}}) ->
    lists:flatten(io_lib:format("returned ~w", [R]));
fmt_cell(#{verdict := V, outcome := O}) ->
    lists:flatten(io_lib:format("~w ~w", [V, O])).
