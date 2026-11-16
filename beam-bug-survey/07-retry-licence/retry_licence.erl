%% What licenses a retry: knowing the request had no effect, or assuming it is harmless.
%%
%% Shape of firezone/firezone#13802: a cold connection pool fails the first requests with
%% `pool_not_available`. The default retry rule retries only GET and HEAD, so POSTs failed
%% for good. The fix did two different things: it retried everything transient ("these are
%% safe to retry", an assumption about the operations), and it added a rule for the two
%% reasons that mean the request was never processed (knowledge about this failure).
-module(retry_licence).
-export([default_rule/2, assumption_rule/2, knowledge_rule/2, demo/0]).

%% BUGGY for POST: the rule looks only at the method.
default_rule(Method, _Reason) -> lists:member(Method, ['GET', 'HEAD']).

%% Fix 1, an ASSUMPTION: every operation here is idempotent, so retrying is harmless.
%% True of these sync calls; says nothing about the next POST someone adds.
assumption_rule(_Method, Reason) -> transient(Reason).

%% Fix 2, KNOWLEDGE: these reasons mean the server never processed the request, so
%% retrying cannot repeat an effect, whatever the method. The error carries the fact.
knowledge_rule(Method, Reason) ->
    never_sent(Reason) orelse (default_rule(Method, Reason) andalso transient(Reason)).

never_sent(R) -> lists:member(R, [pool_not_available, unprocessed]).
transient(R)  -> never_sent(R) orelse lists:member(R, [timeout, closed]).

demo() ->
    Cases = [{'POST', pool_not_available},    % never left: safe to retry
             {'POST', timeout},               % may have executed: the dangerous one
             {'GET',  timeout}],
    [#{request => C,
       default => default_rule(M, R), assumes_idempotent => assumption_rule(M, R),
       knows_not_sent => knowledge_rule(M, R)} || C = {M, R} <- Cases].
