%%%-------------------------------------------------------------------
%%% @author psw
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 29. 12월 2015 오전 11:59
%%%-------------------------------------------------------------------
-module(tw_moigo_trip_http_base).
-author("psw").
-include("src/include/tw_macro.hrl").
-include("src/include/db_record.hrl").
%% API

-export([init/3, handle/2, terminate/3, make_reply/11]).
%%--------------------------------------------------------------------
%% @doc
%% 멀티파트라면 파일로 만들고  멀티파트가 아니면 기본 패이로드를 가져온다
%%
%% @end
%%--------------------------------------------------------------------
acc_multipart_and_upload(Req, Acc, Type, Data) ->

  BodyLength = cowboy_req:body_length(Req),
  ContentTypeParseHeader = cowboy_req:parse_header(<<"content-type">>, Req),
  case ContentTypeParseHeader of
    {ok, {<<"multipart">>, <<"form-data">>, _}, ReqTTT} ->
      case cowboy_req:part(Req, [{read_timeout, 100000}, {length, BodyLength},
        {read_length, BodyLength}]) of
        {ok, Headers, Req2} ->

          {ok, Body, Req3} = cowboy_req:part_body(Req2),

          case cow_multipart:form_data(Headers) of
            {file, _, Filename, ContentType, _TE} ->

              {ok, Headers2, ReqT4} = cowboy_req:part(Req3),
              {ok, BodyT5, ReqT5} = cowboy_req:part_body(ReqT4),
              {A1, A2, A3} = now(),
              random:seed(A1, A2, A3),

              %%1~10000
              Num = random:uniform(1000000),
              Hash = erlang:phash2(Filename),
              List = (io_lib:format("~.16B~.16B", [Hash, Num])),


              AfterUpload = case Type of
                              <<"schedule">> -> Name = lists:append(["schedule/", List]),

                                1;
                              _ -> ok

                            end,
              ReturList = lists:append(Acc, [AfterUpload]),
              acc_multipart_and_upload(Req3, ReturList, Type, Data);
            {data, FieldName} ->
              acc_multipart_and_upload(Req3, Acc, Type, Body)
            %%   {Re, {BodyT5, Filename, FileContents}}
          end;

        {done, Req2} ->
          {lists:reverse(Acc), [{<<"data">>, Data}]}
      end;
    _ ->

      {ok, Body, RawData} = cowboy_req:body_qs(Req, [{length, BodyLength}, {read_length, BodyLength}, {read_timeout, 30000}]),

      {[], Body}
  end.


%%--------------------------------------------------------------------
%% @doc
%% 멀티파트라면 파일로 만들고  멀티파트가 아니면 기본 패이로드를 가져온다
%%
%% @end
%%--------------------------------------------------------------------
acc_multipart(Req) ->
  BodyLength = cowboy_req:body_length(Req),
  case cowboy_req:part(Req, [{read_timeout, 100000}, {length, BodyLength},
    {read_length, BodyLength}]) of
    {ok, Headers, Req2} ->
      {ok, Body, Req3} = cowboy_req:part_body(Req2),
      case cow_multipart:form_data(Headers) of
        {file, _, Filename, ContentType, _TE} ->
          {body_next, Filename, ContentType, _TE, Body, Req3};
        {data, FieldName} ->
          {file_next, FieldName, Body, Req3}
      end
  end.

init(_Type, Req, []) ->
  {ok, Req, no_state}.

