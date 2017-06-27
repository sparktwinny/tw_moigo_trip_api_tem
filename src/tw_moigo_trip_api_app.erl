%% coding: utf-8
%%%-------------------------------------------------------------------
%%% @author psw
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 19. 12월 2015 오후 1:05
%%%-------------------------------------------------------------------
-module(tw_moigo_trip_api_app).
-author("psw").

-include("include/tw_macro.hrl").
-behaviour(application).

%% Application callbacks
-export([start/2,
  stop/1]).

%%%===================================================================
%%% Application callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application is started using
%% application:start/[1,2], and should start the processes of the
%% application. If the application is structured according to the OTP
%% design principles as a supervision tree, this means starting the
%% top supervisor of the tree.
%%
%% @end
%%--------------------------------------------------------------------
-spec(start(StartType :: normal | {takeover, node()} | {failover, node()},
    StartArgs :: term()) ->
  {ok, pid()} |
  {ok, pid(), State :: term()} |
  {error, Reason :: term()}).

start(_StartType, _StartArgs) ->


  {ok, Sup} = tw_moigo_trip_sup:start_link(),
  lager:start(),

  FixVersion = "0.1",
  ?INFOL("Initilizing. tw_moigo_trip,Node:~p,Version:~p", [node(), FixVersion]),
  start_servers(Sup),
  initialize(),
  {ok, Sup}.
