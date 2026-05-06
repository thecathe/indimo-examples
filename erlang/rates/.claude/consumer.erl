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
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(NAME,            rate_consumer).
-define(REPORT_INTERVAL, 20).   %% ticks between queue-depth reports

-record(state, {
    rate        :: pos_integer(),   %% msgs/sec we can consume
    processed   :: non_neg_integer(),
    tick_count  :: non_neg_integer()
}).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

start_link(Rate) ->
    gen_server:start_link({local, ?NAME}, ?MODULE, Rate, []).

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------

init(Rate) ->
    schedule_tick(Rate),
    io:format("[consumer] started  rate=~w msg/s~n", [Rate]),
    {ok, #state{rate=Rate, processed=0, tick_count=0}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

%% Consume one work item per tick.
handle_info(tick, State = #state{rate=Rate, processed=P, tick_count=T}) ->
    NewP = case consume_one() of
               consumed -> P + 1;
               empty    -> P
           end,

    NewT = T + 1,
    maybe_report(NewT, Rate),

    schedule_tick(Rate),
    {noreply, State#state{processed=NewP, tick_count=NewT}};

%% Work messages arrive here from producers.
handle_info({work, _ProducerId, _SeqNo} = _Msg, State) ->
    %% Message sits in the mailbox until the next tick drains it.
    %% We do NOT process it here — the tick is the rate-limiter.
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

%% Pull one {work, ...} message from the mailbox without blocking.
consume_one() ->
    receive
        {work, _Id, _Seq} -> consumed
    after 0 ->
        empty
    end.

schedule_tick(Rate) ->
    erlang:send_after(interval(Rate), self(), tick).

%% Convert a rate (msg/s) to a millisecond interval.
interval(Rate) ->
    trunc(1000 / Rate).

maybe_report(TickCount, _Rate) when TickCount rem ?REPORT_INTERVAL =:= 0 ->
    QueueLen = case process_info(self(), message_queue_len) of
                   {message_queue_len, N} -> N;
                   undefined              -> -1
               end,
    io:format("[consumer] tick=~w  queue_depth=~w~n", [TickCount, QueueLen]);
maybe_report(_, _) ->
    ok.
