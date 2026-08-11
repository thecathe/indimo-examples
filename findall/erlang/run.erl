-module(run).
-export([main/1]).

%% run using: erl -noshell -s run main safe
%% run using: erl -noshell -s run main 3 4 5

atom_to_int(X) -> list_to_integer(atom_to_list(X)).

main([N,M,K]) -> run(atom_to_int(N),atom_to_int(M),atom_to_int(K));
main(['safe']) -> run(5,6,3);
main(['unsafe']) -> run(1,10,12);
main(Args) -> invalid_args(Args).

invalid_args(Args) -> 
  io:format("Unrecognised input: ~w~n"
      "Either use one of the preset atoms 'safe' or 'unsafe', "
      "or input 3 integers for N M K.~n"
      "A \"safe\" input is one where: N + M >= K~n~n", [Args]),
  halt(1).

run(N,M,K) -> sup:start(N,M,K).