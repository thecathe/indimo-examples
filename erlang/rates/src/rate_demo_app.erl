%%%-------------------------------------------------------------------
%%% @doc rate_demo OTP application entry point.
%%%
%%% Configuration is read from the application environment, which can
%%% be set in config/sys.config or overridden at the shell:
%%%
%%%   application:set_env(rate_demo, producer_rate, 5).
%%%   application:set_env(rate_demo, consumer_rate, 8).
%%%   application:set_env(rate_demo, ratio,         2).
%%%   application:start(rate_demo).
%%%
%%% Invariant:
%%%   ratio * producer_rate =< consumer_rate   =>  stable queue
%%%   ratio * producer_rate  > consumer_rate   =>  growing queue
%%%-------------------------------------------------------------------
-module(rate_demo_app).
-behaviour(application).

-export([start/2, stop/1]).

%%--------------------------------------------------------------------
%% Application callbacks
%%--------------------------------------------------------------------

start(_StartType, _StartArgs) ->
    %% msgs / sec per producer
    ProducerRate = require_env(producer_rate),
    %% msgs / sec
    ConsumerRate = require_env(consumer_rate),
    %% producers per consumer
    Ratio = require_env(ratio),

    log_invariant(Ratio, ProducerRate, ConsumerRate),

    rate_demo_sup:start_link(#{
        producer_rate => ProducerRate,
        consumer_rate => ConsumerRate,
        ratio => Ratio
    }).

stop(_State) ->
    ok.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

require_env(Key) ->
    case application:get_env(rate_demo, Key) of
        {ok, Value} -> Value;
        undefined -> error({missing_config, rate_demo, Key, "define it in config/sys.config"})
    end.

log_invariant(Ratio, PR, CR) ->
    Load = Ratio * PR,
    Status =
        if
            Load =< CR -> "STABLE (invariant holds)";
            true -> "OVERLOADED (invariant violated)"
        end,
    io:format(
        "[rate_demo] ratio=~w  producer_rate=~w  consumer_rate=~w~n"
        "            offered_load=~w msg/s  capacity=~w msg/s  => ~s~n",
        [Ratio, PR, CR, Load, CR, Status]
    ).
