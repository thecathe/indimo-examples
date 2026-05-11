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

-export([start_link/1]).
-export([init/1, handle_event/4, terminate/2, code_change/3, callback_mode/0]).

-define(NAME, rate_consumer).
-define(REPORT_INTERVAL, 20).   %% ticks between queue-depth reports
-define(CONSUME_PERIOD, 1).

-record(data, {
    rate        :: pos_integer(),   %% msgs/sec we can consume
    processed   :: non_neg_integer(),
    tick_count  :: non_neg_integer(),
    backlog     :: non_neg_integer()
}).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

start_link(Rate) ->
    gen_statem:start_link({local, ?NAME}, ?MODULE, Rate, []).

%%--------------------------------------------------------------------
%% gen_statem callbacks
%%--------------------------------------------------------------------

callback_mode() -> handle_event_function.

init(Rate) ->
  log(init, io_lib:format("started  rate=~w msg/s", [Rate])),
    {ok, waiting, #data{rate=Rate, processed=0, tick_count=0, backlog=0}, {{timeout, tick}, interval(Rate), open}}.

handle_event({call, From}, get_backlog, _State, _Data = #data{backlog=N}) ->
  % log(_State, io_lib:format("replying call From ~w for backlog", [From])),
  {keep_state_and_data, {reply, From, N}};

handle_event({call, _From}, _EventContent, _State, _Data) ->
  log(_State, io_lib:format("ignoring call From ~w: ~w", [_From, _EventContent])),
  keep_state_and_data;

handle_event(cast, _EventContent, _State, _Data) ->
  log(_State, io_lib:format("ignoring cast: ~w", [_EventContent])),
  keep_state_and_data;

%% Consume one work item per tick.
handle_event({timeout, tick}, open, _State = waiting, Data) ->
  % log(_State, "open"),
  {next_state, consume, Data, {state_timeout, ?CONSUME_PERIOD, closed}};

handle_event(state_timeout, closed, _State = consume, Data = #data{rate=Rate, tick_count=T, backlog=N}) ->
  % log(_State, "closed"),
  NewT = T + 1,
  maybe_report(NewT, Rate, _State, N),
  {next_state, waiting, Data#data{tick_count=NewT}, {{timeout, tick}, interval(Rate), open}};

handle_event(info, {work, _Id, _Seq}, _State = consume, Data = #data{rate=Rate, processed=P, tick_count=T, backlog=N}) ->
  log(_State,io_lib:format("consumed work {~w, ~w}", [_Id, _Seq])),
  % log(_State,io_lib:format("backlog vs mailbox {~w, ~w}", [N, sys:get_status(self())])),
    NewP =  P + 1,
    NewT = T + 1,
    NewN = dec_backlog(N), %% still report what would be the backlog if the state change wouldn't occur
    maybe_report(NewT, Rate, _State, NewN),
    {next_state, waiting, Data#data{processed=NewP, tick_count=NewT, backlog=0}, {{timeout, tick}, interval(Rate), open}};

handle_event(info, {work, _Id, _Seq}, _State = waiting, Data = #data{rate=Rate, tick_count=T, backlog=N}) ->
  % log(_State, io_lib:format("postpone work {~w, ~w}", [_Id, _Seq])),
  NewN = N + 1,
  maybe_report(T, Rate, _State, NewN),
  {keep_state, Data#data{backlog=NewN}, postpone};

handle_event(info, _EventContent, _State, _Data) ->
  % log(_State,io_lib:format("ignoring info: ~w", [_EventContent])),
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

log(State, Msg) ->
    io:format("[consumer #~w] ~s~n", [State, Msg]).

%% Convert a rate (msg/s) to a millisecond interval.
interval(Rate) ->
    trunc(1000 / Rate).

maybe_report(TickCount, _Rate, _State, Backlog) when TickCount rem ?REPORT_INTERVAL =:= 0 ->
    log(_State, io_lib:format("tick=~w  backlog=~w", [TickCount, Backlog]));
maybe_report(_, _, _, _) ->
    ok.
