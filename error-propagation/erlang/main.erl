-module(main).
-export([start/0]).


-record(shared_resource,{a::pos_integer(),b::pos_integer(),c::pos_integer()}).

start() ->
  SR = new_shared_resource(),
  M = spawn(fun shared_resource_manager/1, [SR]),
  loop(M).


loop(M) ->
  try
    _X = spawn(fun transactor/2, [M,a]),
    _Y = spawn(fun transactor/2, [M,b]),
    _Z = spawn(fun transactor/2, [M,c]),
  catch
  % catch a failed transaction, retry and loop
    {abort,waiting,Label} ->
      spawn(fun transactor/2, [M,Label]),
      loop(M);
  % crash on other error
    Err -> exit(Err)
  end.


transactor(M,Label) ->
  try
    M ! {update,Label,fun(X) -> X+1 end}
  catch
  % allow this error to be propagated back up
    {abort,waiting,Label}=Err -> exit({abort,waiting,Label});
  % below would swallow all errors and make them unrecognizable to the main loop
    Err -> exit({Label,Err})
  end.



new_shared_resource() -> #shared_resource#{a=0,b=0,c=0}.

get_shared_resource(a, #shared_resource{a=A}) -> A;
get_shared_resource(b, #shared_resource{b=B}) -> B;
get_shared_resource(c, #shared_resource{c=C}) -> C.

set_shared_resource(a, X, SR) -> SR#shared_resource{a=X};
set_shared_resource(b, X, SR) -> SR#shared_resource{b=X};
set_shared_resource(c, X, SR) -> SR#shared_resource{c=X}.



shared_resource_updater(Manager,Fun,X,Label) ->
  erlang:send_after(50, self(), do_update),
  receive do_update -> Manager ! {Label,apply(Fun,[X])} end.


shared_resource_manager(SR) -> shared_resource_manager(ready,SR).

shared_resource_manager(ready, SR) ->
  receive
    {{updated,Label},_} -> exit({abort,ready,Label});
    {update, Label, Fun} ->
      Field = get_shared_resource(Label,SR),
      Pid = self(),
      spawn(fun() -> shared_resource_updater(Pid,Fun,A,{updated,Field}) end),
      shared_resource_manager(waiting, SR)
  end;

shared_resource_manager(waiting, SR = #shared_resource{a=A,b=B,c=C}) ->
  receive
    {update,Label,_} -> exit({abort,waiting,Label});
    {{updated, Label}, X} ->
      NewSR = set_shared_resource(Label, X, SR),
      shared_resource_manager(ready, NewSR)
  end.

