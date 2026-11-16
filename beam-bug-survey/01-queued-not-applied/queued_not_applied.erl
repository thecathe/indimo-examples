%% The call returned, but "returned" only means "queued".
%%
%% Shape of emqx/emqx#17821 (hook removal), esl/MongooseIM#968 (dispatch reload) and
%% elixir-lang/elixir@3ae579d (stopping the lexical tracker): a server owns a piece of state
%% that readers consult directly (here an ETS table, in emqx a persistent_term). The write goes
%% through the server. With a cast, the caller learns "queued"; the reader then sees the old state.
-module(queued_not_applied).
-behaviour(gen_server).
-export([start_link/0, stop/0, hooks/0, del_async/1, del_sync/1, demo/0]).
-export([init/1, handle_call/3, handle_cast/2]).

-define(T, ?MODULE).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
stop() -> gen_server:stop(?MODULE).

%% Readers do not go through the server.
hooks() -> [H || {H} <- ets:tab2list(?T)].

%% BUGGY: ok means "the request is in the server's mailbox".
del_async(H) -> gen_server:cast(?MODULE, {del, H}).

%% FIXED: ok means "the server has applied it" (the reply is sent after the write).
del_sync(H) -> gen_server:call(?MODULE, {del, H}, infinity).

init([]) ->
    ets:new(?T, [named_table, public, set]),
    ets:insert(?T, [{a}, {b}]),
    {ok, no_state}.

handle_call({del, H}, _From, S) -> apply_del(H), {reply, ok, S}.
handle_cast({del, H}, S) -> apply_del(H), {noreply, S}.

apply_del(H) ->
    timer:sleep(50),               % the server is busy, as under load
    ets:delete(?T, H).

demo() ->
    {ok, _} = start_link(),
    ok = del_async(a),
    Stale = lists:sort(hooks()),   % the agent "knows" a was removed: it saw ok
    timer:sleep(100),
    AfterWait = lists:sort(hooks()),
    stop(),
    {ok, _} = start_link(),
    ok = del_sync(a),
    Fresh = lists:sort(hooks()),
    stop(),
    #{after_async_ok => Stale, a_little_later => AfterWait, after_sync_ok => Fresh}.
