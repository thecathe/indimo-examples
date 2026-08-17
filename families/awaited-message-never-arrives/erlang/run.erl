-module(run).

%% Entry point for `make run`, following findall/erlang/run.erl.
%%
%%   make run              both tables
%%   make run matrix       the cause x remedy matrix only
%%   make run boundary     the look-alike comparison only
%%   make run a none       one cell, with the waiter left running and inspected
%%   make run defs         what each cause and remedy means

-export([main/1]).

main([])           -> both();
main(['all'])      -> both();
main(['matrix'])   -> amna:matrix(), ok;
main(['boundary']) -> boundary:table(), ok;
main(['defs'])     -> defs();
main([C, R])       -> cell(C, R);
main(Args)         -> invalid_args(Args).

both() ->
    amna:matrix(),
    boundary:table(),
    ok.

defs() ->
    io:format("~n  causes -- three ways to violate the invariant~n"),
    [io:format("    ~-5w ~s~n", [C, amna:describe(C)]) || C <- amna:causes()],
    io:format("~n  remedies -- one per clause of the invariant~n"),
    [io:format("    ~-5w ~s~n", [R, amna:describe(R)]) || R <- amna:remedies()],
    io:format("~n"),
    ok.

%% One cell, printed in full. This is the interactive path: it leaves the waiter
%% and peer alive long enough to show the symptom vector, which is the thing the
%% matrix summarises away.
cell(C, R) ->
    Cause = valid(C, amna:causes(), "cause"),
    Remedy = valid(R, amna:remedies(), "remedy"),
    io:format("~n  cause  ~-5w ~s~n", [Cause, amna:describe(Cause)]),
    io:format("  remedy ~-5w ~s~n~n", [Remedy, amna:describe(Remedy)]),
    S = amna:run(Cause, Remedy),
    #{waiter := W, verdict := V, outcome := O, mailbox := Q} = S,
    io:format("  verdict  ~w~n", [V]),
    io:format("  outcome  ~w~n", [O]),
    io:format("  mailbox  ~w~n", [Q]),
    io:format("  waiter   ~s~n~n", [observe:format(observe:vector(W, 0))]),
    amna:cleanup(S),
    ok.

valid(Given, Allowed, What) ->
    case lists:member(Given, Allowed) of
        true  -> Given;
        false ->
            io:format("Unrecognised ~s: ~w~nExpected one of ~w~n", [What, Given, Allowed]),
            halt(1)
    end.

invalid_args(Args) ->
    io:format("Unrecognised input: ~w~n~n"
              "  make run              both tables~n"
              "  make run matrix       the cause x remedy matrix~n"
              "  make run boundary     the look-alike comparison~n"
              "  make run defs         what each cause and remedy means~n"
              "  make run <cause> <remedy>   one cell, e.g. 'make run b r1'~n"
              "                              cause  :: ~w~n"
              "                              remedy :: ~w~n~n",
              [Args, amna:causes(), amna:remedies()]),
    halt(1).
