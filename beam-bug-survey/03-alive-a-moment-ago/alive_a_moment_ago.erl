%% "Alive" is knowledge that expires; "dead" is knowledge that lasts.
%%
%% Shape of atomvm/AtomVM#572 (port:call), benoitc/hackney#869 (pool), emqx/emqx#4834
%% (noproc logged as error) and erlang/otp@f6bb3dc (spawn then monitor).
-module(alive_a_moment_ago).
-export([call_checked/2, call_monitored/2, spawn_then_monitor/1, spawn_monitor_/1, demo/0]).

%% BUGGY: the check is a snapshot; the process can die right after it, and nothing wakes us.
%% (The original had no `after`; the 300 ms is only so the demo ends.)
call_checked(Pid, Req) ->
    case is_process_alive(Pid) of
        false -> {error, noproc};
        true ->
            Ref = make_ref(),
            Pid ! {self(), Ref, Req},
            receive {Ref, Reply} -> Reply after 300 -> hung_until_timeout end
    end.

%% FIXED: subscribe to the fact that lasts (death), then send. Reply, DOWN or timeout.
call_monitored(Pid, Req) ->
    Mon = monitor(process, Pid),
    Ref = make_ref(),
    Pid ! {self(), Ref, Req},
    receive
        {Ref, Reply}                      -> demonitor(Mon, [flush]), Reply;
        {'DOWN', Mon, process, Pid, Why}  -> {error, Why}
    after 300 -> demonitor(Mon, [flush]), {error, timeout}
    end.

%% BUGGY: two steps. If the child has already finished, the monitor reports `noproc`
%% and the real exit reason is lost for good.
spawn_then_monitor(F) ->
    Pid = spawn(F),
    timer:sleep(50),                         % "the child finished in between"
    Mon = monitor(process, Pid),
    receive {'DOWN', Mon, process, Pid, Why} -> Why after 500 -> none end.

%% FIXED: one atomic step; the monitor exists before the child can die.
spawn_monitor_(F) ->
    {Pid, Mon} = spawn_monitor(F),
    receive {'DOWN', Mon, process, Pid, Why} -> Why after 500 -> none end.

%% A server that dies on its first request, without replying.
dying_server() -> spawn(fun() -> receive {_From, _Ref, _Req} -> exit(boom) end end).

%% The child finishes BEFORE the monitor is set. That is the race, so for the buggy variant `noproc`
%% is the expected result: the real reason (finished_badly) is gone. The fixed variant keeps it.
demo() ->
    #{buggy_check_then_call_server_dies      => call_checked(dying_server(), hello),     % hung_until_timeout
      fixed_monitor_then_call_server_dies    => call_monitored(dying_server(), hello),   % {error,boom}
      buggy_spawn_then_monitor_exit_reason   => spawn_then_monitor(fun() -> exit(finished_badly) end),  % noproc
      fixed_spawn_monitor_exit_reason        => spawn_monitor_(fun() -> exit(finished_badly) end)}.     % finished_badly
