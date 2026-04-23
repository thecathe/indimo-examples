-module(sup).
-behaviour(supervisor).
-export([start_link/0,init/1]).

start_link() -> supervisor:start_link(sup, []).

% -type PArgs = 

% -spec begin(n::pos_integer(),m::pos_integer(),k::pos_integer()) -> ().
% begin() -> 
%   SupFlags = #{strategy => one_for_one, intensity =>1, period => 5},
%   ChildSpecs = [#{id => findp,
%                     start => {findp, start_link, []},
%                     restart => permanent,
%                     shutdown => brutal_kill,
%                     type => worker,
%                     modules => [findp]}],
%     {ok, {SupFlags, ChildSpecs}}.



% init(["safe"]) -> ok.
% init(["unsafe"]) ->
% init([n,m,k]) ->
% init(_Args) ->
%   io:format("Unknown Args: ~s~n", _Args),
%   ko.