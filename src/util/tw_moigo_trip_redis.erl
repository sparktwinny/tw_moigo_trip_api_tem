%%%-------------------------------------------------------------------
%%% @author psw
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. 2월 2016 오후 1:07
%%%-------------------------------------------------------------------
-module(tw_moigo_trip_redis).
-author("psw").
-include("src/include/tw_macro.hrl").
-include("src/include/db_record.hrl").
%% API
-export([init/0, loop/1, get_group_update_lock/2, release_group_update_lock/2, load_redis_pool/0,redis_call/3]).
-record(state, {}).
init() ->
  %%이 프로세스를 subscribe 한 메세지를 핸들할 프로세스로 지정한다.
  NewState = #state{},
  SpanPid = spawn(tw_moigo_trip_redis, loop, [NewState]),

  RedisEndPoint = case ets:lookup(global_variables, "redis_pubsubendpoint") of
                    [{Key, Val}] ->
                      Val;
                    _ -> "null"
                  end,

  ?INFOL("redis endpoint?:~p", [RedisEndPoint]),
  {ok, Sub} = eredis_sub:start_link(RedisEndPoint, 6379, ""),
  ?INFOL("Sub:~p~n", [SpanPid]),

  Res = eredis_sub:controlling_process(Sub, SpanPid),

  %%subscribe 해야 하는 체널들
  Channels = [<<"mqtt_to_api">>, <<"ping_alive">>],
  ok = eredis_sub:subscribe(Sub, Channels),


  erlang:send_after(5000, SpanPid, {check_conditions_for_mqtt_servers, SpanPid}),
  ok.



%%--------------------------------------------------------------------
%% @doc
%% 일정 시간동안 ping을 보내오지 않은, 즉 뭔가 상태에 이상이 생긴 MQTT서버를 끊어낸다.
%%
%% @end
%%--------------------------------------------------------------------
delete_invalid_mqtt_node(Val) ->
  {NodeName, LastUpdate} = Val,


  Now1 = tw_util:get_current_time_in_unix_timestamp(),
  Delta = (Now1 - LastUpdate),
  %% ?INFOL("Updated Time For Node ~p :~p, Now:~p,Delta:~p~n", [NodeName, LastUpdate, Now1, Delta]),
  if (Delta > 60) ->
    %%1분이 넘은 상태라 서버가 죽었다고 판단한다.
    "," ++ tw_util:to_list(NodeName);

    true -> ""


  end.


%%--------------------------------------------------------------------
%% @doc
%% 그룹에 관련한 정보를 업데이트 할때, LOCK을 가져온다.
%%
%% @end
%%--------------------------------------------------------------------
get_group_update_lock(UserIdx, GroupIdx) ->

  Res = eredis_pool:q(get_redis_pool(UserIdx), ["HINCRBY", UserIdx, GroupIdx, 1]),

  case Res of
    {ok, <<"1">>} -> true;
    _ -> false
  end.

%%--------------------------------------------------------------------
%% @doc
%% 그룹에 관련한 정보를 업데이트 할때, LOCK을 해제한다.
%%
%% @end
%%--------------------------------------------------------------------
release_group_update_lock(UserIdx, GroupIdx) ->

  Res = eredis_pool:q(get_redis_pool(UserIdx), ["HDEL", UserIdx, GroupIdx]).


