%%%-------------------------------------------------------------------
%%% @doc Consumer worker.
%%%
%%% Registers under the well-known name `rate_consumer` so producers
%%% can send to it by name, surviving restarts without PID coupling.
%%%
%%% Drains its mailbox at `Rate` messages per second using a
%%% self-scheduled tick. Each tick processes exactly one message (or
%%% does nothing if the mailbox is empty). This models a server whose
%%% service time is 1/Rate seconds per message.
%%%
%%% Metrics emitted every ?REPORT_INTERVAL ticks so you can observe
%%% the queue depth trend without external tooling.
%%%-------------------------------------------------------------------
-module(consumer).
-behaviour(gen_statem).

-export([start_link/2]).
-export([init/1, handle_event/4, terminate/2, code_change/3, callback_mode/0]).

-define(NAME, rate_consumer).
%% ticks between queue-depth reports
-define(REPORT_INTERVAL, 20).
-define(CONSUME_PERIOD, 1).

-record(data, {
    %% msgs/sec we can consume
    rate :: pos_integer(),
    processed :: non_neg_integer(),
    tick_count :: non_neg_integer(),
    tick_mult :: pos_integer(),
    backlog :: non_neg_integer()
}).

new_data(Rate, Tick) ->
    #data{rate = Rate, tick_mult = Tick, processed = 0, tick_count = 0, backlog = 0}.

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

start_link(Rate, Tick) ->
    gen_statem:start_link({local, ?NAME}, ?MODULE, {Rate, Tick}, []).

%%--------------------------------------------------------------------
%% gen_statem callbacks
%%--------------------------------------------------------------------

callback_mode() -> handle_event_function.

init({Rate, Tick}) ->
    log(init, started, io_lib:format("  rate=~w msg/s   tick_multi=~w", [Rate, Tick])),
    Data = new_data(Rate, Tick),
    {ok, waiting, Data, tick(Data)}.

handle_event({timeout, tick}, open, _State = waiting, Data) ->
    {next_state, consume, Data, {state_timeout, ?CONSUME_PERIOD, closed}};
handle_event(state_timeout, closed, State = consume, Data = #data{tick_count = T}) ->
    Data2 = Data#data{tick_count = T + 1},
    maybe_report(State, Data2),
    {next_state, waiting, Data2, tick(Data2)};
handle_event(info, {work, _Id, _Seq}, State = consume, Data = #data{tick_count = T, processed = P}) ->
    log(State, consumed, io_lib:format("work {~w, ~w}", [_Id, _Seq])),
    Data1 = Data#data{processed = P + 1, tick_count = T + 1},
    %% still report what would be the backlog if the state change wouldn't occur
    maybe_report(State, Data1#data{backlog = dec_backlog(Data#data.backlog)}),
    Data2 = Data1#data{backlog = 0},
    {next_state, waiting, Data2, tick(Data2)};
handle_event(info, {work, _Id, _Seq}, State = waiting, Data = #data{backlog = N}) ->
    log(State, postponed, io_lib:format("work {~w, ~w}", [_Id, _Seq])),
    Data2 = Data#data{backlog = N + 1},
    maybe_report(State, Data2),
    {keep_state, Data2, postpone};
handle_event({call, From}, get_backlog, _State, Data) ->
    {keep_state_and_data, {reply, From, Data#data.backlog}};
handle_event({call, _From}, _EventContent, _State, _Data) ->
    keep_state_and_data;
handle_event(cast, _EventContent, _State, _Data) ->
    keep_state_and_data;
handle_event(info, _EventContent, _State, _Data) ->
    keep_state_and_data.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

dec_backlog(N) when N > 0 -> N - 1;
dec_backlog(N) -> N.

log(_State, _Kind = postponed, _Msg) -> ok;
log(_State, _Kind = consumed, _Msg) -> ok;
log(State, Kind = report, Msg) -> io:format("[consumer] ~w  (~w)  ~s~n", [Kind, State, Msg]);
log(_State, Kind, Msg) -> io:format("[consumer] ~w ~s~n", [Kind, Msg]).

tick(Data) -> {{timeout, tick}, interval(Data), open}.

%% Convert a rate (msg/s) to a millisecond interval.
interval(_Data = #data{rate = Rate, tick_mult = Mult}) ->
    trunc(Mult / Rate).

maybe_report(State, Data) when
    (Data#data.tick_count rem ?REPORT_INTERVAL =:= 0) and (State =:= consume)
->
    log(
        State,
        report,
        io_lib:format("tick=~w  backlog=~w", [Data#data.tick_count, Data#data.backlog])
    );
maybe_report(_, _) ->
    ok.
