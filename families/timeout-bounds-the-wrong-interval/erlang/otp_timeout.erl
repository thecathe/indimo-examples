-module(otp_timeout).
-behaviour(gen_server).

%% erlang/otp#9615 (id 114), run against whatever runtime you are on.
%%
%% This one is not distilled. The other scenarios in tbwi.erl are reconstructions
%% of fixes; this is the real thing, still in stdlib, and it is worth running
%% rather than paraphrasing because of what the fix did.
%%
%% Before #9615: gen_server's plain timeout -- the bare integer in
%% {noreply, State, 500} -- lived in the `after` of the main receive. A system
%% message came out of that receive like any other message and went off to
%% sys:handle_system_msg. What it came back to was loop_continue/5, which chose
%% between `hibernate` and `infinity` and knew nothing about a pending timeout.
%% The bound was gone. One sys:get_status/1 was enough.
%%
%% #9615 fixed that by carrying the loop action across the system message, so
%% the timeout survives. Read what it survives AS:
%%
%%   system_continue(Parent, Debug, [ServerData, State, HibT, Timer]) ->
%%       loop(update_callback_cache(ServerData), State, HibT, Debug, Timer).
%%
%%   loop(ServerData, State, Time, Debug, Timer) when ?is_rel_timeout(Time) ->
%%       receive Msg -> ... after Time -> ... end.
%%
%% `Time`, not what is left of it. There is no remaining-time arithmetic
%% anywhere in gen_server. So the timeout is not resumed, it is RE-ARMED, at its
%% full value, by every system message -- and a system message is meant to be
%% invisible to the state machine. Poll a gen_server faster than its own timeout
%% and the timeout never fires.
%%
%% Which is id 26. The fix for the M-empty row of family 35 moved the bug to the
%% M-subset-I row of family 35, and the corpus records it as a fix.
%%
%% OTP knows. From the action() docs in stdlib:
%%
%%   Note: A system message restarts the time-out, which is a known and
%%   unfortunate flaw in its implementation. This also applies to stray
%%   (cancelled) timer messages from the {timeout|hibernate, ...} time-outs
%%   described below, so it is recommended to not use them in combination
%%   with this legacy time-out type.
%%
%% and the remedy offered is {timeout, Time, Message}, which is "not affected by
%% system messages" and can be made absolute with {abs, true}. That is hackney's
%% fix, in the standard library, arrived at from the other direction.
%%
%% table/0 MEASURES all of this rather than asserting it. It prints the release
%% and stdlib version it ran against and reports what it saw. If a future OTP
%% closes the flaw, the row changes and says so; nothing here breaks.

