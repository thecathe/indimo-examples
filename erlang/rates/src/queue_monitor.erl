%%%-------------------------------------------------------------------
%%% @doc Queue depth monitor.
%%%
%%% Periodically samples the consumer's mailbox length and emits a
%%% one-line trend summary. This is the primary observable for the
%%% rate invariant:
%%%
%%%   ratio * producer_rate =< consumer_rate  =>  depth stays near 0
%%%   ratio * producer_rate  > consumer_rate  =>  depth grows linearly
%%%
%%% The trend is estimated by keeping a small sliding window of
%%% samples and computing (last - first) / window_size as a simple
%%% msgs-per-sample slope. A positive slope confirms invariant
%%% violation; ~0 confirms stability.
%%%-------------------------------------------------------------------
-module(queue_monitor).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SAMPLE_INTERVAL_MS, 1000).
-define(WINDOW_SIZE,         5).     %% samples kept for slope estimate

-record(state, {
    samples :: queue:queue(non_neg_integer())
}).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------

init([]) ->
    schedule_sample(),
    {ok, #state{samples=queue:new()}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(sample, State = #state{samples=Win}) ->
    Depth = consumer_queue_depth(),
    Win1  = slide(Win, Depth, ?WINDOW_SIZE),

    report(Depth, slope(Win1)),

    schedule_sample(),
    {noreply, State#state{samples=Win1}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

consumer_queue_depth() ->
    case whereis(rate_consumer) of
        undefined -> 0;
        Pid ->
            case process_info(Pid, message_queue_len) of
                {message_queue_len, N} -> N;
                undefined              -> 0
            end
    end.

%% Add a new sample, dropping the oldest when the window is full.
slide(Q, Sample, MaxSize) ->
    Q1 = queue:in(Sample, Q),
    case queue:len(Q1) > MaxSize of
        true  -> {_, Q2} = queue:out(Q1), Q2;
        false -> Q1
    end.

%% Linear slope over the window: (last - first) / (n - 1).
%% Returns undefined if fewer than 2 samples.
slope(Q) ->
    case queue:len(Q) < 2 of
        true  -> undefined;
        false ->
            First = queue:get(Q),
            Last  = queue:get_r(Q),
            N     = queue:len(Q),
            (Last - First) / (N - 1)
    end.

report(Depth, undefined) ->
    io:format("[monitor]  queue_depth=~w  trend=collecting...~n", [Depth]);
report(Depth, Slope) ->
    Trend = if
                Slope >  0.5 -> "GROWING  (invariant VIOLATED)";
                Slope < -0.5 -> "shrinking";
                true         -> "stable   (invariant holds)"
            end,
    io:format("[monitor]  queue_depth=~4w  slope=~6.2f msg/sample  ~s~n",
              [Depth, Slope, Trend]).

schedule_sample() ->
    erlang:send_after(?SAMPLE_INTERVAL_MS, self(), sample).
