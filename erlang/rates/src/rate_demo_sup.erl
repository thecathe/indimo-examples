%%%-------------------------------------------------------------------
%%% @doc Top-level supervisor.
%%%
%%% Starts children in this order (order matters — consumer must
%%% register its name before producers try to resolve it):
%%%
%%%   1. consumer          — registers as `rate_consumer`
%%%   2. queue_monitor     — samples consumer mailbox depth
%%%   3. producer_1..N     — each holds a ref to `rate_consumer`
%%%
%%% Strategy: rest_for_one.
%%% Rationale: if the consumer crashes, producers should also restart
%%% so they re-resolve the newly registered consumer name. The monitor
%%% follows the consumer for the same reason.
%%%-------------------------------------------------------------------
-module(rate_demo_sup).
-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).

-define(SERVER, ?MODULE).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

start_link(Params) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, Params).

%%--------------------------------------------------------------------
%% Supervisor callback
%%--------------------------------------------------------------------

init(#{producer_rate := PR, consumer_rate := CR, ratio := Ratio, tick := Tick, samples := Samples}) ->
    SupFlags = #{
        strategy => rest_for_one,
        intensity => 5,
        period => 10
    },

    ConsumerSpec = #{
        id => consumer,
        start => {consumer, start_link, [CR, Tick]},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [consumer]
    },

    MonitorSpec = #{
        id => queue_monitor,
        start => {queue_monitor, start_link, [Tick, Samples]},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [queue_monitor]
    },

    ProducerSpecs = [producer_spec(I, PR, Tick) || I <- lists:seq(1, Ratio)],

    {ok, {SupFlags, [ConsumerSpec, MonitorSpec | ProducerSpecs]}}.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

producer_spec(Index, Rate, Tick) ->
    Id = list_to_atom("producer_" ++ integer_to_list(Index)),
    #{
        id => Id,
        start => {producer, start_link, [Id, Rate, Tick]},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [producer]
    }.