initialize() ->


  ?INFOL("[Initializing..]", []),
  Dispatch = cowboy_router:compile([
    {'_', [
      {"/:version/[:api/[:what/[:opt]]]", tw_moigo_trip_http_base, []}
    ]}
  ]),
  %%----------[기본 모듈 시작]------------
  %%http 시작
  crypto:start(),
  inets:start(),
  lhttpc:start(),

  tw_reloader:start(),

  ets:new(redis_pool_info, [public, named_table]),
  ets:new(emoticon_info_list, [public, named_table]),
  ets:new(badword_list, [public, named_table]),
  ets:new(schedule_item_list, [bag, public, named_table]),
  ets:new(aes_key_list, [public, named_table]),
  ets:new(mqtt_server_list, [public, named_table]),
  ets:new(session_list_gen, [public, named_table]),
  ets:new(session_list_by_user_idx, [public, named_table]),
  ets:new(session_list, [public, named_table]),
  ets:new(global_variables, [public, named_table]),
  ets:new(idx_unique_map, [public, named_table]),
  ets:new(humor_list, [public, named_table]),
  ets:new(prepared_statement, [public, named_table]),

  Node = tw_util:to_list(node()),

  SQLHOST_DEV = "tw-db-dev.cmid7pfca2bg.ap-northeast-2.rds.amazonaws.com",
  SQLHOST_SEOUL = "tw-db-seoul.cmid7pfca2bg.ap-northeast-2.rds.amazonaws.com",
  %%SQLHOST_LOG=SQLHOST_SEOUL,
  SQLHOST_LOG = "203.247.208.196",


  %%  aws ec2 describe-instances  --region ap-northeast-2  --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id)  --query 'Reservations[*].Instances[*].[LaunchTime]'   --output text

  ?WARNL("loading from :~p,~p", [position, position]),
  ServerPosition = tw_util:env(position, position),

  ?WARNL("ServerPosition:~p", [ServerPosition]),

  DBNODE = case ServerPosition of
             local ->
               ?INFOL("LOCAL SERVER!", []),
               ets:insert(global_variables, {"instance_public_ip", SQLHOST_LOG}),
               ets:insert(global_variables, {"redis_pubsubendpoint", "localhost"}),
               ets:insert(global_variables, {"mqtt_endpoint", SQLHOST_LOG}),
               ets:insert(global_variables, {"endpoint", SQLHOST_LOG}),
               ets:insert(global_variables, {"file_server_endpoint", "localhost"}),
               tw_moigo_trip_redis:load_redis_pool(),


               SQLHOST_LOG;
             dev ->
               {ok, {{HttpVer, Code, Msg}, Headers, Body}} = httpc:request("http://169.254.169.254/latest/meta-data/public-ipv4"),

               ?INFOL("DEV SERVER,IP:~p!", [Body]),
               ets:insert(global_variables, {"endpoint", "elbdev.twinny.io"}),
               ets:insert(global_variables, {"mqtt_endpoint", "mqttelb_dev.twinny.io"}),
               ets:insert(global_variables, {"redis_pubsubendpoint", "redis-dev.twinny.io"}),
               ets:insert(global_variables, {"instance_public_ip", Body}),
               ets:insert(global_variables, {"file_server_endpoint", "elbdev.twinny.io"}),

               tw_moigo_trip_redis:load_redis_pool(),
               %%인스턴스 아이디를 조회해온다. Autoscaling hook관련
               {ok, {{_, _, _}, _, EC2ID}} = httpc:request("http://169.254.169.254/latest/meta-data/instance-id"),
               ets:insert(global_variables, {"ec2_instance_id", EC2ID}),
               SQLHOST_DEV;
             stage ->
               {ok, {{HttpVer, Code, Msg}, Headers, Body}} = httpc:request("http://169.254.169.254/latest/meta-data/public-ipv4"),
               STAGE_ADDR = Body,

               ?INFOL("STAGE SERVER,IP:~p!", [Body]),
               ets:insert(global_variables, {"endpoint", STAGE_ADDR}),
               ets:insert(global_variables, {"mqtt_endpoint", STAGE_ADDR}),
               ets:insert(global_variables, {"redis_pubsubendpoint", "localhost"}),
               ets:insert(global_variables, {"instance_public_ip", Body}),
               ets:insert(global_variables, {"file_server_endpoint", STAGE_ADDR}),

               tw_moigo_trip_redis:load_redis_pool(),
               %%인스턴스 아이디를 조회해온다. Autoscaling hook관련
               {ok, {{_, _, _}, _, EC2ID}} = httpc:request("http://169.254.169.254/latest/meta-data/instance-id"),
               ets:insert(global_variables, {"ec2_instance_id", EC2ID}),
               "localhost";
             real ->
               {ok, {{HttpVer, Code, Msg}, Headers, Body}} = httpc:request("http://169.254.169.254/latest/meta-data/public-ipv4"),

               ?INFOL("REAL SERVER,IP:~p!", [Body]),

               ets:insert(global_variables, {"endpoint", "elb.twinny.io"}),
               ets:insert(global_variables, {"mqtt_endpoint", "mqttelb.twinny.io"}),
               ets:insert(global_variables, {"redis_pubsubendpoint", "redis.twinny.io"}),
               ets:insert(global_variables, {"instance_public_ip", Body}),
               ets:insert(global_variables, {"image_endpoint", "image.twinny.io"}),
               ets:insert(global_variables, {"file_server_endpoint", "file.twinny.io"}),
               tw_moigo_trip_redis:load_redis_pool(),
               %%인스턴스 아이디를 조회해온다. Autoscaling hook관련
               {ok, {{_, _, _}, _, EC2ID}} = httpc:request("http://169.254.169.254/latest/meta-data/instance-id"),
               ets:insert(global_variables, {"ec2_instance_id", EC2ID}),
               SQLHOST_SEOUL
           end,
  ?INFOL("InstanceId:~p", [tw_util:get_instance_id()]),
  %%  DBNODE = if (Node == "tw_node1@203.247.208.196") ->
  %%    ets:insert(global_variables, {"instance_public_ip", SQLHOST_LOG}),
  %%    ets:insert(global_variables, {"redis_endpoint", SQLHOST_LOG}),
  %%    ets:insert(global_variables, {"mqtt_endpoint", SQLHOST_LOG}),
  %%    ?INFOL("LOCAL SERVER!", []),
  %%    SQLHOST_LOG;
  %%             true ->
  %%               {ok, {{HttpVer, Code, Msg}, Headers, Body}} = httpc:request("http://169.254.169.254/latest/meta-data/public-ipv4"),
  %%
  %%               ?INFOL("REAL SERVER,IP:~p!", [Body]),
  %%               ets:insert(global_variables, {"mqtt_endpoint", "mqttelb.twinny.io"}),
  %%               ets:insert(global_variables, {"redis_endpoint", "image.twinny.io"}),
  %%               ets:insert(global_variables, {"instance_public_ip", Body}),
  %%               SQLHOST_SEOUL
  %%           end,
  %%[todo:풀 다양화 시키기]


  ConnectionPools = [

    {tw_pool1, DBNODE},
    {tw_pool2, DBNODE},
    {tw_pool3, DBNODE},
    {tw_pool4, DBNODE},
    {tw_pool5, DBNODE},
    {tw_pool6, DBNODE},
    {tw_pool7, DBNODE},
    {tw_pool8, DBNODE},
    {tw_pool9, DBNODE},
    {tw_pool0, DBNODE}


    , {tw_log, DBNODE}, {tw_admin, DBNODE}],

  [add_connection_pool(Pool) || Pool <- ConnectionPools],


  tw_moigo_trip_redis:init(),


  ServerRole = tw_util:env(setting, role),
  NodeToRegister = tw_node_manager_gen:get_node_as_json(),

  ?INFOL("Server Role:~p", [ServerRole]),
  case ServerRole of
    api ->

      %%우선 알고있는 모든 릴레이 서버에게 에게 핑을 하고
      case eredis_pool:q(node_manage, ["LRANGE", "known_relay_host", 0, -1]) of
        {ok, Value} when Value =/= undefined ->
          ?INFOL("KNOWN NODES:~p", [Value]),
          lists:foreach(
            fun(NodeTuple) ->

              MyNodeType = tw_node_manager_gen:get_node_type(),
              {NodeType, Host} = tw_node_manager_gen:get_node_from_json(NodeTuple),

              case NodeType of
                MyNodeType ->
                  %%알고있는 모든 호스트들에게 나를 등록한다.

                  ?INFOL("Pinging Hosts:~p", [Host]),
                  Relay = Host,
                  Ping = net_adm:ping(Relay),

                  case Ping of
                    pang ->
                      ?WARNL("deleing downnode!33333:~p", [Host]),
                      eredis_pool:q(node_manage, ["LREM", "known_relay_host", 0, NodeTuple]);
                    _ ->
                      REsult = rpc:call(Relay, tw_node_manager_gen, add_node, [{NodeToRegister, tw_node_manager_gen:get_server_launch_time_in_sec()}]),
                      ?INFOL("Result:~p", [REsult])
                  end;
                _ ->
                  ok
              end


            end, Value),
          ok;
        _ ->
          failed
      end;
    all ->

      eredis_pool:q(node_manage, ["LREM", "known_relay_host", 0, node()]), %%  이전 버전 호환을 위해
      eredis_pool:q(node_manage, ["LREM", "known_relay_host", 0, NodeToRegister]),
      ?INFOL("Relay pushing to known host!", []),
      eredis_pool:q(node_manage, ["lpush", "known_relay_host", NodeToRegister]),

      ?INFOL("CURRENT RELAY HOST?:~p", [eredis_pool:q(node_manage, ["LRANGE", "known_relay_host", 0, -1])]),
      %%cowboy http 시작
      {ok, _} = cowboy:start_http(http, 100, [{port, 6060}, {max_connections, infinity}], [
        {env, [{dispatch, Dispatch}]}
      ]),
      %%우선 알고있는 모든 릴레이 서버에게 에게 핑을 하고
      case eredis_pool:q(node_manage, ["LRANGE", "known_relay_host", 0, -1]) of
        {ok, Value} when Value =/= undefined ->
          ?INFOL("KNOWN NODES:~p~n", [Value]),
          lists:foreach(
            fun(NodeTuple) ->

              MyNodeType = tw_node_manager_gen:get_node_type(),
              {NodeType, Host} = tw_node_manager_gen:get_node_from_json(NodeTuple),

              case NodeType of
                MyNodeType ->
                  %%알고있는 모든 호스트들에게 나를 등록한다.

                  ?INFOL("Pinging Hosts:~p", [Host]),
                  Relay = Host,
                  Ping = net_adm:ping(Relay),
                  case Ping of
                    pang ->
                      ?WARNL("deleing downnode2222!:~p", [Host]),
                      eredis_pool:q(node_manage, ["LREM", "known_relay_host", 0, NodeTuple]);
                    _ ->
                      REsult = rpc:call(Relay, tw_node_manager_gen, add_node, [{NodeToRegister, tw_util:get_server_launch_time_in_sec()}]),
                      ?INFOL("Result:~p", [REsult])
                  end;
                _ ->
                  ok
              end

            end, Value),
          ok;
        _ ->
          failed
      end;

    _ ->
      eredis_pool:q(node_manage, ["LREM", "known_relay_host", 0, node()]), %%  이전 버전 호환을 위해
      eredis_pool:q(node_manage, ["LREM", "known_relay_host", 0, NodeToRegister]),
      ?INFOL("Relay pushing to known host!", []),
      eredis_pool:q(node_manage, ["lpush", "known_relay_host", NodeToRegister]),

      ?INFOL("CURRENT RELAY HOST?", [eredis_pool:q(node_manage, ["LRANGE", "known_relay_host", 0, -1])]),
      %%cowboy http 시작
      {ok, _} = cowboy:start_http(http, 100, [{port, 6060}], [
        {env, [{dispatch, Dispatch}]}
      ])
  end,

  case ServerPosition of
    local ->
      ok;
    _ ->
      InstanceID = tw_util:get_instance_id()


  end,


  %%%%  RR = eredis_pool:q(pool1, ["LREM", "known_host", 0, node()]),
  %%%%
  %%%%  %%우선 알고있는 모두에게 핑을 하고
  %%%%  case eredis_pool:q(pool1, ["LRANGE", "known_host", 0, -1]) of
  %%%%    {ok, Value} when Value =/= undefined ->
  %%%%      io:format("RR~p~n", [Value]),
  %%%%      lists:foreach(
  %%%%        fun(Host) ->
  %%%%
  %%%%
  %%%%          %%알고있는 모든 호스트들에게
  %%%%
  %%%%          ?INFOL("Pinging Hosts:~p,~n", [Host]),
  %%%%          net_adm:ping(binary_to_atom(Host, utf8))
  %%%%
  %%%%        end, Value),
  %%%%      ok;
  %%%%    _ ->
  %%%%      failed
  %%%%  end,
  %%%%
  %%%%  %%내 자신을 추가한다.
  %%%%
  %%%%  eredis_pool:q(pool1, ["lpush", "known_host", node()]),
  %%%%  ?INFOL("Known Nodes:~p", [nodes()]),
  %%%%
  %%%%
  %%%%  {ok,REDIS} =eredis_pool:q(pool1, ["get", "current_local"]),
  %%%%  ?INFOL("Current REDIS:~p", [REDIS]),
  %%
  %%  %%그룹 메세지 숫자 캐슁을 위한 레디스 루아 스크립트 로드
  %%  case eredis_pool:q(pool1, ["get", "script_update_group_chat_messages_sha"]) of
  %%    {ok, ValueSha} when ValueSha =/= undefined ->
  %%
  %%      %%이미 등록되있다. 글로벌 베리어블에 sha를 추가
  %%      ets:insert(global_variables, {"script_update_group_chat_messages_sha", ValueSha}),
  %%      ok;
  %%    _ ->
  %%      %%스크립트 등록후 글로벌 베리어블에 추가.
  %%      {ok, File} = file:read_file("scheme/update_group_chat_messages.lua"),
  %%
  %%      {ok, Sha} = eredis_pool:q(pool1, ["SCRIPT", "LOAD", File]),
  %%      ets:insert(global_variables, {"script_update_group_chat_messages_sha", Sha}),
  %%      failed
  %%  end,



  %%badword 읽어오기
  %%  {ok, FileCSv} = file:read_file("scheme/badword_list.csv"),
  %%  DD = tw_util:parse_from_string(tw_util:to_list(FileCSv)),
  %%  add_to_badword_list(4, DD, length(DD)),
  %% tw_util:dump(ets, badword_list, fun print/1),

  tw_util:print_current_memory(),
  lager:info("-------[>>Initializing Complete Twm_api,Node:~p<<]-------", [node()]),
  ok.



