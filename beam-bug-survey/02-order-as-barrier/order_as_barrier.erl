%% A later reply proves an earlier message was handled, if the channel is FIFO.
%%
%% Shape of esl/MongooseIM#4072: a test assumed a message sent from another node was handled
%% by now ("sending a message from one node to the other is instant"). The fix asks each
%% member node to call the local server on the test's behalf: messages from one node to
%% another arrive in the order they were sent, so the reply can only come after the earlier
%% message was handled. Modelled with plain processes: b is the other node, s the local server.
-module(order_as_barrier).
-export([demo/0]).

%% s: counts the `check_for_updates` messages it has handled; `ping` returns the count.
server() -> server(0).
server(N) ->
    receive
        check_for_updates -> server(N + 1);
        {ping, From}      -> From ! {pong, N}, server(N)
    end.

%% b: the other node. It sends its notice to s after a delay (slow link or busy node),
%% and answers `ping_via` by calling s itself, strictly after that.
other_node(S) ->
    receive
        notify_later ->
            timer:sleep(40),
            S ! check_for_updates,
            other_node(S);
        {ping_via, Caller} ->
            S ! {ping, self()},
            receive {pong, N} -> Caller ! {via_pong, N} end,
            other_node(S)
    end.

demo() ->
    S = spawn(fun server/0),
    B = spawn(fun() -> other_node(S) end),
    B ! notify_later,               % b has something to tell s
    B ! {ping_via, self()},         % queued behind notify_later in b's own mailbox
    S ! {ping, self()},             % BUGGY barrier: ask s directly
    Direct = receive {pong, N1} -> N1 after 1000 -> timeout end,
    Via = receive {via_pong, N2} -> N2 after 1000 -> timeout end,
    #{direct_ping_says_handled => Direct, ping_via_the_sender_says_handled => Via}.
