%% Check, then act: the check's knowledge expires before the act.
%%
%% Shape of akira/exq#87 (a worker count read, then written back), emqx/emqx#17575 and
%% vernemq/vernemq#509 (counters). Many agents each read a shared cell and write back a
%% value derived from it; between the read and the write another agent's write lands.
-module(entry_race).
-export([read_then_write/2, update_counter/2, run/2, demo/0]).

%% The read gives knowledge of N *now*; the write acts on it *later*.
read_then_write(T, K) ->
    [{_, N}] = ets:lookup(T, K),
    erlang:yield(),                  % widen the window, as scheduling does under load
    ets:insert(T, {K, N + 1}).

%% Check and act are one step, taken at the owner of the cell.
update_counter(T, K) -> ets:update_counter(T, K, 1), ok.

run(Incr, Workers) ->
    T = ets:new(entry, [public, set]),
    ets:insert(T, {k, 0}),
    Self = self(),
    Pids = [spawn_link(fun() -> Incr(T, k), Self ! {done, self()} end) || _ <- lists:seq(1, Workers)],
    [receive {done, P} -> ok end || P <- Pids],
    [{_, N}] = ets:lookup(T, k),
    ets:delete(T),
    N.

demo() ->
    #{workers => 200,
      read_then_write_total => run(fun read_then_write/2, 200),   % far below 200: most updates are lost
      update_counter_total  => run(fun update_counter/2, 200)}.
