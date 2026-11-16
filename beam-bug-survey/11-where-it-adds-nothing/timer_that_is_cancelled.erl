%% A bug about what a timer means, not about what anyone knows.
%%
%% Shape of a couchdb replicator change ("use an explicit message for delayed init"): the
%% start delay was a gen_server timeout, and any message that arrives first cancels it, so the
%% delayed initialisation never ran. No agent was missing information; a language construct
%% does not mean what the code assumed. The epistemic layer has nothing to say here.
-module(timer_that_is_cancelled).
-behaviour(gen_server).
-export([run/1, demo/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

init(buggy) -> {ok, #{fired => false}, 100};                  % "do the delayed init after 100 ms of quiet"
init(fixed) -> erlang:send_after(100, self(), delayed_init), {ok, #{fired => false}}.

handle_call(fired, _From, S) -> {reply, maps:get(fired, S), S}.
handle_cast(_, S) -> {noreply, S}.
handle_info(timeout, S)      -> {noreply, S#{fired => true}};
handle_info(delayed_init, S) -> {noreply, S#{fired => true}};
handle_info(tick, S)         -> {noreply, S}.               % ANY message cancels the pending timeout

run(Kind) ->
    {ok, P} = gen_server:start_link(?MODULE, Kind, []),
    timer:sleep(50), P ! tick,                               % unrelated traffic at 50 ms
    timer:sleep(300),
    R = gen_server:call(P, fired),
    gen_server:stop(P),
    R.

demo() -> #{buggy_delayed_init_ran => run(buggy), fixed_delayed_init_ran => run(fixed)}.
