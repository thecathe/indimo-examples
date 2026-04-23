-module(run).
-export([main/1]).

%% run using: erl -noshell -s run main safe
%% run using: erl -noshell -s run main 3 4 5

run(_N,_M,0) -> init:stop();
run(N,M,K) -> run2(N,M,K-1).

run2(N,M,K) -> io:format("(~p, ~p, ~p)~n", [N,M,K]), run(N,M,K).

safestr(true) -> "safe";
safestr(false) -> "unsafe".

atom_to_int(X) -> list_to_integer(atom_to_list(X)).

main([_N,_M,_K]) -> 
    {N,M,K} = {atom_to_int(_N),atom_to_int(_M),atom_to_int(_K)},
    io:format("(~p + ~p >= ~p) looks ~s~n", 
              [N, M, K, safestr ((N + M) >= K)]),
  run2(N,M,K);
main(['safe']) -> io:format("using preset: safe.~n"), run2(5,6,3);
main(['unsafe']) -> io:format("using preset: unsafe.~n"), run2(1,10,12);
main(_Args) ->
  io:format("Unrecognised input: ~w~n"
      "Either use one of the preset atoms 'safe' or 'unsafe',~n"
      "or input 3 integers for N M K.~n"
      "A \"safe\" input is one where: N + M >= K~n", [_Args]),
  exit(1).