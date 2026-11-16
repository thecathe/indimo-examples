%% "Alive" is knowledge that expires; "dead" is knowledge that lasts.
%%
%% Shape of atomvm/AtomVM#572 (port:call), benoitc/hackney#869 (pool), emqx/emqx#4834
%% (noproc logged as error) and erlang/otp@f6bb3dc (spawn then monitor).
%%
%% Part A (check, then call): call_checked/3 and call_monitored/3, run against an explicit
%% environment by run/2. check_then_call_model.erl is the same interaction as a model, and
%% checks that its predictions agree with run/2.
%% Part B (spawn, then monitor): spawn_then_monitor/1 and spawn_monitor_/1. Parked for now.
-module(alive_a_moment_ago).
-export([call_checked/3, call_monitored/3, run/2, positions/0,
         spawn_then_monitor/1, spawn_monitor_/1, demo/0]).

%% ---------------------------------------------------------------------------------------
%% Part A. The caller. Seam/1 is called at fixed points of the caller's own code and does
%% nothing in real use; it is where an environment can act (see run/2).

%% BUGGY: the check is a snapshot; the server can die right after it, and nothing wakes us.
%% (The original had no `after`; the 300 ms is only so the demo ends.)
call_checked(Pid, Req, Seam) ->
    Seam(before_first_step),
    Alive = is_process_alive(Pid),
    Seam(after_first_step),
    case Alive of
        false -> {error, noproc};
        true ->
            Ref = make_ref(),
            Pid ! {self(), Ref, Req},
            Seam(after_send),
            receive {Ref, Reply} -> Reply after 300 -> hung_until_timeout end
    end.

%% FIXED: subscribe to the fact that lasts (death), then send. Reply, DOWN or timeout.
call_monitored(Pid, Req, Seam) ->
    Seam(before_first_step),
    Mon = monitor(process, Pid),
    Seam(after_first_step),
    Ref = make_ref(),
    Pid ! {self(), Ref, Req},
    Seam(after_send),
    receive
        {Ref, Reply}                     -> demonitor(Mon, [flush]), Reply;
        {'DOWN', Mon, process, Pid, Why} -> {error, Why}
    after 300 -> demonitor(Mon, [flush]), {error, timeout}
    end.

%% ---------------------------------------------------------------------------------------
%% The environment. A server that handles a request only when released, and a driver that
%% decides, at each seam, whether to kill the server (or release it first). Exactly one
%% kill position per run; `after_done` kills nothing before the caller has finished.

positions() -> [before_first_step, after_first_step, after_send, after_reply, after_done].

%% run(Variant, KillAt) -> what the caller returned. Variant: liveness_check | monitor.
run(Variant, KillAt) ->
    Driver = self(),
    Server = spawn(fun() -> gated_server(Driver) end),
    Seam = fun(Point) -> Driver ! {at, Point}, receive proceed -> ok end end,
    Call = case Variant of liveness_check -> fun call_checked/3; monitor -> fun call_monitored/3 end,
    Caller = spawn(fun() -> Driver ! {result, Call(Server, hello, Seam)} end),
    Result = drive(Caller, Server, KillAt),
    kill(Server),
    Result.

%% A server that, once it has a request, waits for `go` before replying.
gated_server(Driver) ->
    receive {From, Ref, Req} ->
        receive go -> From ! {Ref, {ok, Req}}, Driver ! replied end
    end.

drive(Caller, Server, KillAt) ->
    receive
        {at, Point} ->
            act(Point, KillAt, Server),
            Caller ! proceed,
            drive(Caller, Server, KillAt);
        {result, R} -> R
    end.

act(Point, Point, Server) when Point =/= after_send -> kill(Server);
act(after_send, KillAt, Server) ->
    case KillAt of
        after_send  -> kill(Server);                         % dies before it handles the request
        after_reply -> Server ! go, wait_replied(), kill(Server);
        after_done  -> Server ! go, wait_replied();
        _           -> ok                                    % an earlier kill: nothing to release
    end;
act(_, _, _) -> ok.

wait_replied() -> receive replied -> ok after 500 -> ok end.

%% Kill, and wait until the server is certainly dead, so the schedule is deterministic.
kill(Pid) ->
    M = monitor(process, Pid), exit(Pid, kill),
    receive {'DOWN', M, _, _, _} -> ok end.

%% ---------------------------------------------------------------------------------------
%% Part B. Spawn, then monitor. The child finishes BEFORE the monitor is set; that is the
%% race. The monitor then reports `noproc`: it tells us the process is gone, but the exit
%% reason, which is the information a monitor exists to deliver, is lost.
spawn_then_monitor(F) ->
    Pid = spawn(F),
    timer:sleep(50),                         % "the child finished in between"
    Mon = monitor(process, Pid),
    receive {'DOWN', Mon, process, Pid, Why} -> Why after 500 -> none end.

%% One atomic step: the monitor exists before the child can die, so the reason is kept.
spawn_monitor_(F) ->
    {Pid, Mon} = spawn_monitor(F),
    receive {'DOWN', Mon, process, Pid, Why} -> Why after 500 -> none end.

demo() ->
    #{liveness_check_by_kill_position => [{P, run(liveness_check, P)} || P <- positions()],
      monitor_by_kill_position        => [{P, run(monitor, P)} || P <- positions()],
      spawn_then_monitor_reason       => spawn_then_monitor(fun() -> exit(finished_badly) end),  % noproc
      spawn_monitor_reason            => spawn_monitor_(fun() -> exit(finished_badly) end)}.     % finished_badly
