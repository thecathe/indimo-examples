-module(observe).

%% The symptom oracle.
%%
%% A fixed, family-independent read of what a process is doing right now. This
%% module deliberately does NOT know what a failure family is: it reports, and
%% each family's own module decides what the report means. That split is what
%% stops this file growing every time a family is added -- a new family adds a
%% verdict function in its own directory and touches nothing here.
%%
%% It is the successor to findall/erlang/sup.erl, which met the same problem one
%% family at a time. As that example's README puts it: a Go program can detect
%% its own deadlock, an Erlang one cannot, so sup.erl demanded a heartbeat and
%% declared the main process stuck when one failed to arrive. A heartbeat tells
%% you THAT progress stopped. It cannot tell you WHICH failure stopped it,
%% because a starved process, a deadlocked process and a spinning process all
%% fail to send one alike. The vector below separates those cases.
%%
%% Two things here are less obvious than they look:
%%
%%   reductions.  `status` alone cannot distinguish blocked from spinning -- a
%%   snapshot of a busy process often reads `running`, and one of a process
%%   between reschedules reads `runnable`. Progress is only observable as a
%%   DIFFERENCE, so every reading takes two samples and reports the delta.
%%
%%   the cost of looking.  That difference is not clean, because observing a
%%   process is not free and the cost lands on the process being OBSERVED:
%%   process_info/2 charges the target exactly one reduction per call, however
%%   many keys it asks for. Measured on OTP 28.5 -- 1, 10, 100 and 1000 polls of
%%   a blocked process move its reduction count by exactly 1, 10, 100 and 1000,
%%   while a process left alone for 500ms moves by 0. So a naive delta reports
%%   the observer's own footprint as the target's progress, and every blocked
%%   process reads as busy. The floor for K readings is K-1 (a reading cannot
%%   see its own charge), and that is what net/2 subtracts. Every predicate
%%   below uses the corrected figure; `raw_reductions` keeps the uncorrected one
%%   so the correction stays visible rather than hidden.
%%
%%   monitors.  A bare `receive` records nothing about who it expects to hear
%%   from, so the runtime cannot tell you what a blocked process is waiting FOR.
%%   A `gen_server:call` monitors its callee, which puts that edge in
%%   process_info/2 where an observer can read it. So the wait-for graph is
%%   recoverable exactly when the waiter arranged to observe its peer -- the
%%   same act this family's invariant demands. See the README.

-export([vector/1, vector/2, watch/2, watch/3]).
-export([alive/1, blocked/1, spinning/1, mailbox/1, mailbox_empty/1, wait_for/1]).
-export([format/1, print/1, print/2]).

%% Let the scenario reach steady state before the first reading.
-define(SETTLE_MS, 200).
%% Gap between the two samples a reductions delta is taken across.
-define(SAMPLE_MS, 100).
%% Polling interval used by watch/2,3.
-define(POLL_MS, 50).

%% ---------------------------------------------------------------------------
%% Instantaneous reading
%% ---------------------------------------------------------------------------

%% vector(Pid) -> #{alive := boolean(), ...}
%%
%% Keys when alive: status, mailbox, reductions, delta_reductions,
%% current_function, stack, monitors.
vector(Pid) -> vector(Pid, ?SETTLE_MS).

vector(Pid, SettleMs) ->
    timer:sleep(SettleMs),
    case snapshot(Pid) of
        dead ->
            #{alive => false};
        S0 ->
            timer:sleep(?SAMPLE_MS),
            case snapshot(Pid) of
                dead ->
                    #{alive => false};
                S1 ->
                    Raw = maps:get(reductions, S1) - maps:get(reductions, S0),
                    S1#{alive            => true,
                        probes           => 2,
                        raw_reductions   => Raw,
                        delta_reductions => net(Raw, 2)}
            end
    end.

%% Reductions actually spent by the process, once the observer's own footprint
%% is taken back out. See the header note.
net(Raw, Probes) -> max(0, Raw - (Probes - 1)).

snapshot(Pid) ->
    case process_info(Pid, [status, message_queue_len, reductions,
                            current_function, current_stacktrace, monitors]) of
        undefined ->
            dead;
        Info ->
            #{status           => proplists:get_value(status, Info),
              mailbox          => proplists:get_value(message_queue_len, Info),
              reductions       => proplists:get_value(reductions, Info),
              current_function => proplists:get_value(current_function, Info),
              stack            => proplists:get_value(current_stacktrace, Info),
              monitors         => proplists:get_value(monitors, Info)}
    end.