handle(Req0, State) ->


  {ApiVersion, Req} = cowboy_req:binding(version, Req0),
  {Category, Req1} = cowboy_req:binding(api, Req),
  {Api, Req2} = cowboy_req:binding(what, Req1),
  {Opt, Req3} = cowboy_req:binding(opt, Req2),
  {_, UserUniqueAESId, SS5} = cowboy_req:parse_header(<<"user_unique_id">>, Req3),
  {_, RSAVersion, _} = cowboy_req:parse_header(<<"encrypt_version">>, Req3),
  {_, Encryption, _} = cowboy_req:parse_header(<<"encryption">>, Req3),
  BodyLength = cowboy_req:body_length(Req3),
  {GetParms, Re} = cowboy_req:qs_vals(Req3),
  {_, CssVal, _} = cowboy_req:parse_header(<<"access-control-request-method">>, Req3),
  {_, OriginT, _} = cowboy_req:parse_header(<<"origin">>, Req3),
  {Peer, ReqE} = cowboy_req:peer(Req3),
  {Address, Port} = Peer,

  Origin = case OriginT of
             undefined -> <<"-">>;
             _ ->
               OriginT
           end,
  ConType = case Category of
              <<"webview">> -> <<"text/html">>;
              _ -> <<"text/plain">>
            end,
  %카테고리에 따라 받아온 내용을 Parse한다.
  {Received, ExtraData} = case Category of
                            %파일 업로드는 multipart로 들어오기 때문에 multipart처리를 해주어야 한다.
                            <<"file">> ->
                              %web의 크로스 브라우징 스크립트의 선발 리퀘스트에서는 content type이 없기 때문에 그냥 통과시키면 에러가 난다. access-control-request-method가 헤더에 존재하면서
                              % 파일 카테고리 리퀘스트라면 그냥 통과시킨다.

                              case CssVal of
                                undefined ->
                                  {ok, Body, RawData} = {ok, [], ""},
                                  case acc_multipart(Re) of
                                    {body_next, Filename, ContentType, _TE, FileContents, ReqT3} ->
                                      {ok, Headers, ReqT4} = cowboy_req:part(ReqT3),
                                      {ok, BodyT5, ReqT5} = cowboy_req:part_body(ReqT4),
                                      {{Re, {BodyT5, Filename, FileContents}}, <<"">>};
                                    {file_next, FieldName, BodyT5, ReqT3} ->
                                      {ok, Headers, ReqT4} = cowboy_req:part(ReqT3),
                                      {ok, FileContents, ReqT5} = cowboy_req:part_body(ReqT4),
                                      {file, _, Filename, ContentType, _TE} = cow_multipart:form_data(Headers),
                                      {{Re, {BodyT5, Filename, FileContents}}, <<"">>}
                                  end;
                                _ -> {<<"">>, <<"">>}
                              end;
                            %%아마존 SNS에서 온 내용이다. 일반적으로 요구하는 Payload형식이 아니라 따로 처리해준다.
                            <<"fromsns">> ->
                              JSONBODY = cowboy_req:body(Req),
                              {JSONBODY, []};
                            %%다른 모든 처리
                            _ ->
                              %%트위니에서 날라오는 페이로드는 data=JSON 의 형식으로 되어있다.
                              {ok, ReceivedTem, RawData} = cowboy_req:body_qs(Req, [{length, BodyLength}, {read_length, BodyLength}, {read_timeout, 30000}]),
                              {(proplists:get_value(<<"data">>, ReceivedTem, undefined)), []}
                          end,


  %%클라이언트 요청을 처리한다.
  ResultReply = case Category of
                  %%그냥 HealthCheck이기 때문에 리턴 내용은 상관 없다.
                  <<"elb">> ->
                    IsTerminated = tw_db_log_manager:is_terminated(),
                    case IsTerminated of
                      false -> jsx:encode([{<<"result">>, 0}]);
                      _ -> {404, jsx:encode([{<<"result">>, -401}, {<<"message">>, <<"만료된 서버입니다."/utf8>>}])}
                    end;
                  %AWS Autoscale에서 EC2 Instance가 Terminate될때 날라오는 notification이다. 처리해준다.
                  <<"fromsns">> ->
                    {ok, JsonPartTT, _} = Received,
                    ?WARNL("JSONPARTT:~p", [JsonPartTT]),
                    TT = jsx:decode(JsonPartTT, [return_maps]),
                    MessageJson = maps:get(<<"Message">>, TT, undefined),
                    Mesg = jsx:decode(MessageJson, [return_maps]),
                    tw_aws:handleOnTerminate(Mesg),
                    {200,jsx:encode([{<<"result">>, 0}])};
                  %파일 업로드는 따로 처리해준다.
                  <<"file">> ->
                    case Api of
                      <<"uploadImage">> -> twinny_http_file:handleImageUpload(Category, GetParms, Received, Peer);
                      <<"uploadFile">> -> twinny_http_file:handleFileUpload(Category, GetParms, Received, Peer)
                    end;
                  %다른 일반적인 내용에 대해 처리
                  _ ->
                    make_reply(ApiVersion, Category, Api, Opt, GetParms, Received, ExtraData, Peer, UserUniqueAESId, Encryption, RSAVersion)
                end,


  %만약 redirect http 요청(이미지, 파일 등을 다운받을때) 라면,301 redirect처리를 하고 redirect될 주소를 보내주기로 한다.
  case ResultReply of
    {200, file, OrgName, Ct} ->

      cowboy_req:reply(200, [
        {<<"content-type">>, ConType},
        {<<"content-disposition">>, <<"attachment; filename=\"", OrgName/binary, "\"">>}
      ], Ct, Req3);
    {301, redirect, URL} ->
      ?WARNL("Redirectiong to:~ts", [URL]),
      cowboy_req:reply(301, [
        {<<"content-type">>, ConType},
        {<<"Location">>, tw_util:to_binary(URL)},
        {<<"Access-Control-Allow-Origin">>, Origin},
        {<<"Access-Control-Allow-Credentials">>, <<"true">>},
        {<<"Access-Control-Allow-Methods">>, <<"GET, POST">>},
        {<<"Access-Control-Allow-Headers">>, <<"Content-Type,user_unique_id,*">>}

      ], <<"-">>, Req3);
    {404, request_error, Reason} ->
      cowboy_req:reply(404, [
        {<<"content-type">>, ConType}
      ], Reason, Req3);
    {500, server_error, Reason} ->
      cowboy_req:reply(404, [
        {<<"content-type">>, ConType}
      ], Reason, Req3);
    %일반 처리
    {HttpCode,  Result} ->
      cowboy_req:reply(HttpCode, [
        {<<"content-type">>, ConType},
        {<<"Access-Control-Allow-Origin">>, Origin},
        {<<"Access-Control-Allow-Credentials">>, <<"true">>},
        {<<"Access-Control-Allow-Methods">>, <<"GET, POST">>},
        {<<"Access-Control-Allow-Headers">>, <<"Content-Type,user_unique_id,*">>}
      ], Result, Req3)
  end,
  if (Category /= <<"elb">>)
    ->
    ?INFOL("api call, ~p/~p/~p", [Category, Api, Opt]);
    true ->
      ok
  end,
  {ok, Req3, State}.




