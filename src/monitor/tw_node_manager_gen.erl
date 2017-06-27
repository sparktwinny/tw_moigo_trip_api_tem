%%%-------------------------------------------------------------------
%%% @author psw
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. 7월 2016 오후 10:46
%%%-------------------------------------------------------------------

-module(tw_node_manager_gen).
-author("psw").
-include("src/include/db_record.hrl").
-include("src/include/tw_macro.hrl").
-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-export([get_node_type/0,get_node_host_from_json/1,get_node_from_json/1,get_node_as_json/0,add_node/1, sync_node_order/2, compare_item/2, get_node_by_user_uniqe_id/1, register_aes_key_from_other_server/2]).
-define(SERVER, ?MODULE).

-record(state, {node_array, node_num, boot_time}).



%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  ?INFOL("initialzing Node Manager~!", []),
  net_kernel:monitor_nodes(true),
  {ok, #state{node_array = [], node_num = 0, boot_time = tw_datetime:get_current_time_in_unix_timestamp()}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(
    Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).



handle_call({sync_node_order, BootTime, Array}, _From, State) ->


  ?INFOL("Syncing NODE LIST!", []),
  NewState = if (BootTime < State#state.boot_time)
    -> State#state{node_array = Array, node_num = length(Array)};
               true ->
                 State
             end,

  {reply, {ok, 0}, NewState};


handle_call({add_node, NewNodeT}, _From, StateOld) ->

  {NewNode, Time} = NewNodeT,

  %%우선 현재 노드 상태를 체크한다

  State = lists:foldl(
    fun(Record, Result) ->

      {Node, Time1} = Record,
      PingTo = get_node_host_from_json(Node),

      Ping = net_adm:ping(PingTo),
      case Ping of
        pang ->
          swap_with_the_last_and_delete_node(Result, Node);
        _ ->
          Result
      end


    end


    , StateOld, StateOld#state.node_array),
  Idx = index_of(NewNode, State#state.node_array),
  ?INFOL("IDX :~p", [Idx]),
  NewState = case Idx of

               not_found ->


                 NodeToAdd = {NewNode, Time},
                 %%일단 내가 받은 기준으로 맨 뒤로 만든다음에

                 ?INFOL("Curretnn temp Node List:~p", [State#state.node_array]),
                 NewList = sort_list_by_time_added(lists:append([NodeToAdd], State#state.node_array)),
                 ?INFOL("Curretnn after Node List:~p", [NewList]),
                 %%현재 Relay 노드들에게 노드 순서를 맞춘다. 이때 부트 타임 기준으로 제일 나중의 노드가 우선권을 갖는다.
                 NewStateT = State#state{node_array = NewList, node_num = State#state.node_num + 1},

                 MyNode = get_node_as_json(),
                 case NewNode of
                   MyNode -> ok;
                   _ ->
                     rpc:async_call(get_node_host_from_json(NewNode), tw_node_manager_gen, add_node, [{MyNode, tw_util:get_server_launch_time_in_sec()}])
                 end,

                 rpc:multicall(nodes(), tw_node_manager_gen, sync_node_order, [NewStateT#state.boot_time, NewStateT#state.node_array]),


                 NewStateT;
               _ ->


                 State
             end,

  ?INFOL("Curretnn Node List:~p", [NewState]),
  set_tag_for_ec2(NewState),
  ?INFOL("Curretnn Node List:~p", [NewState]),
  {reply, {ok, 0}, NewState};


handle_call({delete_node, NodeToDelete}, _From, State) ->


  %%이 노드의 역할이 all일수도 있기 때문에 우선 릴레이 목록에서 지운다.
  ?INFOL("Deleting Nodes:~p!", [NodeToDelete]),

  NewState = remove_node(NodeToDelete, State),
  ?INFOL("NEw State:~p", [NewState]),

  ?INFOL("known nodes:~p", [nodes()]),
  %%현재 Relay 노드들에게 노드 순서를 맞춘다. 이때 부트 타임 기준으로 제일 나중의 먼저가 우선권을 갖는다.

  lists:foreach(
    fun(Host) ->
      rpc:async_call(Host, tw_node_manager_gen, sync_node_order, [NewState#state.boot_time, NewState#state.node_array])
    end, nodes()),

  set_tag_for_ec2(NewState),
  ?INFOL("Curretnn Node List:~p", [NewState]),
  {reply, {ok, 0}, NewState};

handle_call({get_node_by_user_uniqe_id, UserUniqueIdTT}, _From, State) ->

  try


    UserUniqueIdT = tw_util:to_list(UserUniqueIdTT),
    DividerIdx = string:str(UserUniqueIdT, "_"),

    UserUniqueId = case DividerIdx of
                     0 -> UserUniqueIdT;
                     _ ->
                       Unique = string:tokens(UserUniqueIdT, "_"),
                       Size = length(Unique),
                       if (Size >= 2)
                         ->
                         lists:nth(2, string:tokens(UserUniqueIdT, "_"));
                         true ->
                           0
                       end
                   end,


    {Node, AddedTime} = try
                          Int = list_to_integer(tw_util:to_list(UserUniqueId)),
                          ?INFOL("int:~p,Bukcet:~p", [Int, State#state.node_num]),
                          Idx = jch:ch(Int, State#state.node_num) + 1,
                          lists:nth(Idx, State#state.node_array)
                        catch
                          Er:badarg ->
                            ?WARNL("BAD ARG FOR JCH:~p", [UserUniqueId]),
                            lists:nth(1, State#state.node_array);
                          _:ER -> throw(conver_exception)
                        end,

    ?INFOL("Result Node:~p", [Node]),

    {reply, {ok, Node}, State}
  catch
    Errr:Error ->

      StackList = erlang:get_stacktrace(),
      ?ERRORL("Error while process node manager:Er:~p,Error:~p,StackT1:~p", [tw_util:to_list(Errr), Error, StackList]),

      {Node2, AddedTime2} = lists:nth(1, State#state.node_array),
      {reply, {ok, Node2}, State}

  end;

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

%%handle_info({nodeup, Node}, State) ->
%%
%%
%%  add_node(Node),
%%
%%  {noreply, State};

handle_info({nodedown, NodeHost}, State) ->

  ?ERRORL("NodeDown!:~p", [NodeHost]),
  NodesToDelete = get_nodes_by_host(NodeHost, State#state.node_array),
  {reply, {ok, 0}, NewState} = handle_call({delete_node, NodesToDelete}, self(), State),

  {noreply, NewState};
handle_info(_INFO, State) ->


  {noreply, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

register_aes_key_from_other_server(AESKey, UniqueId) ->
  AESModKey = UniqueId,

  AesForState = case AESKey of
                  undefined -> undefined;
                  <<"undefined">> -> undefined;
                  _ ->

                    RawKey = tw_util:decode_web_safe_base64(AESKey),

                    ?INFOL("AES MODEKEY:~p", [AESModKey]),
                    ets:insert(aes_key_list, {AESModKey, RawKey}),


                    RawKey
                end.
%% @doc 유저 유니크아이디를 키값으로 Jump Consitant Hash를 사용해서 필요한 Node를 불러온다.

get_node_by_user_uniqe_id(UniqueId) ->
  {ok, Node} = gen_server:call(?MODULE, {get_node_by_user_uniqe_id, UniqueId}, infinity),
  Node.

sync_node_order(BootTime, Array) ->
  Res = gen_server:call(?MODULE, {sync_node_order, BootTime, Array}, infinity).
%% @doc 다른 서버가 자신의 존재를 알려왔을때 그 노드를 리스트에 등록한다. 그리고 가장 먼저 생성된 노드 기준으로 다른 모든 노드들에게 순서를 제정렬한다.
add_node(Node) ->
  ?INFOL("adding new Node:~p", [Node]),
  Res = gen_server:call(?MODULE, {add_node, Node}, infinity).

get_nodes_by_host(Host, Nodes) ->
  lists:filter(
    fun({N, _Time}) -> get_node_host_from_json(N) == Host end,
    Nodes
  ).

%% @doc 노드를 지운다. 그리고 제정렬한다.
delte_node(Node) ->

  Res = gen_server:call(?MODULE, {delete_node, Node}, infinity).

remove_node(NodeToDelete, State) when not is_list(NodeToDelete) ->
  remove_node([NodeToDelete], State);
remove_node(NodesToDelete, State) ->
  NodesHostToDelete = [get_node_host_from_json(N) || {N, _Time} <- NodesToDelete],

  lists:foreach(
    fun(N) -> eredis_pool:q(node_manage, ["LREM", "known_relay_host", 0, N]) end,
    NodesHostToDelete
  ),
  lists:foreach(
    fun(N) -> eredis_pool:q(node_manage, ["LREM", "known_relay_host", 0, N]) end,
    NodesToDelete
  ),

  NewState = lists:foldl(
    fun swap_with_the_last_and_delete_node/2,
    State,
    NodesToDelete
  ),

  NewState.

%% @doc 서로의 노드를 비교한다. 더 최신순이 우선권을 가지도록 비교한다(ASC)
compare_item(Item1, Item2) ->
  %%true->Item1 가 왼쪽으로
  %%false->Item2 가 오른쪽으로
  {Node1, Time1} = Item1,
  {Node2, Time2} = Item2,
  %%시간이 더 크면 더 늦게 등록된 것이므로 오른쪽으로 가야한다.
  if (Item1 > Item2) ->
    false;
    true -> true
  end.
%% @doc 먼저 등록된 노드순으로 정렬한다. 즉 먼저 등록된노드가 리스트의 앞쪽에 위치하게 된다.
sort_list_by_time_added(List) ->

  lists:sort(fun(Item1, Item2) ->
    case Item2 of
      [] -> true;
      _ -> %%true->Item1 가 왼쪽으로
        %%false->Item2 가 오른쪽으로

        {Node1, Time1} = Item1,
        {Node2, Time2} = Item2,
        %%시간이 더 크면 더 늦게 등록된 것이므로 오른쪽으로 가야한다.
        if (Time1 > Time2) ->
          false;
          true -> true
        end
    end
             end, List).

get_last_node(State) ->

  lists:nthtail(State#state.node_num - 1, State#state.node_array).

%% @doc 삭제할 노드를 가장 나중으로 보낸후에 삭제한다.
swap_with_the_last_and_delete_node(Item, State) ->


  LastNode = get_last_node(State),

  Idx = index_of(Item, State#state.node_array),

  case Idx of
    not_found -> State;
    _ ->
      NewList = swap(State#state.node_array, Idx, State#state.node_num),
      FinalList = delete_from_list(State#state.node_num, NewList),


      State#state{node_array = FinalList, node_num = State#state.node_num - 1}
  end.


swap(List, S1, S2) -> {List2, [F | List3]} = lists:split(S1 - 1, List),
  LT = List2 ++ [lists:nth(S2, List) | List3],
  {List4, [_ | List5]} = lists:split(S2 - 1, LT),
  List4 ++ [F | List5].
delete_from_list(Idx, List) ->
  {Left, [_ | Right]} = lists:split(Idx - 1, List),
  Left ++ Right.
index_of(Item, List) -> index_of(Item, List, 1).
index_of(_, [], _) -> not_found;
index_of(Item, [{Item, P} | _], Index) -> Index;
index_of(Item, [_ | Tl], Index) -> index_of(Item, Tl, Index + 1).

get_default_node_type() ->
  case tw_util:get_server_position() of
    dev -> "dev_twm_api_autoscale";
    real -> "twm_api_autoscale";
    stage -> "stage_twm_api_autoscale";
    _ -> "local"
  end.

get_node_type() ->
  case os:getenv("MOIGO_NODE") of
    false -> get_default_node_type();
    NODE -> NODE
  end.

get_node_as_json() ->
  jsx:encode([
    {<<"type">>, get_node_type()},
    {<<"node">>, atom_to_list(node())}
  ]).

get_node_from_json(RAW) when is_atom(RAW) ->
  {get_default_node_type(), RAW};
get_node_from_json(RAW) when is_binary(RAW) ->
  try jsx:decode(RAW) of
    [{<<"type">>, Type}, {<<"node">>, Node}] -> {Type, list_to_atom(Node)}
  catch
    error:badarg -> get_node_from_json(binary_to_atom(RAW, utf8))
  end.
get_node_host_from_json(RAW) when is_binary(RAW) ->
  {_, Host} = get_node_from_json(RAW),
  Host.
set_tag_for_ec2(NewState) ->

  MyNodeN = get_node_as_json(),
  lists:foldl(
    fun(Record, Result) ->

      {Node, Time1} = Record,
      ?WARNL("node countfor:~ts,Count:~p", [Node, Result]),
      case Node of
        MyNodeN ->

          PingTo = get_node_host_from_json(Node),
          Type = get_node_type(),

          InstanceID = tw_util:get_instance_id(),
          ?WARNL("MyNode Count:~p , ~p", [InstanceID, Result]),
          tw_aws:set_ec2_instance_tag(InstanceID, Type ++ "_count", Result),
          tw_aws:set_ec2_instance_tag(InstanceID, "Name", Type ++ "_" ++ tw_util:to_list(Result)),
          tw_aws:set_ec2_instance_tag(InstanceID, "count", tw_util:to_list(Result));
        _ -> ok
      end,
      Result + 1


    end


    , 1, NewState#state.node_array).