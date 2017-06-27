%%%-------------------------------------------------------------------
%%% @author psw
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. 4월 2016 오후 5:41
%%%-------------------------------------------------------------------
-module(tw_moigo_trip_log_manager).
-author("psw").

-behaviour(gen_server).

%% API
-export([start_link/0]).
-include("src/include/db_record.hrl").
-include("src/include/tw_macro.hrl").
%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,

  terminate/2,

  code_change/3]).

-export([
  %insert_log_to_s3/1,
  insert_db_log/5,
  % %insert_error_log_s3/1,
  insert_admin_log/5,
  onTerminate/0, is_terminated/0, insert_api_log_v2/1, insert_error_log_v2/1, insert_acount_log_v2/3, flush_log/0]).

-define(SERVER, ?MODULE).

-record(state, {log_raw_size, log_size, api_log_size, error_log_size, is_terminated = false}).

%%%===================================================================
%%% Heleper
%%%===================================================================

upload_temlogfile_to_s3(FileNameT) ->
  %%기본로그 커밋
  FileName = tw_util:to_list(FileNameT),
  Time = tw_datetime:datetime_to_record(calendar:local_time()),
  Today = lists:append([tw_util:to_list(Time#tw_datetime.year), "_", tw_util:to_list(Time#tw_datetime.month), "_",
    string:right(integer_to_list(Time#tw_datetime.day), 2, $0)]),
  InstanceId = tw_util:to_list(tw_util:get_instance_id()),
  FileNameTemLog1 = lists:append(["log_v2/temlog/", Today, "/", InstanceId, "/", FileName]),
  FileRefLog1 = file:read_file(lists:append(["log/", FileName])),

  case FileRefLog1 of
    %%파일이 있다면 업로드 한다.
    {ok, File} -> tw_s3:upload_log_to_s3(FileNameTemLog1, File);
    _ -> ok
  end.

%%%===================================================================
%%% API
%%%===================================================================
insert_acount_log_v2(UserUniqueId, Type, Json) ->
  Time = tw_datetime:datetime_to_record(calendar:local_time()),

  Today = lists:append([tw_util:to_list(Time#tw_datetime.year), "_", tw_util:to_list(Time#tw_datetime.month), "_",
    string:right(integer_to_list(Time#tw_datetime.day), 2, $0)]),

  ServerPosition = tw_util:get_server_position(),
  UserUniqueIdStr = tw_util:to_list(UserUniqueId),
  TypeStr = tw_util:to_list(Type),
  Suffix = lists:append([Today, "_", tw_util:to_list(node()), "_", tw_util:to_list(Time#tw_datetime.hour), "_", tw_util:to_list(Time#tw_datetime.min)]),
  FileName = case ServerPosition of
               local ->
                 lists:append(["log_v2/local/log_account/", TypeStr, "/", UserUniqueIdStr, "/", Suffix]);
               dev ->
                 lists:append(["log_v2/dev/log_account/", TypeStr, "/", UserUniqueIdStr, "/", Suffix]);
               stage ->
                 lists:append(["log_v2/stage/log_account/", TypeStr, "/", UserUniqueIdStr, "/", Suffix]);
               real ->
                 lists:append(["log_v2/real/log_account/", TypeStr, "/", UserUniqueIdStr, "/", Suffix])
             end,
  tw_s3:upload_log_to_s3(FileName, Json).

insert_api_log_v2(Json) ->
  gen_server:cast(?MODULE, {insert_api_log_v2, Json}).


insert_error_log_v2(Json) ->
  gen_server:cast(?MODULE, {insert_error_log_v2, Json}).





%
%% @doc s3에 기록할 에러로그 등록
%%insert_error_log_s3({Type, IPAddress, Contents} = Tuple) ->
%%  gen_server:cast(?MODULE, {insert_error_log_s3, Tuple}).

%%insert_error_log_s3_with_userinfo({Type, UserIdx, ClientInfo, IPAddress, Contents} = Tuple) ->
%%  gen_server:cast(?MODULE, {insert_error_log_s32, Tuple}).



%% @doc s3에 기록할 기본 로그 등록
%%insert_log_to_s3({Type, UserIdx, IPAddress, ClientInfo, ClientType, Action, Contents} = Tuple) ->
%%  insert_log_to_s3({Type, UserIdx, tw_user:get_unique_id(UserIdx), IPAddress, ClientInfo, ClientType, Action, Contents});
%%insert_log_to_s3({Type, UserIdx, UserUniqueId, IPAddress, ClientInfo, ClientType, Action, Contents} = Tuple) ->
%%  gen_server:cast(?MODULE, {insert_log_to_s3, Tuple}).

%% @doc db에 기록할 로그 등록
insert_db_log(Type, UserIdx, IPAddress, Action, Contents) ->
  gen_server:cast(?MODULE, {insert_db_log, tw_util:to_binary(Type), UserIdx, IPAddress, Action, Contents}).

%% @doc db에 admin log등록
insert_admin_log(Type, AdminId, IPAddress, Action, Contents) ->
  gen_server:cast(?MODULE, {insert_admin_log, tw_util:to_binary(Type), AdminId, IPAddress, Action, Contents}).


%% @doc AutoScale로 인해 셧다운시 처리
onTerminate() ->
  %%1 아직 업로드 되지 않은 로그 모두를 업로드 시킨다
  gen_server:cast(?MODULE, {on_terminate}).
%% @doc AutoScale로 인해 셧다운시 처리


%%flush_all() ->
%%  gen_server:call(?MODULE, {flush_all}, infinity).
%%

is_terminated() ->
  gen_server:call(?MODULE, is_terminated).
%% @doc 현재 업로드 되지 않은 로그를 업로드 시킨다.
flush_log() ->
  Time = tw_datetime:datetime_to_record(calendar:local_time()),
  %로그가 업로드된 시간을 로그 파일명으로 사용할것이다.
  %우선 로그가 업로드될 폴더는 하루 단위로 구성하기 때문에 오늘을 폴더명으로 지정한다.
  Today = lists:append([tw_util:to_list(Time#tw_datetime.year), "/", tw_util:to_list(Time#tw_datetime.month), "/",
    string:right(integer_to_list(Time#tw_datetime.day), 2, $0)]),
  %파일명은 log/log/오늘날자_시간.log

  ServerPosition = tw_util:get_server_position(),

  Suffix = lists:append([Today, "/", tw_util:to_list(node()), "_", tw_util:to_list(Time#tw_datetime.hour), "_", tw_util:to_list(Time#tw_datetime.min)]),
  FileName = case ServerPosition of
               local ->
                 lists:append(["log_v2/local/log_api/", Suffix]);
               dev ->
                 lists:append(["log_v2/dev/log_api/", Suffix]);
               stage ->
                 lists:append(["log_v2/stage/log_api/", Suffix]);
               real ->
                 lists:append(["log_v2/real/log_api/", Suffix])
             end,
  DB_LOG_PATH = "log/api_log_v2.log",
  FileRes = file:read_file(DB_LOG_PATH),
  case FileRes of
    %%파일이 있다면 업로드 한다.
    {ok, File} -> tw_s3:upload_log_to_s3(FileName, File);
    _ -> ok
  end,
  %에러로그도 기본 로그와 마찮가지.
  FileName2 = case ServerPosition of
                local ->
                  lists:append(["log_v2/local/log_api_error/", Suffix]);
                dev ->
                  lists:append(["log_v2/dev/log_api_error/", Suffix]);
                stage ->
                  lists:append(["log_v2/stage/log_api_error/", Today, "/", Suffix]);
                real ->
                  lists:append(["log_v2/real/log_api_error/", Today, "/", Suffix])
              end,
  DB_LOG_PATH2 = "log/error_log_v2.log",
  FileRes2 = file:read_file(DB_LOG_PATH2),
  case FileRes of
    {ok, File2} -> tw_s3:upload_log_to_s3(FileName2, File2);
    _ -> ok
  end,
  %업로드한 파일을 삭제한다.
  file:write_file(DB_LOG_PATH, "", []),
  file:write_file(DB_LOG_PATH2, "", []).
%%
%%flush_and_upload_log() ->
%%
%%
%%  %%s3로그를 업로드
%%  Time = tw_datetime:datetime_to_record(calendar:local_time()),
%%  %로그가 업로드된 시간을 로그 파일명으로 사용할것이다.
%%  %우선 로그가 업로드될 폴더는 하루 단위로 구성하기 때문에 오늘을 폴더명으로 지정한다.
%%  Today = lists:append([tw_util:to_list(Time#tw_datetime.year), "_", tw_util:to_list(Time#tw_datetime.month), "_",
%%    string:right(integer_to_list(Time#tw_datetime.day), 2, $0)]),
%%  %파일명은 log/log/오늘날자_시간.log
%%  FileName = lists:append(["log/log_v2/", Today, "/", tw_util:to_list(node()), "_", tw_util:to_list(Time#tw_datetime.hour)]),
%%  DB_LOG_PATH = "log/api_log_v2.log",
%%  FileRes = file:read_file(DB_LOG_PATH),
%%  case FileRes of
%%    %%파일이 있다면 업로드 한다.
%%    {ok, File} -> tw_s3:upload_log_to_s3(FileName, File);
%%    _ -> ok
%%  end,
%%
%%  %에러로그도 기본 로그와 마찮가지.
%%  FileName2 = lists:append(["log/error_v2/", Today, "/", tw_util:to_list(node()), "_", tw_util:to_list(Time#tw_datetime.hour)]),
%%
%%  DB_LOG_PATH2 = "log/error_log_v2.log",
%%
%%  FileRes2 = file:read_file(DB_LOG_PATH2),
%%  case FileRes of
%%    {ok, File2} -> tw_s3:upload_log_to_s3(FileName2, File2);
%%    _ -> ok
%%  end,
%%
%%  %업로드한 파일을 삭제한다.
%%
%%  file:write_file(DB_LOG_PATH, "", []),
%%  file:write_file(DB_LOG_PATH2, "", []),
%%
%%
%%  %%db로그 커밋
%%  %tw_db:commit_log(),
%%
%%  %%
%%  upload_temlogfile_to_s3("twm_info.log"),
%%  upload_temlogfile_to_s3("twm_info.log.0"),
%%  upload_temlogfile_to_s3("twm_info.log.1"),
%%  upload_temlogfile_to_s3("twm_info.log.2"),
%%  upload_temlogfile_to_s3("twm_info.log.3"),
%%  upload_temlogfile_to_s3("twm_error.log"),
%%  upload_temlogfile_to_s3("twm_error.log.0"),
%%  upload_temlogfile_to_s3("twm_error.log.1"),
%%  upload_temlogfile_to_s3("twm_error.log.2"),
%%  upload_temlogfile_to_s3("twm_error.log.3"),
%%  ok.

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
  %%일정 주기마다 모아둔 로그를 flush한다.

  ServerPosition = tw_util:env(position, position),

  ?INFOL("ServerPosition:~p", [ServerPosition]),

  DBNODE = case ServerPosition of
             real ->
               erlang:send_after(15000, self(), {schedule_flush});
             _ -> ok
           end,
  {ok, #state{log_size = 1, log_raw_size = 0, api_log_size = 0, error_log_size = 0}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).

handle_call({schedule_flush}, _From, State) ->
  {_, NewState} = handle_info({schedule_flush}, State),
  {reply, ok, State};


handle_call(is_terminated, _From, State) ->
  {reply, State#state.is_terminated, State};

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

handle_cast({insert_error_log_v2, JSON}, State) ->
  %%s3로그가 저장된 path
  %Res = file:write_file("log/error_log_v2.log", io_lib:fwrite("~s~n", [JSON]), [append]),
  %Num = State#state.log_size + 1,
  %State1 = State#state{log_size = Num},
  {noreply, State};


handle_cast({insert_api_log_v2, JSON}, State) ->
  %%s3로그가 저장된 path
  D=spawn(tw_s3,upload_api_log_to_firehose,[<<JSON/binary,"\n">>]),
  %?WARNL("firehose list:~p",[D]),
  %Res = file:write_file("log/api_log_v2.log", io_lib:fwrite("~s~n", [JSON]), [append]),
  %Num = State#state.log_size + 1,

  {noreply, State};





handle_cast({schedule_flush}, State) ->
  {_, NewState} = handle_info({schedule_flush}, State),
  {noreply, NewState};
%%
%%handle_cast({insert_log_to_s3, Tuple}, State) ->
%%  {Type, UserIdx, UserUniqueId, IPAddress, ClientInfo, ClientType, Action, Contents} = Tuple,
%%
%%  ContentsT = case Contents of
%%                "" -> [{}];
%%                _ -> Contents
%%              end,
%%
%%  %%s3로그가 저장된 path
%%  DB_LOG_PATH = tw_util:env(db_log, s3_log_file_path),
%%
%%  %%JSON형식에 맞게 등록한다.
%%  Data = jsx:encode([
%%    {<<"who">>,
%%      [
%%        {<<"address">>, tw_util:to_binary(IPAddress)},
%%        {<<"user_idx">>, UserIdx},
%%        {<<"user_unique_id">>, tw_util:to_binary(UserUniqueId)},
%%        {<<"client_info">>, tw_util:to_binary(ClientInfo)},
%%        {<<"client_type">>, tw_util:to_binary(ClientType)}
%%      ]},
%%    {<<"what">>, ContentsT},
%%    {<<"how">>, tw_util:to_binary(Action)},
%%    {<<"when">>, tw_util:get_timestamp_in_mil()},
%%    {<<"date">>, tw_util:to_binary(tw_util:get_current_time_in_list())}
%%  ]),
%%
%%  %%  ?INFOL("writing file into server,Path:~p", [DB_LOG_PATH]),
%%  %파일을 쓰고 현재 로그 사이즈를 하나 올린다.
%%  %모아둔 로그는 upload_log_and_flush 를 통해 나중에 올라가게 된다.
%%  Res = file:write_file(DB_LOG_PATH, io_lib:fwrite("~s~n", [Data]), [append]),
%%  Num = State#state.log_size + 1,
%%  State1 = State#state{log_size = Num},
%%  {noreply, State1};






%%handle_cast({insert_error_log_s3, Tuple}, State) ->
%%  {Type, IPAddress, Contents} = Tuple,
%%
%%  DB_LOG_PATH = tw_util:env(db_log, s3_error_log_file_path),
%%
%%  Data = jsx:encode([
%%    {<<"who">>,
%%      [
%%        {<<"address">>, tw_util:to_binary(IPAddress)}
%%      ]},
%%    {<<"what">>, tw_util:to_binary(Contents)},
%%
%%    {<<"when">>, tw_util:get_timestamp_in_mil()},
%%    {<<"date">>, tw_util:to_binary(tw_util:get_current_time_in_list())}
%%  ]),
%%
%%  %%  ?INFOL("writing file into server,Path:~p", [DB_LOG_PATH]),
%%  Res = file:write_file(DB_LOG_PATH, io_lib:fwrite("~s~n", [Data]), [append]),
%%  Num = State#state.error_log_size + 1,
%%  State1 = State#state{error_log_size = Num},
%%  {noreply, State1};
%%

handle_cast({on_terminate}, State) ->


  State1 = State#state{log_size = 0, error_log_size = 0, api_log_size = State#state.api_log_size, is_terminated = true},

  flush_log(),
  upload_temlogfile_to_s3("twm_info.log"),
  upload_temlogfile_to_s3("twm_info.log.0"),
  upload_temlogfile_to_s3("twm_info.log.1"),
  upload_temlogfile_to_s3("twm_info.log.2"),
  upload_temlogfile_to_s3("twm_info.log.3"),
  upload_temlogfile_to_s3("twm_error.log"),
  upload_temlogfile_to_s3("twm_error.log.0"),
  upload_temlogfile_to_s3("twm_error.log.1"),
  upload_temlogfile_to_s3("twm_error.log.2"),
  upload_temlogfile_to_s3("twm_error.log.3"),
  {noreply, State1};

handle_cast({insert_admin_log, Type, AdminId, IPAddress, Action, Contents}, State) ->


  tw_db:insert_admin_log(AdminId, Action, Contents, Type, IPAddress),
  {noreply, State};
%%
handle_cast({insert_db_log, Type, UserIdx, IPAddress, Action, Contents}, State) ->

  if (Action == <<"check_session">>) or (Action == <<"get_image">>) or (Action == <<"get_friend_info">>) or (Action == <<"get_contact">>) ->
    {noreply, State};
    true ->
      if (Action == <<"create_notice">>) or (Action == <<"delete_notice">>) or (Action == <<"send_chat">>) or (Action == <<"send_group_chat">>) or (Action == <<"register_schedule">>) or (Action == <<"edit_schedule">>) or (Action == <<"delete_schedule">>) or (Action == <<"upload_image">>) or (Action == <<"upload_file">>) or (Action == <<"change_nickname">>) or (Action == <<"change_nickname">>) or (Action == <<"make_group">>) ->
        tw_db:update_last_update(UserIdx);
        true ->
          ok
      end,

      %db에 저장될 로그를 임시로 담아두는 장소
      DB_LOG_PATH = tw_util:env(db_log, insert_file_path),

      %로그가 몇개 쌓인후에 flush할것인지에 관련한 Variable.
      %sys.config에 정의되어 있다.
      DB_LOG_FLUSH_NUM = tw_util:env(db_log, flush_num),
      Data = {Type, UserIdx, Action, Contents},

      %file형식으로 만든다음에 파일을 업로드하여 db에 insert할 것이기 때문에 형식에 맞춰서 써준다.
      %% ?INFOL("writing file into server,Path:~p",[DB_LOG_PATH]),
      Res = file:write_file(DB_LOG_PATH, io_lib:fwrite("~s#~s#~s#~s#~s#~s#~s$", [(tw_util:to_list(node())), tw_util:to_list(Type), tw_util:to_list(UserIdx), tw_util:to_list(IPAddress), tw_util:to_list(Action), tw_util:to_list(Contents), tw_util:get_current_time_in_list()]
      ), [append]),


      Num = State#state.api_log_size + 1,

      %%현재 로그 숫자가 일정 숫자 이상 쌓이거나 error로그일경우, 커밋한다.
      Num2 = if ((Num >= 1) or (Type == <<"error">>)) ->
        tw_db:commit_log(),
        Res = file:write_file(DB_LOG_PATH, "", []),
        0;
               true ->
                 Num
             end,
      State1 = State#state{api_log_size = Num2},
      {noreply, State1}
  end;



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


handle_info({schedule_flush}, State) ->


  Time = tw_datetime:datetime_to_record(calendar:local_time()),

  ?WARNL("upload preparing!", []),
  ReturnRes = case State#state.log_size of
                0 ->
                  %로그 사이즈가 0:로그가 없다면, 그냥 스킵
                  %약 한시간마다 업로드
                  erlang:send_after(3650000, self(), {schedule_flush});

                _ ->
                  flush_log(),

                  ?INFOL("S3 LOG UPLOADING! SIZE:~p,ErrorLOGSize:~p", [State#state.log_size, State#state.error_log_size]),
                  %파일명은 log/log/오늘날자_시간.log


                  State1 = State#state{log_size = 0, error_log_size = 0, api_log_size = State#state.api_log_size},
                  %약 한시간후에 같은 작업 반복 마다 업로드한다.
                  erlang:send_after(3650000, self(), {schedule_flush})

              end,
  {noreply, State};

handle_info(_Info, State) ->
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