loop(State) ->


  receive

    {check_conditions_for_mqtt_servers, SpanPid} ->
      try

        %%일정시간 응답이 없는 mqtt노드를 지운다.
        DeleteNodeList = tw_util:dump(ets, mqtt_server_list, fun delete_invalid_mqtt_node/1),


        Nodes = string:tokens(DeleteNodeList, ","),
        Sum = [],
        lists:foldl(
          fun(Node, Result) ->
            Key = try list_to_existing_atom(Node)
                  catch
                    ER:Err ->
                      list_to_atom(Node)
                  end,
            ets:delete(mqtt_server_list, Key),
            ?INFOL("Deleteing old node:~p~n", [Node]),
            ok
          end
          , Sum, Nodes),

        erlang:send_after(60000 * 5, SpanPid, {check_conditions_for_mqtt_servers, SpanPid}),
        loop(State)
      catch
        ER:Err ->

          StackList = erlang:get_stacktrace(),

          %%  {ModuleF3,FunctionF,ArityF3,StackHistory3}= lists:nth(3, StackList),

          lager:error("-------(!![error REDIS:~p,arg:~p,StackT1:~p]!!)-------", [ER, Err, StackList]),
          loop(State)
      end;
    {subscribed, C, Sub} = M ->

      ?INFOL("Redis Channel ~p is Subscribed!", [C]),
      eredis_sub:ack_message(Sub),

      case C of

        <<"ping_alive">> ->
          %%현재 존재하는 모든 MQTT서버에 살아있는지 알려달라 한다.
          JsonMessage = jsx:encode([
            {<<"message_commend">>, <<"request_alive">>},
            {<<"org_node">>, node()}
          ]),


          eredis_pool:q(redis_pubsub, ["PUBLISH", <<"api_to_mqtt">>, JsonMessage]);
        _ -> ok

      end,
      loop(State);
    {message, Channel, Message, Sub} ->

      try

        Json = jsx:decode(Message),
        Commend = proplists:get_value(<<"message_commend">>, Json),
        OriginNode = (proplists:get_value(<<"org_node">>, Json, <<"not_exist">>)),
        io_lib:format("orgnode:~p~n", [OriginNode]),
        ND = node(),

        NewState = case OriginNode of
                     ND ->
                       %%"이 노드에서 온 메세지다. 무시.
                       State;
                     <<"not_exist">> ->
                       %%정보가 없다.
                       ?INFOL("MESSAGE FROM UNKNOWN NODE:~p:~p~n", [Channel, Message]),
                       State;
                     _ ->
                       case Commend of
                         <<"ping_alive">> ->


                           ets:insert(mqtt_server_list, {OriginNode, tw_util:get_current_time_in_unix_timestamp()});
                         <<"force_logout">> ->

                           %%                         {<<"message_commend">>, <<"force_logout">>},
                           %%                         {<<"user_idx">>, UserIdx},
                           %%                         {<<"client_type">>, tw_util:to_binary(ClientType)},
                           %%                         {<<"org_node">>, node()}

                           UserIdx = proplists:get_value(<<"user_idx">>, Json),
                           ClientType = proplists:get_value(<<"client_type">>, Json),
                           tw_user_gen:stop(tw_twinny_util:get_gen_server_id(UserIdx, ClientType)),
                           State;
                         _ ->
                           ?ERRORL("commend_not_found:~p:~p", [Channel, Message]),
                           State
                       end

                   end,


        eredis_sub:ack_message(Sub),
        loop(NewState)
      catch
        ER:Err ->

          StackList = erlang:get_stacktrace(),

          %%  {ModuleF3,FunctionF,ArityF3,StackHistory3}= lists:nth(3, StackList),

          lager:error("-------(!![error REDIS:~p,arg:~p,StackT1:~p]!!)-------", [ER, Err, StackList]),
          loop(State)
      end;
    {Pid, module_update} ->

      ?MODULE:loop(State);
    {_, _, _, Sub} = MM ->
      eredis_sub:ack_message(Sub),
      io:format("other message received:~p~n", [MM]),
      loop(State)
  end.
%%--------------------------------------------------------------------
%% @doc
%% 기존에 연결정보가 존재하지 않는다면 새로운 Redis 연결 풀을 만들고 내용을 저장한다.
%%
%% @end
%%--------------------------------------------------------------------
load_pool_and_save_data(PoolName, MaxConnection, Host, Port) ->
  case ets:lookup(redis_pool_info, PoolName) of
    [{PoolName, Info}] ->
      ok;
    _ ->

      ets:insert(redis_pool_info, {PoolName, {PoolName, MaxConnection, Host, Port}}),
      eredis_pool:create_pool(PoolName, MaxConnection, Host, Port)
  end.