%% ---------------------------------------------------------------------------
%% Reading over a window
%% ---------------------------------------------------------------------------

%% A single vector cannot tell a permanently blocked process from one that wakes
%% periodically -- sample either between wakeups and both read `waiting` with an
%% empty mailbox. Only a window long enough to span a wakeup separates them, so
%% anything that must rule out intermittent progress uses this rather than
%% vector/1.
watch(Pid, WindowMs) -> watch(Pid, WindowMs, ?POLL_MS).

watch(Pid, WindowMs, PollMs) ->
    Deadline = erlang:monotonic_time(millisecond) + WindowMs,
    case snapshot(Pid) of
        dead ->
            gone(WindowMs, 1, 0);
        S0 ->
            watch_loop(Pid, Deadline, PollMs, WindowMs,
                       maps:get(reductions, S0), maps:get(mailbox, S0), 1)
    end.

watch_loop(Pid, Deadline, PollMs, WindowMs, R0, MaxQ, Probes) ->
    case erlang:monotonic_time(millisecond) >= Deadline of
        true ->
            watch_result(Pid, WindowMs, R0, MaxQ, Probes);
        false ->
            timer:sleep(PollMs),
            case snapshot(Pid) of
                dead ->
                    %% Exiting is progress: whatever else it did, it did not sit
                    %% blocked for the whole window.
                    gone(WindowMs, Probes + 1, MaxQ);
                S ->
                    watch_loop(Pid, Deadline, PollMs, WindowMs, R0,
                               max(MaxQ, maps:get(mailbox, S)), Probes + 1)
            end
    end.

watch_result(Pid, WindowMs, R0, MaxQ, Probes0) ->
    Probes = Probes0 + 1,
    case snapshot(Pid) of
        dead ->
            gone(WindowMs, Probes, MaxQ);
        S ->
            Raw = maps:get(reductions, S) - R0,
            Net = net(Raw, Probes),
            #{window_ms        => WindowMs,
              probes           => Probes,
              alive            => true,
              status           => maps:get(status, S),
              ever_ran         => Net > 0,
              raw_reductions   => Raw,
              total_reductions => Net,
              max_mailbox      => max(MaxQ, maps:get(mailbox, S))}
    end.

gone(WindowMs, Probes, MaxQ) ->
    #{window_ms        => WindowMs,
      probes           => Probes,
      alive            => false,
      ever_ran         => true,
      raw_reductions   => 0,
      total_reductions => 0,
      max_mailbox      => MaxQ}.

%% ---------------------------------------------------------------------------
%% Generic predicates
%%
%% Properties of BEAM processes, not of failure families. Nothing below names a
%% family, and nothing below should ever need to.
%% ---------------------------------------------------------------------------

alive(V) -> maps:get(alive, V, false).

mailbox(V) -> maps:get(mailbox, V, maps:get(max_mailbox, V, 0)).

mailbox_empty(V) -> mailbox(V) =:= 0.

%% Alive, sitting in a receive, and no reductions between the two samples.
blocked(V) ->
    alive(V)
        andalso maps:get(status, V, undefined) =:= waiting
        andalso maps:get(delta_reductions, V, 0) =:= 0.

spinning(V) ->
    alive(V) andalso maps:get(delta_reductions, V, 0) > 0.

%% Who this process would learn about the death of. For a bare `receive` this is
%% empty even though the process is plainly waiting on someone -- which is the
%% point: the runtime knows only what the waiter arranged to be told.
wait_for(V) ->
    [Target || {process, Target} <- maps:get(monitors, V, [])].

%% ---------------------------------------------------------------------------
%% Rendering
%% ---------------------------------------------------------------------------

format(V) ->
    lists:flatten(do_format(V)).

do_format(#{alive := false}) ->
    "exited";
do_format(#{status := Status} = V) ->
    io_lib:format("~-8s q=~-3w dr=~-7w ~s~s",
                  [Status, mailbox(V), maps:get(delta_reductions, V, 0),
                   fmt_mfa(maps:get(current_function, V, undefined)),
                   fmt_waits(wait_for(V))]);
do_format(V) ->
    io_lib:format("~p", [V]).

fmt_mfa({M, F, A}) -> io_lib:format("~w:~w/~w", [M, F, A]);
fmt_mfa(_)         -> "-".

fmt_waits([])    -> "";
fmt_waits(Pids)  -> io_lib:format("  waits-for=~w", [Pids]).

print(Pid) -> print(Pid, "").

print(Pid, Label) ->
    io:format("  ~-28s ~s~n", [Label, format(vector(Pid))]).