print(Val) ->
  {Node, Update} = Val,
  io:format("print:~ts~n", [Node]).

add_to_badword_list(LineNum, Data, Size) ->
  add_to_badword(LineNum, Data, Size).
add_to_badword(LineNum, T, Size) ->


  if (LineNum > Size) ->
    ok;
    true ->

      First = lists:nth(LineNum, T),
      case First of
        [] -> ok;
        newline ->
          add_to_badword(LineNum + 1, T, Size);
        _ ->

          Second = lists:nth(LineNum + 1, T),
          ets:insert(badword_list, {tw_util:to_binary(Second), 1}),
          add_to_badword(LineNum + 2, T, Size)
      end
  end.


add_connection_pool(PoolTuple) ->

  {Pool, SQLHOST} = PoolTuple,
  %%seoul
  %%SQLHOST="alpha2.cmid7pfca2bg.ap-northeast-2.rds.amazonaws.com",
  %%tokyo
  %%  SQLHOST = "alphamysqldev.cwefd6dne2lt.ap-northeast-1.rds.amazonaws.com",
  %%LOCAL
  %% SQLHOST="203.247.208.196",
  %%SQLHOST="localhost",
  ?INFOL("Mysql Pool:~p,Host:~p ~n", [Pool, SQLHOST]),
  emysql:add_pool(Pool, [{size, 1},
    {user, "twinny"},
    {password, "xmdnlsldmlelqldkagh!"},
    {database, "alpha"},
    {encoding, utf8},
    {host, SQLHOST}, {port, 3306}]).



