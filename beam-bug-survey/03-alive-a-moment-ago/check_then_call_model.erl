%% The context of card 03, made explicit, and the epistemic question asked of it mechanically.
%%
%% alive_a_moment_ago.erl shows the code. Here the surrounding context is a small model with three
%% roles, and every ordering of their steps is explored:
%%
%%   c  the caller      liveness_check: check, send, await     monitor: monitor, send, await
%%   s  the server      handles a request if it is alive and one is waiting
%%   e  the environment kills the server, once, at any point (a crash, a supervisor, a peer)
%%
%% A WORLD is a reachable state together with how it was reached. The caller's VIEW is the list of
%% things it has itself done or received (perfect recall, as in the epistemic-plausibility model).
%% Two worlds are indistinguishable to the caller when their views are equal. The caller KNOWS a
%% fact at a world when the fact holds in every reachable world with the same view.
%%
%% This is hand-written from the card, not extracted from the Erlang code.
-module(check_then_call_model).
-export([demo/0, report/1, explore/1, init/1, by_position/1, conformance/0]).

init(Variant) ->
    #{prog => program(Variant), alive => true, killed => false, s_in => [], c_in => [],
      mon => false, view => [], out => running, trace => []}.

program(liveness_check) -> [check, send, await];
program(monitor)        -> [monitor, send, await].

%% Which roles can take a step now. `await` blocks until the caller's inbox is non-empty.
enabled(#{prog := Prog, out := Out, c_in := CIn, alive := Alive, s_in := SIn, killed := Killed}) ->
    C = case {Out, Prog} of
            {running, [await | _]} when CIn =/= [] -> [c];
            {running, [await | _]} -> [];
            {running, [_ | _]}     -> [c];
            _                      -> []
        end,
    S = [s || Alive, SIn =/= []],
    E = [e || not Killed],
    C ++ S ++ E.

step(c, #{prog := [Step | Rest]} = St) -> do(Step, St#{prog := Rest});
step(s, #{c_in := CIn} = St) -> St#{s_in := [], c_in := CIn ++ [reply]};
step(e, #{c_in := CIn, mon := Mon} = St) ->
    St1 = St#{alive := false, killed := true, s_in := []},
    case Mon of
        true  -> St1#{c_in := CIn ++ [{down, killed}]};     % the monitor turns the death into a message
        false -> St1                                         % nobody is told
    end.

do(check, #{alive := A} = St) ->
    Seen = case A of true -> alive; false -> dead end,
    St1 = see(St, {check, Seen}),
    case Seen of dead -> St1#{out := {error, noproc}, prog := []}; alive -> St1 end;
do(monitor, #{alive := A, c_in := CIn} = St) ->
    St1 = (see(St, monitor))#{mon := true},
    case A of true -> St1; false -> St1#{c_in := CIn ++ [{down, noproc}]} end;
do(send, #{alive := A} = St) ->
    St1 = see(St, sent),
    case A of true -> St1#{s_in := [req]}; false -> St1 end;      % a send to a dead server is dropped
do(await, #{c_in := [M | Rest]} = St) ->
    St1 = (see(St, {got, M}))#{c_in := Rest},
    case M of reply -> St1#{out := ok}; {down, R} -> St1#{out := {error, R}} end.

see(#{view := V} = St, Obs) -> St#{view := [Obs | V]}.

%% Every reachable world, including the incomplete ones (the prefixes).
explore(St) -> [St | lists:append([explore(next(Ev, St)) || Ev <- enabled(St)])].
next(Ev, #{trace := T} = St) -> (step(Ev, St))#{trace := [Ev | T]}.

view(#{view := V}) -> lists:reverse(V).
alive(#{alive := A}) -> A.

knows_dead(Worlds, W) ->
    [] =/= same_view(Worlds, W) andalso lists:all(fun(X) -> not alive(X) end, same_view(Worlds, W)).
same_view(Worlds, W) -> [X || X <- Worlds, view(X) =:= view(W)].

report(Variant) ->
    Worlds = explore(init(Variant)),
    Final = [W || W <- Worlds, enabled(W) =:= []],
    Hangs = [W || W = #{out := running} <- Final],
    #{variant => Variant,
      complete_runs => length(Final),
      outcomes => lists:sort([maps:get(out, W) || W <- Final]),
      hangs => length(Hangs),
      %% a hang whose view also occurs in a world where the server is alive: the caller could not
      %% tell "the reply is coming" from "the reply never will"
      hangs_the_caller_could_not_tell_from_a_live_server =>
          length([H || H <- Hangs, lists:any(fun(X) -> alive(X) end, same_view(Worlds, H))]),
      views_where_the_caller_knows_the_server_is_dead =>
          lists:usort([view(W) || W <- Worlds, view(W) =/= [], knows_dead(Worlds, W)])}.

%% Where the kill falls in a run, named as run/2 in alive_a_moment_ago.erl names it:
%% before_first_step, after_first_step, after_send (server dies before handling),
%% after_reply (server handled, then died), after_done (died after the caller finished).
kill_position(Trace) ->                                  % Trace is in chronological order
    {Before, [e | After]} = lists:splitwith(fun(Ev) -> Ev =/= e end, Trace),
    CSteps = length([c || c <- Before]),
    Handled = lists:member(s, Before),
    _ = After,
    case {CSteps, Handled} of
        {0, _}     -> before_first_step;
        {1, _}     -> after_first_step;
        {2, false} -> after_send;
        {2, true}  -> after_reply;
        {_, _}     -> after_done
    end.

%% The model's prediction per kill position: [{Position, Outcome}], one per position.
by_position(Variant) ->
    Final = [W || W <- explore(init(Variant)), enabled(W) =:= []],
    Pairs = lists:usort([{kill_position(lists:reverse(maps:get(trace, W))), outcome(W)} || W <- Final]),
    Pairs.

outcome(#{out := running}) -> hang;
outcome(#{out := Out}) -> Out.

%% The model against the real code: for each variant and kill position, what the model
%% predicts and what alive_a_moment_ago:run/2 returned, with the code's result translated.
conformance() ->
    [#{variant => V, kill_at => P, model => M, code => translate(alive_a_moment_ago:run(V, P)),
       agree => M =:= translate(alive_a_moment_ago:run(V, P))}
     || V <- [liveness_check, monitor], {P, M} <- by_position(V)].

translate({ok, hello})         -> ok;
translate(hung_until_timeout)  -> hang;
translate({error, R})          -> {error, R}.

demo() ->
    #{liveness_check => report(liveness_check), monitor => report(monitor),
      model_against_code => conformance()}.
