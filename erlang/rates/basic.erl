-module(basic).
-export([start/0, start/1]).

-record(monitor_state, {
    samples :: queue:queue(non_neg_integer()),
    sample_rate :: pos_integer(),
    num_samples :: non_neg_integer(),
    slope :: float()
}).

start() -> start([1]).

start([N]) when N =:= '0' -> halt(no_producers_to_spawn);
start([N]) ->
    % spawn consumer
    C = spawn(fun consumer/0),
    io:format("[main] spawned consumer: ~w~n", [C]),
    % spawn N producers
    io:format("[main] spawning ~w producers...~n", [atom_to_int(N)]),
    spawn_producers(C, atom_to_int(N)),
    % continue as monitor
    monitor_(C, new_monitor_state()).

%% Consumer
consumer() ->
    receive
        msg -> consumer()
    end.

%% Producer
producer(C) ->
    C ! msg,
    producer(C).

%% Spawn Producers
spawn_producers(_, N) when N =< 0 -> ok;
spawn_producers(C, N) ->
    spawn(fun() -> producer(C) end),
    spawn_producers(C, N - 1).

%%--------------------------------------------------------------------
%% Lightweight Monitor
%%--------------------------------------------------------------------

monitor_(C, State = #monitor_state{sample_rate = R}) ->
    % check backlog -> update and report samples
    Win = handle_new_sample(consumer_backlog(C), State),
    % set reminder for next sample
    erlang:send_after(R, self(), sample),
    % wait until next sample should be performed
    receive
        sample -> monitor_(C, State#monitor_state{samples = Win})
    end.

new_monitor_state() ->
    #monitor_state{samples = queue:new(), sample_rate = 1000, num_samples = 5, slope = 0.5}.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

atom_to_int(X) -> list_to_integer(atom_to_list(X)).

consumer_backlog(C) ->
    case process_info(C, message_queue_len) of
        {message_queue_len, N} -> N;
        undefined -> 0
    end.

handle_new_sample(N, State) ->
    Win = update_sample(N, State),
    report(N, slope(Win), State),
    Win.

report(Backlog, undefined, _State) ->
    io:format("[monitor]  backlog=~w  trend=collecting...~n", [Backlog]);
report(Backlog, Slope, _State = #monitor_state{slope = S}) ->
    Trend =
        if
            (Slope > S) and (Backlog > 1) -> "GROWING  (invariant VIOLATED)";
            Slope > S -> "growing  (invariant may violate...)";
            Slope < -0.5 -> "shrinking";
            true -> "stable   (invariant holds)"
        end,
    io:format(
        "[monitor]  backlog=~4w  slope=~6.2f msg/sample  ~s~n",
        [Backlog, Slope, Trend]
    ).

update_sample(Backlog, #monitor_state{samples = Win, num_samples = Num}) ->
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