start_servers(Sup) ->
  ssl:start(),
  inets:start(),
  Dependencies = [{"twm crypto", crypto},
    {"moigo-trip-mysql", emysql},
    {"moigo-trip-eredis_pool", eredis_pool},
    {"moigo-trip-cowlib", cowlib},
    {"moigo-trip-tw_moigo_trip_log_manager", {supervisor, tw_moigo_trip_log_manager}},
    {"moigo-trip-tw_node_manager_gen", {supervisor, tw_node_manager_gen}},

    {"moigo-trip-lager", lager},

    {"moigo-trip-system monitor", {supervisor, tw_monitor_sup}},
    {"moigo-trip-xmerl", xmerl},
    {"moigo-trip-jsx", jsx},
    {"moigo-trip-lhttpc", lhttpc},
    {"moigo-trip-erlcloud", erlcloud},
    {"moigo-trip-ranch", ranch},
    {"moigo-trip-cowboy", cowboy}
  ],
  [start_application(Sup, Dep) || Dep <- Dependencies].


start_application(Sup, {Name, {supervisor, Module}}) ->
  ?INFOL("supervisor ~p(~p) is starting...", [Module, Name]),

  ?INFOL("[done:~p]", [supervisor:start_child(Sup, supervisor_spec(Module))]);
start_application(_Sup, {Name, Application}) ->
  ?INFOL("~p(~p) is starting...", [Name, Application]),
  REs = application:start(Application),
  case REs of
    ok -> ?INFOL("[done]", []);
    {ok, X} -> ?INFOL("[done:~p]", []);
    {error, Reason} -> ?ERRORL("Application ~p did not start:~p", [Name,Reason])
  end.





worker_spec(Module, Opts) when is_atom(Module) ->
  worker_spec(Module, start_link, [Opts]).

worker_spec(M, F, A) ->
  {M, {M, F, A}, permanent, 10000, worker, [M]}.

supervisor_spec(Module) when is_atom(Module) ->
  supervisor_spec(Module, start_link, []).

supervisor_spec(Module, Opts) ->
  supervisor_spec(Module, start_link, [Opts]).

supervisor_spec(M, F, A) ->
  {M, {M, F, A}, permanent, infinity, supervisor, [M]}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application has stopped. It
%% is intended to be the opposite of Module:start/2 and should do
%% any necessary cleaning up. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
-spec(stop(State :: term()) -> term()).
stop(_State) ->
  ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================