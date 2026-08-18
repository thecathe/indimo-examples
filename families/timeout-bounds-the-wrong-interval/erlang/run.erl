-module(run).

%% Entry point for `make run`, following findall/erlang/run.erl and family 8's.
%%
%%   make run              every table
%%   make run ledger       the five scenarios, with both intervals
%%   make run cross        direction x remedy
%%   make run otp          gen_server's own timeout, on this runtime
%%   make run boundary     the look-alikes
%%   make run sweep        the observation window, swept
%%   make run defs         what each scenario is
%%   make run rearmed      one scenario in full

-export([main/1]).

main([])           -> all();
main(['all'])      -> all();
main(['ledger'])   -> tbwi:ledger(), ok;
main(['cross'])    -> tbwi:cross(), ok;
main(['otp'])      -> otp_timeout:table(), ok;
main(['boundary']) -> boundary:table(), ok;
main(['sweep'])    -> boundary:sweep(), ok;
main(['defs'])     -> defs();
main([One])        -> one(One);
main(Args)         -> invalid_args(Args).

all() ->
    tbwi:ledger(),
    tbwi:cross(),
    otp_timeout:table(),
    boundary:table(),
    boundary:sweep(),
    ok.

defs() ->
    io:format("~n  scenarios~n~n"),
    [io:format("    ~-16w ~s~n"
               "    ~-16s means to bound  ~s~n"
               "    ~-16s actually bounds ~s~n~n",
               [N, tbwi:describe(N),
                "", tbwi:intended(N),
                "", tbwi:measured(N)])
     || N <- tbwi:scenarios()],
    ok.

%% One scenario, printed in full. The interactive path: it names both intervals
%% before running, because the whole family is the difference between them and
%% only one of the two will show up in the output.
one(Name) ->
    Scenario = valid(Name, tbwi:scenarios(), "scenario"),
    io:format("~n  ~w~n  ~s~n~n", [Scenario, tbwi:describe(Scenario)]),
    io:format("  means to bound   ~s~n", [tbwi:intended(Scenario)]),
    io:format("  actually bounds  ~s~n~n", [tbwi:measured(Scenario)]),
    S = tbwi:run(Scenario),
    #{outcome := O, elapsed := E, pulses := P, gaps := G} = S,
    io:format("  outcome          ~w after ~wms~n", [O, E]),
    case P of
        [] -> ok;
        _  -> io:format("  woke at          ~w~n", [P]),
              io:format("  gaps             ~w  <- the measured interval~n", [G])
    end,
    io:format("~n"),
    tbwi:cleanup(S),
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
              "  make run              every table~n"
              "  make run ledger       the five scenarios, with both intervals~n"
              "  make run cross        direction x remedy~n"
              "  make run otp          gen_server's own timeout, on this runtime~n"
              "  make run boundary     the look-alikes~n"
              "  make run sweep        the observation window, swept~n"
              "  make run defs         what each scenario is~n"
              "  make run <scenario>   one scenario, e.g. 'make run suspended_abs'~n"
              "                        scenario :: ~w~n~n",
              [Args, tbwi:scenarios()]),
    halt(1).