-export([table/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% The bound under test.
-define(BOUND_MS, 300).
%% Comfortably under ?BOUND_MS, so every poll lands before the timer expires.
-define(POLL_MS, 120).
%% How long to wait before conceding a timeout never fired. Five times the
%% bound; ten seconds behaves identically, it just makes `make run` slow.
-define(BUDGET_MS, 1500).

%% ---------------------------------------------------------------------------
%% The server
%% ---------------------------------------------------------------------------

%% Two ways to arm the same bound: the legacy plain timeout, and the OTP-28
%% action. Both reply first, so the caller knows the timer is running.
init([]) -> {ok, undefined}.

handle_call({arm, plain, T}, {Pid, _}, _S) ->
    {reply, ok, Pid, T};
handle_call({arm, action, T}, {Pid, _}, _S) ->
    {reply, ok, Pid, {timeout, T, tick}};
handle_call(ping, _From, S) ->
    {reply, pong, S}.

handle_cast(_Msg, S) -> {noreply, S}.

%% `timeout` from the plain bound, `tick` from the action. Same event.
handle_info(Which, Pid) when Which =:= timeout; Which =:= tick ->
    Pid ! {fired, erlang:monotonic_time(millisecond)},
    {noreply, undefined};
handle_info(_Msg, S) ->
    {noreply, S}.

%% ---------------------------------------------------------------------------
%% The measurements
%% ---------------------------------------------------------------------------

table() ->
    {ok, Vsn} = application:get_key(stdlib, vsn),
    io:format("~n  114 -- gen_server's own timeout, on the runtime you are on~n~n"),
    io:format("  otp ~s / stdlib ~s.  bound ~wms, polled every ~wms,~n"
              "  budget ~wms (~w x the bound).~n~n",
              [erlang:system_info(otp_release), Vsn,
               ?BOUND_MS, ?POLL_MS, ?BUDGET_MS, ?BUDGET_MS div ?BOUND_MS]),

    Alone   = left_alone(plain),
    Polled  = polled(plain),
    After   = polled_then_stopped(plain),
    Action  = polled(action),

    io:format("  ~-46s ~s~n", ["plain timeout, left alone", fmt(Alone)]),
    io:format("  ~-46s ~s~n", ["plain timeout, sys:get_status throughout", fmt(Polled)]),
    io:format("  ~-46s ~s~n", ["  ... measured again once polling stops", fmt(After)]),
    io:format("  ~-46s ~s~n", ["{timeout, T, tick} action, same polling", fmt(Action)]),

    io:format("~n  ~s~n~n", [conclusion(Alone, Polled, Action)]),
    {Alone, Polled, After, Action}.

%% The control. Nothing touches the server; the bound should just fire.
left_alone(Kind) ->
    {P, T0} = arm(Kind),
    R = await(?BUDGET_MS, T0),
    stop(P),
    R.

%% A system message every ?POLL_MS, for the whole budget.
polled(Kind) ->
    {P, T0} = arm(Kind),
    Poller = spawn(fun() -> poll_forever(P) end),
    R = await(?BUDGET_MS, T0),
    exit(Poller, kill),
    stop(P),
    R.

%% The same, but keep listening after the polling stops. If the bound was merely
%% postponed rather than lost, it lands one full bound after the last poll --
%% which is the difference between this being a re-arm and being a cancel.
polled_then_stopped(Kind) ->
    {P, T0} = arm(Kind),
    Poller = spawn(fun() -> poll_forever(P) end),
    never_fired = await(?BUDGET_MS, T0),
    Stopped = erlang:monotonic_time(millisecond),
    exit(Poller, kill),
    R = case await(?BUDGET_MS, Stopped) of
            never_fired    -> never_fired;
            {fired, After} -> {fired_after_stopping, After}
        end,
    stop(P),
    R.

%% Arm the bound and start the clock. The call returns once the server has
%% replied, so the timer is running by the time T0 is taken.
arm(Kind) ->
    {ok, P} = gen_server:start(?MODULE, [], []),
    pong = gen_server:call(P, ping),
    ok = gen_server:call(P, {arm, Kind, ?BOUND_MS}),
    {P, erlang:monotonic_time(millisecond)}.

await(Budget, T0) ->
    receive
        {fired, At} -> {fired, At - T0}
    after Budget ->
        never_fired
    end.

poll_forever(P) ->
    timer:sleep(?POLL_MS),
    _ = sys:get_status(P),
    poll_forever(P).

stop(P) ->
    exit(P, kill),
    flush().

%% A killed server may already have sent its {fired, _}; do not let it land in
%% the next measurement's mailbox.
flush() ->
    receive {fired, _} -> flush() after 0 -> ok end.

%% ---------------------------------------------------------------------------
%% What was observed
%% ---------------------------------------------------------------------------

fmt(never_fired) ->
    io_lib:format("never fired (~wms)", [?BUDGET_MS]);
fmt({fired, Ms}) ->
    io_lib:format("fired after ~wms", [Ms]);
%% The re-arm happened at the LAST POLL, which was up to ?POLL_MS before polling
%% stopped -- so this figure plus that gap is the bound, and the sum is the
%% evidence that the timeout was postponed rather than lost.
fmt({fired_after_stopping, Ms}) ->
    io_lib:format("fired ~wms later (+ up to ~wms since the last poll = ~wms)",
                  [Ms, ?POLL_MS, ?BOUND_MS]).

%% Derived from the readings, never assumed. The interesting case is the first;
%% the others are here so that a runtime which behaves differently gets said so
%% rather than silently producing a table that means something else.
conclusion({fired, _}, never_fired, {fired, _}) ->
    "observed: a system message RESTARTS the plain timeout, so polling\n"
    "  postpones it indefinitely. the {timeout,_,_} action is immune. this is\n"
    "  the documented flaw -- and it is id 26's bug, inside the fix for 114.";
conclusion({fired, _}, never_fired, never_fired) ->
    "observed: polling suppresses BOTH the plain timeout and the action.\n"
    "  that is not what stdlib 7.3 does -- the action is meant to be immune.\n"
    "  worth looking at before trusting the rest of this table.";
conclusion({fired, _}, {fired, _}, _) ->
    "observed: polling did NOT suppress the plain timeout. this runtime does\n"
    "  not have the documented flaw -- either it has been fixed since, or the\n"
    "  poll interval was not short enough relative to the bound.";
conclusion(never_fired, _, _) ->
    "observed: the control never fired either, so nothing here is measuring\n"
    "  what it claims to. check the server started.".
