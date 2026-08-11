-module(main).
-export([start/0]).

-record(rd, {
    x,
    y = 0
}).

start() ->
    Me = self(),
    N = 1,
    R = new_rd(N),
    C = spawn(fun() -> consumer(Me) end),
    C ! {go, R},
    receive
        {C, og, _N2} -> exit(C, ok)
    end.

consumer(Pid) ->
    Me = self(),
    receive
        {go, Q} ->
            Q2 = rd_incr(Q),
            Sum = rd_sum(Q2),
            erlang:send(Pid(Me, og, Sum))
    end.

new_rd(X) when is_integer(X), X > 0 ->
    #rd{x = X, y = -X};
new_rd(X) ->
    #rd{x = X}.

rd_incr(R = #rd{y = Y}) ->
    R#rd{x = R#rd.x + 1, y = Y + 1}.

rd_sum(R = #rd{x = X}) ->
    Y = R#rd.y,
    Y + X.