%%--------------------------------------------------------------------
%% @doc
%% 서버에서 사용하는 redis풀들을 모두 로드한다.
%%
%% @end
%%--------------------------------------------------------------------
load_redis_pool() ->
  ServerPosition = tw_util:get_server_position(),

  DBNODE = case ServerPosition of
             local ->

               load_pool_and_save_data(node_manage, 10, "localhost", 6379),
               load_pool_and_save_data(lock, 10, "localhost", 6379),
               load_pool_and_save_data(redis_group_cache_read, 10, "localhost", 6379),
               load_pool_and_save_data(redis_group_cache_write, 10, "localhost", 6379),
               load_pool_and_save_data(redis_cache_read, 10, "localhost", 6379),
               load_pool_and_save_data(redis_cache_write, 10, "localhost", 6379),
               load_pool_and_save_data(redis_pubsub, 10, "localhost", 6379),
               load_pool_and_save_data(redis_message_storage, 10, "localhost", 6379),
               load_pool_and_save_data(redis_session, 10, "localhost", 6379),
               load_pool_and_save_data(redis_push_onff_read, 10, "localhost", 6379),
               load_pool_and_save_data(redis_push_onff_write, 10, "localhost", 6379),
               ok;
             dev ->

               load_pool_and_save_data(node_manage, 10, "redis-dev.twinny.io", 6379),
               load_pool_and_save_data(lock, 10, "redis-dev.twinny.io", 6379),
               load_pool_and_save_data(redis_group_cache_read, 10, "redis-dev.twinny.io", 6379),
               load_pool_and_save_data(redis_group_cache_write, 10, "redis-dev.twinny.io", 6379),
               load_pool_and_save_data(redis_cache_read, 10, "redis-dev.twinny.io", 6379),
               load_pool_and_save_data(redis_cache_write, 10, "redis-dev.twinny.io", 6379),
               load_pool_and_save_data(redis_pubsub, 10, "redis-dev.twinny.io", 6379),
               load_pool_and_save_data(redis_message_storage, 10, "redis-dev.twinny.io", 6379),
               load_pool_and_save_data(redis_session, 10, "redis-dev.twinny.io", 6379),
               load_pool_and_save_data(redis_push_onff_read, 10, "redis-dev.twinny.io", 6379),
               load_pool_and_save_data(redis_push_onff_write, 10, "redis-dev.twinny.io", 6379),

               ok;
             stage ->

               load_pool_and_save_data(node_manage, 10, "localhost", 6379),
               load_pool_and_save_data(lock, 10, "localhost", 6379),
               load_pool_and_save_data(redis_group_cache_read, 10, "localhost", 6379),
               load_pool_and_save_data(redis_group_cache_write, 10, "localhost", 6379),
               load_pool_and_save_data(redis_cache_read, 10, "localhost", 6379),
               load_pool_and_save_data(redis_cache_write, 10, "localhost", 6379),
               load_pool_and_save_data(redis_pubsub, 10, "localhost", 6379),
               load_pool_and_save_data(redis_message_storage, 10, "localhost", 6379),
               load_pool_and_save_data(redis_session, 10, "localhost", 6379),
               load_pool_and_save_data(redis_push_onff_read, 10, "localhost", 6379),
               load_pool_and_save_data(redis_push_onff_write, 10, "localhost", 6379),

               ok;
             real ->

               load_pool_and_save_data(node_manage, 10, "redis_write.twinny.io", 6379),
               load_pool_and_save_data(lock, 10, "redis.twinny.io", 6379),
               load_pool_and_save_data(redis_group_cache_read, 10, "redis_read.twinny.io", 6379),
               load_pool_and_save_data(redis_group_cache_write, 10, "redis_write.twinny.io", 6379),
               load_pool_and_save_data(redis_cache_read, 10, "redis_read.twinny.io", 6379),
               load_pool_and_save_data(redis_cache_write, 10, "redis_write.twinny.io", 6379),
               load_pool_and_save_data(redis_pubsub, 10, "redis.twinny.io", 6379),
               load_pool_and_save_data(redis_message_storage, 10, "redis.twinny.io", 6379),
               load_pool_and_save_data(redis_push_onff_read, 10, "redis.twinny.io", 6379),
               load_pool_and_save_data(redis_push_onff_write, 10, "redis.twinny.io", 6379),
               load_pool_and_save_data(redis_session, 10, "redis.twinny.io", 6379),
               ok
           end.

