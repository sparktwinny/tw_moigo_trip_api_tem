%%%-------------------------------------------------------------------
%%% @author psw
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 19. 12월 2015 오후 8:37
%%%-------------------------------------------------------------------
-module(tw_reloader).
-author("psw").
-include("src/include/tw_macro.hrl").
-include_lib("kernel/include/file.hrl").
%% API
-export([start/0, loop/0, reload/1]).

start() ->
  io:format("Reloading start~n"),
  ets:new(loaded_file_list, [public, named_table]),
  [add_files(Filename)
    || {Module, Filename} <- code:all_loaded(), is_list(Filename)],
  Pid = spawn(tw_reloader, loop, []),
  timer:send_interval(timer:seconds(1), Pid, check).

%%

%% @doc
%% Description: 해당 모듈을 담은 파일명과 마지막 작성시간을 loaded_file_list에 저장한다.
%% Parameter:파일명)
%% Return:ok.
add_files(Filename) ->
  case file:read_file_info(Filename) of
    {ok, #file_info{mtime = MTime}} ->

      %%파일명을 마지막 / 기준으로 잘라 파일의 경로를 제외한 이름만으로 저장한다.
      case re:run(Filename, "[^/]+$") of
        {match, RangeList} ->
          {From, Length} = lists:nth(1, RangeList),
          Name = string:substr(Filename, From + 1, Length),
          %% io:format("added name:~p,~n", [Name]),
          ets:insert(loaded_file_list, {Name, MTime});
        _ -> ok
      end;
    _ -> ok
  end.

%% @doc
%% Description: 파일이 다시 로딩되었는지 검사.
%% Parameter:파일명, 마지막 알려진 작성시간)
%% Return: 처리 결과값.
is_refreshed(Filename, MTime) ->

  %%우선 우리는 파일 경로가 아닌 파일명으로만 살펴보기 때문에 잘라준다.
  case re:run(Filename, "[^/]+$") of
    {match, RangeList} ->
      {From, Length} = lists:nth(1, RangeList),
      Name = string:substr(Filename, From + 1, Length),
      %%io:format("name:~p,~n", [Name]),
      ResultList = ets:lookup(loaded_file_list, Name),
      %%한번도 로딩된적 없는 파일이다. 새로 추가된 파일일것이다. 저장한다.
      case length(ResultList) of
        0 ->
          add_files(Filename),
          false;

        _ ->
        %%시간을 비교해서
          {NN, Time} = lists:nth(1, ResultList),

          if

            (Time /= MTime) ->

             %% io:format("Time:~p,MTIMEL~p,~n",[Time,MTime]),
              %%새로운 파일이라면 기존 정보를 갱신한다.
              ets:insert(loaded_file_list, {Name, MTime}),

              refreshed;
            true ->
              false
          end
      end;
    _ -> false
  end.





loop() ->
  receive
    check ->
      %% io:format("checking updates.213123..~n"),
      To = erlang:localtime(),
      [check(Module, Filename)
        || {Module, Filename} <- code:all_loaded(), is_list(Filename)],
      loop();
    update ->
      ?MODULE:loop();
    Other ->
      io:format("~p~n", [Other]),
      loop()


  end.

check( Module, Filename) ->


  %%?PRINT("filename:~p~n",[Filename]),
  case file:read_file_info(Filename) of
    {ok, #file_info{mtime = MTime}} ->


      Res=is_refreshed(Filename, MTime),

      case Res of
        refreshed ->

          reload(Module);
        false -> pass;
      _->
       %% io:format("Res ~p ...", [Res]),
        pass
      end;
    _ ->
      pass
  end.
reload(Module) ->
  ?WARNL("Loading New Module:~p", [Module]),
  code:purge(Module),
  code:load_file(Module),
  onReload(Module),
ok.


%%모듈을 reload할때 커스터마이징
onReload(Module)->
  case Module of
    tw_user->
      tw_user:send_module_update();
    tw_db->
      ets:delete_all_objects(prepared_statement);
    _->
      ok
  end.
