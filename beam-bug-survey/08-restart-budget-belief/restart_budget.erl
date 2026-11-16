%% A restart budget is a belief about a fault, built from evidence that is not independent.
%%
%% Shape of heroku/logplex#253, oban-bg/oban@a20f0ef, ninenines/ranch#244,
%% blockscout/blockscout#10993 and supabase/realtime@a8a163e. Several children depend on one
%% thing (a network, a database). When it fails they all crash together. The supervisor counts
%% each crash as separate evidence that "this child has a fault that restarting will not
%% clear", gives up after a few, terminates, and takes down a healthy sibling with it.
-module(restart_budget).
-behaviour(supervisor).
-export([demo/0, run/1, flaky_demo/1, start_writer/1, start_healthy/0, start_flaky/1, init/1]).

init({transient, Reason}) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 5},
          [#{id => flaky, start => {?MODULE, start_flaky, [Reason]}, restart => transient}]}};
init(Intensity) ->
    Flags = #{strategy => one_for_one, intensity => Intensity, period => 5},
    Writers = [#{id => {writer, I}, start => {?MODULE, start_writer, [I]}, restart => permanent}
               || I <- lists:seq(1, 4)],
    Healthy = #{id => healthy, start => {?MODULE, start_healthy, []}, restart => permanent},
    {ok, {Flags, [Healthy | Writers]}}.

%% Writers cannot start while the shared dependency `dep` is down, and die when it dies.
start_writer(_I) ->
    case whereis(dep) of
        undefined -> {error, dep_down};
        Dep -> {ok, spawn_link(fun() ->
                                   Mon = monitor(process, Dep),
                                   receive {'DOWN', Mon, _, _, _} -> exit(dep_down) end
                               end)}
    end.

%% A sibling that has nothing to do with the dependency.
start_healthy() -> {ok, spawn_link(fun() -> receive stop -> ok end end)}.

new_dep() -> register(dep, spawn(fun() -> receive stop -> ok end end)).

%% run(Intensity): the dependency is down for 300 ms. Does the supervisor outlive the outage?
run(Intensity) ->
    process_flag(trap_exit, true),
    new_dep(),
    {ok, Sup} = supervisor:start_link(?MODULE, Intensity),
    [{healthy, Healthy, _, _}] = [C || C = {healthy, _, _, _} <- supervisor:which_children(Sup)],
    exit(whereis(dep), kill),           % the outage begins
    timer:sleep(300),
    new_dep(),                          % the outage ends
    timer:sleep(300),
    R = #{supervisor_alive => is_process_alive(Sup), healthy_sibling_alive => is_process_alive(Healthy)},
    case is_process_alive(Sup) of true -> exit(Sup, shutdown); false -> ok end,
    exit(whereis(dep), kill),
    timer:sleep(50),
    flush(),
    R.

%% logplex also changed `exit(normal)` to an abnormal exit: a `transient` child that exits
%% `normal` has told its supervisor "I finished", so it is not restarted, although it failed.
start_flaky(Reason) ->
    case ets:whereis(flaky_seen) of
        undefined ->
            ets:new(flaky_seen, [named_table, public]),
            {ok, spawn_link(fun() -> timer:sleep(20), exit(Reason) end)};
        _ -> {ok, spawn_link(fun() -> receive stop -> ok end end)}
    end.

flaky_demo(Reason) ->
    process_flag(trap_exit, true),
    {ok, Sup} = supervisor:start_link(?MODULE, {transient, Reason}),
    ets:insert(flaky_seen, {seen}),
    timer:sleep(150),
    Live = length([P || {_, P, _, _} <- supervisor:which_children(Sup), is_pid(P)]),
    exit(Sup, shutdown), timer:sleep(30), catch ets:delete(flaky_seen), flush(),
    Live.

flush() -> receive _ -> flush() after 0 -> ok end.

demo() ->
    logger:set_primary_config(level, none),       % every failed restart is reported; keep the output readable
    #{intensity_3_in_5s     => run(3),        % the budget is spent on one shared cause
      intensity_100000_in_5s => run(100000),  % raising the threshold keeps the siblings
      transient_child_exits_normal  => flaky_demo(normal),            % live children after failure: 0
      transient_child_exits_abnormal => flaky_demo({error, bad_reply})}.  % 1
