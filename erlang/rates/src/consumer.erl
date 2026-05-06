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

-define(NAME,            rate_consumer).
-define(REPORT_INTERVAL, 5).   %% ticks between queue-depth reports

-record(data, {
    rate        :: pos_integer(),   %% msgs/sec we can consume
    processed   :: non_neg_integer(),
    tick_count  :: non_neg_integer()
  %% TODO: add backlog counter so that we can stop using process_info, which conflicts with postpone
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
  olog(init, io_lib:format("started  rate=~w msg/s", [Rate])),
    {ok, waiting, #data{rate=Rate, processed=0, tick_count=0}, {{timeout, tick}, interval(Rate), open}}.

handle_event({call, _From}, _EventContent, _State, _Data) ->
  olog(_State, io_lib:format("ignoring call From ~w: ~w", [_From, _EventContent])),
  keep_state_and_data;

handle_event(cast, _EventContent, _State, _Data) ->
  olog(_State, io_lib:format("ignoring cast: ~w", [_EventContent])),
  keep_state_and_data;

%% Consume one work item per tick.
handle_event({timeout, tick}, open, _State = waiting, Data) ->
  olog(_State, "open"),
  {next_state, consume, Data, {state_timeout, 1, closed}};

handle_event(state_timeout, closed, _State = consume, Data = #data{rate=Rate, tick_count=T}) ->
  olog(_State, "closed"),
  NewT = T + 1,
  maybe_report(NewT, Rate, _State),
  {next_state, waiting, Data#data{tick_count=NewT}, {{timeout, tick}, interval(Rate), open}};

handle_event(info, {work, _Id, _Seq}, _State = consume, Data = #data{rate=Rate, processed=P, tick_count=T}) ->
  olog(_State,io_lib:format("consumed work {~w, ~w}", [_Id, _Seq])),
    NewP =  P + 1,
    NewT = T + 1,
    maybe_report(NewT, Rate, _State),
    {next_state, waiting, Data#data{processed=NewP, tick_count=NewT}, {{timeout, tick}, interval(Rate), open}};

handle_event(info, {work, _Id, _Seq}, _State = waiting, _Data) ->
  % olog(_State, io_lib:format("postponed work {~w, ~w}", [_Id, _Seq])),
  {keep_state_and_data, postpone};

handle_event(info, _EventContent, _State, _Data) ->
  olog(_State,io_lib:format("ignoring info: ~w", [_EventContent])),
  % {keep_state_and_data, postpone}.
  keep_state_and_data.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

olog(State, Msg) ->
    io:format("[consumer] [~w] ~s | ~w ~w~n", [State, Msg, process_info(self(), message_queue_len), process_info(self(), messages)]).

%% Convert a rate (msg/s) to a millisecond interval.
interval(Rate) ->
    trunc(1000 / Rate).

maybe_report(TickCount, _Rate, _State) when TickCount rem ?REPORT_INTERVAL =:= 0 ->
    QueueLen = case process_info(self(), message_queue_len) of
                   {message_queue_len, N} -> N;
                   undefined              -> -1
               end,
    olog(_State, io_lib:format("tick=~w  queue_depth=~w", [TickCount, QueueLen]));
maybe_report(_, _, _) ->
    ok.
