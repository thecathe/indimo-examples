%%%-------------------------------------------------------------------
%%% @doc Producer worker.
%%%
%%% Sends one `{work, Id, SeqNo}` message to `rate_consumer` per tick.
%%% The tick interval is derived from the configured Rate so that the
%%% long-run throughput is exactly `Rate` messages per second (modulo
%%% scheduler jitter).
%%%
%%% Producers resolve the consumer by registered name on every send,
%%% which means they automatically route to a restarted consumer
%%% without any coordinator involvement.
%%%-------------------------------------------------------------------
-module(producer).
-behaviour(gen_server).

-export([start_link/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    id   :: atom(),
    rate :: pos_integer(),
    seq  :: non_neg_integer()
}).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

start_link(Id, Rate) ->
    gen_server:start_link({local, Id}, ?MODULE, {Id, Rate}, []).

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------

init({Id, Rate}) ->
    schedule_tick(Rate),
    io:format("[producer] ~w started  rate=~w msg/s~n", [Id, Rate]),
    {ok, #state{id=Id, rate=Rate, seq=0}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(tick, State = #state{id=Id, rate=Rate, seq=Seq}) ->
    send_work(Id, Seq),
    schedule_tick(Rate),
    {noreply, State#state{seq=Seq + 1}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

send_work(Id, Seq) ->
    %% Resolve by name on every send: transparent to consumer restarts.
    case whereis(rate_consumer) of
        undefined ->
            %% Consumer not yet up (race at startup) or temporarily down.
            %% Drop the message; the supervisor will restart us if needed.
            io:format("[producer] ~w  consumer not found, dropping seq=~w~n",
                      [Id, Seq]);
        Pid ->
            Pid ! {work, Id, Seq}
    end.

schedule_tick(Rate) ->
    erlang:send_after(interval(Rate), self(), tick).

interval(Rate) ->
    trunc(1000 / Rate).
