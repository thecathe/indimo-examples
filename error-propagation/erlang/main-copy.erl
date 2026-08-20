-module('main-copy').
-export([start/0, start/1]).

%% Reworked MWE for the ejabberd/mnesia exit:{aborted,_} swallowing bug
%% (processone/ejabberd@ca05bbd6, mod_pubsub:do_transaction/4).
%%
%% Mapping to the real mnesia mechanism:
%%   shared_resource_manager -> mnesia_locker (shared arbiter; replies to
%%     requests, never exits itself on conflict)
%%   attempt_update/2        -> the lock-acquisition call inside
%%     mnesia_locker:do_sticky_lock/4 (runs in the *requester's* process;
%%     it is the requester that locally exit()s on a conflicting reply)
%%   do_transaction/3        -> mod_pubsub:do_transaction/4, buggy vs fixed
%%     catch clause ordering
%%   transactor/3,4          -> mnesia_tm:execute_transaction/5 +
%%     check_exit/7 + maybe_restart/6 + restart/9 (in-process retry loop)
%%
%% The exit that models mnesia's internal retry signal is raised and
%% caught within a single process's call stack throughout - never sent
%% as a message and relied upon to cross a process boundary as an
%% exception, since Erlang exceptions cannot do that.

-record(shared_resource,{a::non_neg_integer(),b::non_neg_integer(),c::non_neg_integer()}).


start() -> start(fixed).

start(Mode) when Mode == buggy; Mode == fixed ->
  SR = new_shared_resource(),
  M = spawn(fun() -> shared_resource_manager(SR) end),
  spawn(fun() -> transactor(Mode, M, a) end),
  spawn(fun() -> transactor(Mode, M, b) end),
  spawn(fun() -> transactor(Mode, M, c) end),
  ok.


%% ---- transactor: mnesia_tm:execute_transaction-style in-process retry loop ----

transactor(Mode, M, Label) ->
  transactor(Mode, M, Label, 20).

transactor(Mode, M, Label, RetriesLeft) ->
  try do_transaction(Mode, M, Label) of
    {ok, NewVal} ->
      io:format("transactor(~p): committed, new value = ~p~n", [Label, NewVal])
  catch
    exit:{aborted, {waiting, _}} when RetriesLeft > 0 ->
      timer:sleep(15),
      transactor(Mode, M, Label, RetriesLeft - 1);
    exit:{aborted, Reason} ->
      io:format("transactor(~p): gave up, reason=~p~n", [Label, Reason]);
    Class:Reason ->
      io:format("transactor(~p): UNEXPECTED failure surfaced instead of "
                "retrying:~n    ~p:~p~n", [Label, Class, Reason])
  end.


%% ---- do_transaction: mod_pubsub:do_transaction/4-style wrapper ----
%% buggy: over-broad catch-all reshapes everything, including mnesia's own
%%   retry signal, into a new exit - the retry loop above can no longer
%%   recognise it as exit:{aborted,{waiting,_}}.
%% fixed: a specific clause re-raises exit:{aborted,_} unchanged before the
%%   catch-all runs, letting the retry signal reach the caller intact.

do_transaction(buggy, M, Label) ->
  try attempt_update(M, Label)
  catch
    Class:Reason:ST ->
      exit({wrapped, Class, Reason, ST})
  end;

do_transaction(fixed, M, Label) ->
  try attempt_update(M, Label)
  catch
    exit:{aborted, _} = Err ->
      exit(Err);
    Class:Reason:ST ->
      exit({wrapped, Class, Reason, ST})
  end.


%% ---- attempt_update: mnesia_locker:do_sticky_lock-style request ----
%% Sends the request to the shared arbiter and, on a conflicting reply,
%% raises the abort locally in this (the requester's) process - exactly
%% like mnesia_locker receiving a reply and then exit()ing itself, rather
%% than the arbiter exiting on the requester's behalf.

attempt_update(M, Label) ->
  M ! {update, self(), Label, fun(X) -> X + 1 end},
  receive
    {ok, Label, NewVal} -> {ok, NewVal};
    {conflict, {aborted, _} = Reason} -> exit(Reason)
  end.


%% ---- shared_resource_manager: mnesia_locker-style arbiter ----
%% Never exits on conflict; only ever replies to the requester.

shared_resource_manager(SR) -> shared_resource_manager(ready, SR).

shared_resource_manager(ready, SR) ->
  receive
    {update, From, Label, Fun} ->
      Field = get_shared_resource(Label, SR),
      Manager = self(),
      spawn(fun() -> shared_resource_updater(Manager, From, Fun, Field, Label) end),
      shared_resource_manager(waiting, SR)
  end;

shared_resource_manager(waiting, SR) ->
  receive
    {update, From, Label, _Fun} ->
      From ! {conflict, {aborted, {waiting, Label}}},
      shared_resource_manager(waiting, SR);
    {done, Label, NewVal} ->
      NewSR = set_shared_resource(Label, NewVal, SR),
      shared_resource_manager(ready, NewSR)
  end.


shared_resource_updater(Manager, From, Fun, X, Label) ->
  erlang:send_after(50, self(), do_update),
  receive
    do_update ->
      NewVal = Fun(X),
      From ! {ok, Label, NewVal},
      Manager ! {done, Label, NewVal}
  end.


%% ---- shared_resource record helpers ----

new_shared_resource() -> #shared_resource{a=0,b=0,c=0}.

get_shared_resource(a, #shared_resource{a=A}) -> A;
get_shared_resource(b, #shared_resource{b=B}) -> B;
get_shared_resource(c, #shared_resource{c=C}) -> C.

set_shared_resource(a, X, SR) -> SR#shared_resource{a=X};
set_shared_resource(b, X, SR) -> SR#shared_resource{b=X};
set_shared_resource(c, X, SR) -> SR#shared_resource{c=X}.