%%--------------------------------------------------------------------
%% @doc
%% 해당하는 타입에 따라 다른 종류의 풀에서 Redis요청을 보낸다.
%%
%% @end
%%--------------------------------------------------------------------
redis_call(CallingType, Request,InfoT,  GiveupUponError) ->


  Info1=tw_util:to_integer(InfoT),
  try

    case CallingType of


      redis_session->
        eredis_pool:q(redis_session,Request);

      redis_pubsub->
        eredis_pool:q(redis_pubsub,Request);
      cached_info_read ->
        Pool=get_redis_cache_pool_read_by_user_idx(Info1),
        eredis_pool:q(Pool, Request);
      cached_info_write ->
        Pool=get_redis_cache_pool_write_by_user_idx(Info1),
        eredis_pool:q(Pool, Request);
      send_ios_push_read ->
        Pool=get_redis_cache_pool_read_by_user_idx(Info1),
        eredis_pool:q(Pool, Request);
      send_ios_push_write ->
        Pool=get_redis_cache_pool_write_by_user_idx(Info1),
        eredis_pool:q(Pool, Request);
      cached_user_idx_read ->
        Pool=redis_cache_read,
        eredis_pool:q(Pool, Request);
      cached_user_idx_write ->
        Pool=redis_cache_write,
        eredis_pool:q(Pool, Request);

      cached_group_idx_read ->
        Pool=redis_group_cache_read,
        eredis_pool:q(Pool, Request);
      cached_group_idx_write ->
        Pool=redis_group_cache_write,
        eredis_pool:q(Pool, Request);

      cached_group_info_write->
        Pool=get_redis_group_cache_pool_write_by_group_idx(Info1),
        eredis_pool:q(Pool, Request);
      cached_group_info_read->
        Pool=get_redis_group_cache_pool_read_by_group_idx(Info1),
        eredis_pool:q(Pool, Request);

      stored_message->
        Pool=get_stored_message_pool_by_user_idx(Info1),
        eredis_pool:q(Pool, Request);

      _ -> ok
    end

  catch
    Error:noproc
      ->

      case GiveupUponError of
        true -> {error, noproc};
        _ -> load_redis_pool(),
          redis_call(CallingType, Info1, Request, true)
      end

  end.


redis_call(CallingType,Info1,Request) ->
  redis_call(CallingType, Info1, Request, false).
get_stored_message_pool_by_user_idx(UserIdx)->
  Int = list_to_integer(tw_util:to_list(UserIdx)),
  Idx = jch:ch(Int, 1) ,

  case Idx of
    0->redis_message_storage
  end.
get_redis_group_cache_pool_write_by_group_idx(GroupIdx)->
  Int = list_to_integer(tw_util:to_list(GroupIdx)),
  Idx = jch:ch(Int, 1) ,

  case Idx of
    0->redis_group_cache_write
  end.
get_redis_group_cache_pool_read_by_group_idx(GroupIdx)->
  Int = list_to_integer(tw_util:to_list(GroupIdx)),
  Idx = jch:ch(Int, 1) ,

  case Idx of
    0->redis_group_cache_read
  end.
get_redis_cache_pool_read_by_user_idx(UserIdx) ->
  Int = list_to_integer(tw_util:to_list(UserIdx)),
  Idx = jch:ch(Int, 1) ,

  case Idx of
    0->redis_cache_read
  end.

get_redis_cache_pool_write_by_user_idx(UserIdx) ->
  Int = list_to_integer(tw_util:to_list(UserIdx)),
  Idx = jch:ch(Int, 1) ,

  case Idx of
    0->redis_cache_write
  end.




