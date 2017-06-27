%%%-------------------------------------------------------------------
%%% @author psw
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%% 시스템이 비정상적인 리소스 소모를 하거나 예상되는 기간보다 많은 CPU기간을 잡아먹은 경우 Notify하는 모듈

%%% @end
%%% Created : 11. 3월 2016 오후 10:14
%%%-------------------------------------------------------------------

-module(tw_monitor).
-define(PROCESS_GC, [memory,
  total_heap_size,
  heap_size,
  stack_size,
  min_heap_size]).
%fullsweep_after]).


-define(PROCESS_INFO, [initial_call,
  current_function,
  registered_name,
  status,
  message_queue_len,
  group_leader,
  priority,
  trap_exit,
  reductions,
  %%binary,
  last_calls,
  catchlevel,
  trace,
  suspending,
  sequential_trace_token,
  error_handler]).


-author("psw").

-include("src/include/tw_macro.hrl").
-behavior(gen_server).



-export([start_link/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3]).

-record(state, {tickref, events = [], tracelog}).
-define(LOG(Msg, ProcInfo),
  lager:warning([{sysmon, true}], "~s~n~p", [WarnMsg, ProcInfo])).

-define(LOG(Msg, ProcInfo, PortInfo),
  lager:warning([{sysmon, true}], "~s~n~p~n~p", [WarnMsg, ProcInfo, PortInfo])).

%%------------------------------------------------------------------------------
%% @doc Start system monitor
%% @end
%%------------------------------------------------------------------------------
-spec start_link(Opts :: list(tuple())) ->
  {ok, pid()} | ignore | {error, term()}.
start_link(Opts) ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [Opts], []).

%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

init([Opts]) ->

  erlang:system_monitor(self(), parse_opt(Opts)),
  {ok, TRef} = timer:send_interval(timer:seconds(1), reset),



  %%TODO: don't trace for performance issue.
  %%{ok, TraceLog} = start_tracelog(proplists:get_value(logfile, Opts)),
  {ok, #state{tickref = TRef}}.

parse_opt(Opts) ->

  parse_opt(Opts, []).
parse_opt([], Acc) ->

  Acc;
parse_opt([{long_gc, false}|Opts], Acc) ->
  parse_opt(Opts, Acc);
parse_opt([{long_gc, Ms}|Opts], Acc) when is_integer(Ms) ->
  parse_opt(Opts, [{long_gc, Ms}|Acc]);
parse_opt([{long_schedule, false}|Opts], Acc) ->
  parse_opt(Opts, Acc);
parse_opt([{long_schedule, Ms}|Opts], Acc) when is_integer(Ms) ->
  parse_opt(Opts, [{long_schedule, Ms}|Acc]);
parse_opt([{large_heap, Size}|Opts], Acc) when is_integer(Size) ->
  parse_opt(Opts, [{large_heap, Size}|Acc]);
parse_opt([{busy_port, true}|Opts], Acc) ->
  parse_opt(Opts, [busy_port|Acc]);
parse_opt([{busy_port, false}|Opts], Acc) ->
  parse_opt(Opts, Acc);
parse_opt([{busy_dist_port, true}|Opts], Acc) ->
  parse_opt(Opts, [busy_dist_port|Acc]);
parse_opt([{busy_dist_port, false}|Opts], Acc) ->
  parse_opt(Opts, Acc);
parse_opt([_Opt|Opts], Acc) ->
  parse_opt(Opts, Acc).

handle_call(Req, _From, State) ->

  ?UNEXPECTED_REQ(Req, State).

handle_cast(Msg, State) ->
  ?UNEXPECTED_MSG(Msg, State).

handle_info({monitor, Pid, long_gc, Info}, State) ->

    WarnMsg = io_lib:format("long_gc warning: pid = ~p, info: ~p", [Pid, Info]),
    ?LOG(WarnMsg, procinfo(Pid)),
    {noreply, State};


handle_info({monitor, Pid, long_schedule, Info}, State) when is_pid(Pid) ->

    WarnMsg = io_lib:format("long_schedule warning: pid = ~p, info: ~p", [Pid, Info]),
    ?LOG(WarnMsg, procinfo(Pid)),
  {noreply, State};

handle_info({monitor, Port, long_schedule, Info}, State) when is_port(Port) ->

    WarnMsg  = io_lib:format("long_schedule warning: port = ~p, info: ~p", [Port, Info]),
    ?LOG(WarnMsg, erlang:port_info(Port)),
  {noreply, State};

handle_info({monitor, Pid, large_heap, Info}, State) ->

    WarnMsg = io_lib:format("large_heap warning: pid = ~p, info: ~p", [Pid, Info]),
    ?LOG(WarnMsg, procinfo(Pid)),
  {noreply, State};

handle_info({monitor, SusPid, busy_port, Port}, State) ->

    WarnMsg = io_lib:format("busy_port warning: suspid = ~p, port = ~p", [SusPid, Port]),

  {noreply, State};

handle_info({monitor, SusPid, busy_dist_port, Port}, State) ->

    WarnMsg = io_lib:format("busy_dist_port warning: suspid = ~p, port = ~p", [SusPid, Port]),
  ?LOG(WarnMsg, procinfo(SusPid), erlang:port_info(Port)),

  {noreply, State};

handle_info(reset, State) ->
  {noreply, State#state{events = []}};

handle_info(Info, State) ->
  {noreply, State}.

terminate(_Reason, #state{tickref = TRef, tracelog = TraceLog}) ->
  timer:cancel(TRef).


code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

suppress(Key, SuccFun, State = #state{events = Events}) ->
  case lists:member(Key, Events) of
    true  ->
      {noreply, State};
    false ->
      SuccFun(),
      {noreply, State#state{events = [Key|Events]}}
  end.

procinfo(Pid) ->
  case {get_process_info(Pid), get_process_gc(Pid)} of
    {undefined, _} -> undefined;
    {_, undefined} -> undefined;
    {Info, GcInfo} -> Info ++ GcInfo
  end.




get_process_info() ->
  [get_process_info(Pid) || Pid <- processes()].
get_process_info(Pid) when is_pid(Pid) ->
  process_info(Pid, ?PROCESS_INFO).

get_process_gc() ->
  [get_process_gc(Pid) || Pid <- processes()].
get_process_gc(Pid) when is_pid(Pid) ->
  process_info(Pid, ?PROCESS_GC).

