%% "Not yet" read as an answer.
%%
%% Shapes of basho/riak_core#764 (a ring join accepted while the node is still starting) and
%% emqx/emqx#7728 (a joining node copies configuration from a peer that has not finished
%% booting, and treats the peer's transient "not ready" as a hard failure).
-module(not_yet_is_not_never).
-export([join_buggy/1, join_gated/1, copy_buggy/2, copy_knowing/2, copy_retrying/3, demo/0]).

%% --- admission (riak_core) -------------------------------------------------------------
%% BUGGY: admit regardless of what the node itself could say about its readiness.
join_buggy(_InitStatus) -> ok.
%% FIXED: the node can read its own readiness (init:get_status/0); gate on it.
join_gated(started) -> ok;
join_gated(_)       -> {error, node_still_starting}.

%% --- copying from a peer (emqx#7728) ---------------------------------------------------
%% A peer answers {ok, Conf}, {error, not_ready} (still booting) or {error, down}.
%% BUGGY: the first peer's answer is final, and not_ready crashes the caller.
copy_buggy([Peer | _], Ask) ->
    case Ask(Peer) of
        {ok, Conf} -> {ok, Conf};
        {error, R} -> error({copy_failed, R})
    end.

%% FIXED (the emqx fix): only ask peers known to be running (information from a membership view).
copy_knowing(Peers, Ask) ->
    case [P || {P, running} <- Peers] of
        []        -> {error, no_running_peer};
        [P | _]   -> Ask(P)
    end.

%% ALTERNATIVE (robust, no extra information): not_ready is retryable, down is not.
copy_retrying(Peer, Ask, Tries) ->
    case Ask(Peer) of
        {error, not_ready} when Tries > 0 -> timer:sleep(10), copy_retrying(Peer, Ask, Tries - 1);
        Other -> Other
    end.

demo() ->
    %% booting is not ready for 3 asks, then ready
    Counter = counters:new(1, []),
    Ask = fun(booting) ->
                  counters:add(Counter, 1, 1),
                  case counters:get(Counter, 1) of N when N =< 3 -> {error, not_ready}; _ -> {ok, conf} end;
             (ready) -> {ok, conf}
          end,
    #{join_buggy_while_starting => join_buggy(starting),
      join_gated_while_starting => join_gated(starting),
      join_gated_when_started   => join_gated(started),
      copy_buggy_first_peer_booting   => try copy_buggy([booting, ready], Ask)
                                       catch error:{copy_failed, R} -> {crashed, R} end,
      copy_knowing_skips_booting      => copy_knowing([{booting, booting}, {ready, running}], Ask),
      copy_retrying_the_booting_peer  => copy_retrying(booting, Ask, 5)}.