parse_data_and_handle(Recevied, Peer, ExtraData, ApiVersion, Category, Api, GetParms, UserUniqueId, Address) ->
  %%암호화가 안된 요청이다.

  ParsedData = case Recevied of
                 undefined -> [];
                 _ -> jsx:decode(Recevied, [return_maps])
               end,
  DataMap = case ParsedData of
              [] -> #{<<"peer">>=>Peer, <<"extra_data">>=>ExtraData};
              _ -> WithPeer = maps:put(<<"peer">>, Peer, ParsedData),
                WithExtraData = maps:put(<<"extra_data">>, ExtraData, WithPeer)
            end,
  SessionKEy = maps:get(<<"session_key">>, DataMap, proplists:get_value(<<"session_key">>, GetParms, undefined)),
  DataMap2 = case eredis_pool:q(redis_session, ["get", SessionKEy]) of
               {ok, Value} when Value =/= undefined ->
                 _From = <<"">>,
                 StateUser = tw_twinny_util:get_user_state_from_json(Value),
                 StateNow = StateUser#user_state{ip_address = Address},
                 WithState = maps:put(<<"user_state">>, StateNow, DataMap);
               _ ->
                 DataMap
             end,

  handle(ApiVersion, Category, Api, GetParms, DataMap2).
%%--------------------------------------------------------------------
%% @doc
%% 요청의 검증과 분기처리/에러 핸들링을 위한 진입점
%%
%% @end
%%--------------------------------------------------------------------
make_reply(ApiVersion, Category, Api, Opt, GetParms, Recevied, ExtraData, Peer, UserUniqueId, Encryption, RSAVersion) ->

  {Address, Port} = Peer,
  IP = tw_util:get_ip_from_tuple(Address),
  try

    %ELB라면 log하지 않는다.
    if (Category /= <<"elb">>)
      ->
      ?INFOL("UserUniqueId:~p,C:~p,A:~p,Recevied:~p,Encryption:~p,GetParm:~p", [UserUniqueId, Category, Api, Recevied, Encryption, GetParms]);
      true ->
        ok
    end,
    ReplyResult = parse_data_and_handle(Recevied, Peer, ExtraData, ApiVersion, Category, Api, GetParms, UserUniqueId, Address),
    ReplyResult
  catch
    _:blocked ->
      {404,jsx:encode([{<<"result">>, -401}, {<<"message">>, <<"블럭된 유저입니다"/utf8>>}])};
    error:badarg ->
      Body2 = Recevied,
      StackList = erlang:get_stacktrace(),
      {ModuleF, FunctionF, ArityF, StackHistory} = lists:nth(1, StackList),
      {ModuleF2, FunctionF2, ArityF2, StackHistory2} = lists:nth(2, StackList),
      {500,jsx:encode([{<<"result">>, -500}, {<<"body">>, <<"알 수 없는 에러입니다."/utf8>>}])};

    Er:no_session ->
      {404,jsx:encode([{<<"result">>, -101}, {<<"message">>, <<"세션이 만료되었습니다."/utf8>>}])};
    Er:invalid_data ->
      {404,jsx:encode([{<<"result">>, -101}, {<<"message">>, <<"세션키가 존재하지 않습니다."/utf8>>}])};
    exit:Error ->
      ?ERRORL("NO PROC1:~p:~p!", [Error, {Api, Category}]),
      StackList = erlang:get_stacktrace(),
      {ModuleF, FunctionF, ArityF, StackHistory} = lists:nth(1, StackList),
      {ModuleF2, FunctionF2, ArityF2, StackHistory2} = lists:nth(2, StackList),
      ?ERRORL("Error while process:Er:~p,Error:~p,StackT1:~p", [tw_util:to_list("Exit"), Error, StackList]),
      {500,jsx:encode([{<<"result">>,-501}, {<<"body">>, <<"알 수 없는 에러입니다."/utf8>>}])};
    Er:Error ->
      Body2 = Recevied,
      StackList = erlang:get_stacktrace(),
      {ModuleF, FunctionF, ArityF, StackHistory} = lists:nth(1, StackList),
      {ModuleF2, FunctionF2, ArityF2, StackHistory2} = lists:nth(2, StackList),
      ?ERRORL("Error while process:Er:~p,Error:~p,StackT1:~p", [tw_util:to_list(Er), Error, StackList]),
      %    tw_db_log_manager:insert_error_log_s3({"error", IP, io_lib:fwrite("Error while process:Er:~p,Error:~p,StackT1:~p,StackT2:~p", [tw_util:to_list(Er), Error, StackHistory, StackHistory2])}),
      {500,jsx:encode([{<<"result">>, -502}, {<<"body">>, <<"알 수 없는 에러입니다."/utf8>>}])}
  end.



%%-----------[실제 구현]------------

%% @doc
%% Description: 다중 API를 처리하기 위한 부분
%% parm:[Category리스트,Api리스트,Data)
%% Return: 처리 결과값.
handleMutipleApi([H0 | T0],[H | T], [H2 | T2], Map) ->

  Bin1 = handle(list_to_binary(H0),list_to_binary(H), list_to_binary(H2), "OPT", Map),
  Bin2 = handleMutipleApi(T0,T, T2, Map),
  lists:append([tw_util:to_list(Bin1), ",", tw_util:to_list(Bin2)]);

handleMutipleApi([],[], _, _) ->
  "{}".




handle(ApiVersion,Category, API, WHAT, _) ->
  ?ERRORL("Received ~p/~p/~p but category does not exist.~n", [ApiVersion,Category, API, WHAT]),

  {404,jsx:encode([{<<"result">>, -403}, {<<"message">>, <<"버전 또는 카테고리가 존재하지 않습니다."/utf8>>}])}.

terminate(_Reason, _Req, _State) ->
  ok.