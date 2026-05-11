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

-export([start_link/2]).
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

% -define(SAMPLE_INTERVAL_MS, 1000).
%% samples kept for slope estimate
% -define(WINDOW_SIZE, 5).

-record(state, {
    samples :: queue:queue(non_neg_integer()),
    tick_rate :: pos_integer(),
    num_samples :: non_neg_integer()
}).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

start_link(Tick, Samples) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, {Tick, Samples}, []).

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------

init({Tick, Samples}) ->
    State = #state{samples = queue:new(), tick_rate = Tick, num_samples = Samples},
    schedule_sample(State),
    {ok, State}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(sample, State) ->
    Win = handle_new_sample(consumer_length(), State),
    schedule_sample(State),
    {noreply, State#state{samples = Win}};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

handle_new_sample(N, State) ->
    Win = update_sample(N, State),
    report(N, slope(Win)),
    Win.

%% sanity check for getting num of un-consumed messages
consumer_length() ->
    A = consumer_backlog(),
    B = consumer_postponed(),
    case (A == B) of
        true ->
            A;
        false ->
            io:format("[monitor] warning, backlog: ~w   postponed: ~w~n", [A, B]),
            A
    end.

%% method A: using consumer self-report backlog
consumer_backlog() -> gen_statem:call(rate_consumer, get_backlog).

%% method B: query status of consumer postponed events
consumer_postponed() ->
    {status, _, {module, gen_statem}, [_, _, _, _, Misc]} = sys:get_status(rate_consumer),
    Data = proplists:get_value(data, Misc, []),
    Postponed = proplists:get_value("Postponed", Data, []),
    length(Postponed).

update_sample(Backlog, _State = #state{samples = Win, num_samples=Num}) ->
    slide(Win, Backlog, Num).

%% Add a new sample, dropping the oldest when the window is full.
slide(Q, Sample, MaxSize) ->
    Q1 = queue:in(Sample, Q),
    case queue:len(Q1) > MaxSize of
        true ->
            {_, Q2} = queue:out(Q1),
            Q2;
        false ->
            Q1
    end.

%% Linear slope over the window: (last - first) / (n - 1).
%% Returns undefined if fewer than 2 samples.
slope(Q) ->
    case queue:len(Q) < 2 of
        true ->
            undefined;
        false ->
            First = queue:get(Q),
            Last = queue:get_r(Q),
            N = queue:len(Q),
            (Last - First) / (N - 1)
    end.

report(Backlog, undefined) ->
    io:format("[monitor]  backlog=~w  trend=collecting...~n", [Backlog]);
report(Backlog, Slope) ->
    Trend =
        if
            (Slope > 0.5) and (Backlog > 1) -> "GROWING  (invariant VIOLATED)";
            Slope > 0.5 -> "growing  (invariant may violate...)";
            Slope < -0.5 -> "shrinking";
            true -> "stable   (invariant holds)"
        end,
    io:format(
        "[monitor]  backlog=~4w  slope=~6.2f msg/sample  ~s~n",
        [Backlog, Slope, Trend]
    ).

schedule_sample(_State = #state{tick_rate = R}) ->
    erlang:send_after(R , self(), sample).