%%  IsDataSet =
  %%    case eredis_pool:q(pool3, ["get", "data_set"]) of
  %%      {ok, Value} when Value =/= undefined ->
  %%        true;
  %%      _ ->
  %%        false
  %%    end,
  %%
  %%  case IsDataSet of
  %%    true ->
  %%      ok;
  %%
  %%    _ ->
  %%
  %%      %%유저 정보 캐슁
  %%      Result2 = tw_db:get_all_user(),
  %%      io:format("all user:~p,~n", [Result2#db_result_select.size]),
  %%      lists:foreach(
  %%        fun(RR) ->
  %%
  %%          %%io:format("res:~p,~n",[FriendRecord]),
  %%          eredis_pool:q(pool3, ["hset", tw_util:to_list(RR#db_user_all.user_idx), "user_nick", RR#db_user_all.user_nick]),
  %%          eredis_pool:q(pool3, ["hset", tw_util:to_list(RR#db_user_all.user_idx), "unique_id", RR#db_user_all.user_unique_id]),
  %%          eredis_pool:q(pool3, ["hset", tw_util:to_list(RR#db_user_all.user_idx), "profile", RR#db_user_all.user_profile_img]),
  %%          eredis_pool:q(pool3, ["hset", "unique_to_idx", RR#db_user_all.user_unique_id, tw_util:to_list(RR#db_user_all.user_idx)]),
  %%          eredis_pool:q(pool3, ["hset", tw_util:to_list(RR#db_user_all.user_idx), "version", RR#db_user_all.version])
  %%        end, Result2#db_result_select.records),
  %%      eredis_pool:q(pool3, ["FLUSHALL"]),
  %%
  %%      %%그룹정보 cacheing
  %%      ResultGroup = tw_db:get_all_groups(),
  %%      lists:foreach(
  %%        fun(RR) ->
  %%
  %%          %%io:format("res:~p,~n",[FriendRecord]),
  %%          Idx = "g_" ++ tw_util:to_list(RR#db_group_all.group_idx),
  %%          eredis_pool:q(pool3, ["hset", Idx, "profile", RR#db_group_all.group_profile_img]),
  %%          eredis_pool:q(pool3, ["hset", Idx, "group_unique_id", RR#db_group_all.group_unique_id]),
  %%          eredis_pool:q(pool3, ["hset", Idx, "group_nick", RR#db_group_all.group_nick]),
  %%
  %%          eredis_pool:q(pool3, ["hset", Idx, "member_num", RR#db_group_all.member_num]),
  %%          %%eredis_pool:q(pool3, ["hset", Idx, "notice_title", RR#db_group_all.notice_title]),
  %%          eredis_pool:q(pool3, ["hset", Idx, "version", RR#db_group_all.version]),
  %%          %%최근 사진은 나중에 불러오자.
  %%
  %%
  %%          %%그룹 맴버들의 메세지 읽음 처리 리스트를 불러온다
  %%
  %%
  %%
  %%
  %%
  %%          eredis_pool:q(pool3, ["hset", "g_unique_to_idx", RR#db_group_all.group_unique_id, RR#db_group_all.group_idx])
  %%        end, ResultGroup#db_result_select.records),
  %%      eredis_pool:q(pool3, ["set", "data_set", "1"])
  %%
  %%
  %%  end,


  %%  eredis_pool:create_pool(pool3, 10),
  %%
  %%%%  eredis_pool:q(pool3, ["FLUSHALL"]),
  %%  Result2 = tw_db:get_all_user(),
  %%
  %%  io:format("all user:~p,~n",[Result2#db_result_select.size]),
  %%  lists:foreach(
  %%    fun(RR) ->
  %%
  %%      %%io:format("res:~p,~n",[FriendRecord]),
  %%       eredis_pool:q(pool3, ["hset", tw_util:to_list(RR#db_user_all.user_idx), "user_nick", RR#db_user_all.user_nick]),
  %%       eredis_pool:q(pool3, ["hset", tw_util:to_list(RR#db_user_all.user_idx), "unique_id", RR#db_user_all.user_unique_id]),
  %%      eredis_pool:q(pool3, ["hset", tw_util:to_list(RR#db_user_all.user_idx), "profile", RR#db_user_all.user_profile_img]),
  %%      eredis_pool:q(pool3, ["hset", "unique_to_idx", RR#db_user_all.user_unique_id , tw_util:to_list(RR#db_user_all.user_idx)]),
  %%      eredis_pool:q(pool3, ["hset", tw_util:to_list(RR#db_user_all.user_idx), "version", RR#db_user_all.version])
  %%    end, Result2#db_result_select.records),
  %%
  %%
  %%  %%그룹정보 cacheing
  %%  ResultGroup=tw_db:get_all_groups(),
  %%  lists:foreach(
  %%    fun(RR) ->
  %%
  %%      %%io:format("res:~p,~n",[FriendRecord]),
  %%      Idx="g_"++tw_util:to_list(RR#db_group_all.group_idx),
  %%      eredis_pool:q(pool3, ["hset", Idx, "profile", RR#db_group_all.group_profile_img	]),
  %%      eredis_pool:q(pool3, ["hset", Idx, "group_unique_id", RR#db_group_all.group_unique_id]),
  %%      eredis_pool:q(pool3, ["hset", Idx, "group_nick", RR#db_group_all.group_nick]),
  %%
  %%      eredis_pool:q(pool3, ["hset", Idx, "member_num", RR#db_group_all.member_num]),
  %%      %%eredis_pool:q(pool3, ["hset", Idx, "notice_title", RR#db_group_all.notice_title]),
  %%      eredis_pool:q(pool3, ["hset", Idx, "version", RR#db_group_all.version]),
  %%      %%최근 사진은 나중에 불러오자.
  %%
  %%      eredis_pool:q(pool3, ["hset", "g_unique_to_idx", RR#db_group_all.group_unique_id , RR#db_group_all.group_idx])
  %%    end, ResultGroup#db_result_select.records),
  %%ok.



  get_redis_pool(UserIdx) ->
lock.


%%increment_group_member_num(GroupIdx) ->
%%  Idx = "g_" ++ tw_util:to_list(GroupIdx),
%%  eredis_pool:q(pool3, ["HINCRBY", Idx, "member_num", 1]).