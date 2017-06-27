%%%-------------------------------------------------------------------
%%% @author psw
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. 1월 2016 오후 1:48
%%%-------------------------------------------------------------------
-author("psw").
-define(PRINT(Format, Args),
  io:format(Format, Args)).

-define(PRINT_MSG(Msg),
  io:format(Msg)).
-define(SECTOMICRO(Second),
  1000000 * Second).


-define(INFOL(Msg, Args),
  lager:info(lists:append(["-----(<>[", Msg, "]<>)-----"]), Args)).
-define(WARNL(Msg, Args),
  lager:warning(lists:append(["-----(<>[", Msg, "]<>)-----"]), Args)).

-define(ERRORL(Msg, Args),
  lager:error(lists:append(["-----(<>[", Msg, "]<>)-----"]), Args)).


-define(UNEXPECTED_REQ(Req, State),
  (begin
     lager:error("Unexpected Request: ~p", [Req]),
     {reply, {error, unexpected_request}, State}
   end)).

-define(UNEXPECTED_MSG(Msg, State),
  (begin
     lager:error("Unexpected Message: ~p", [Msg]),
     {noreply, State}
   end)).

-define(UNEXPECTED_INFO(Info, State),
  (begin
     lager:error("Unexpected Info: ~p", [Info]),
     {noreply, State}
   end)).


%% 디버깅용 출력을 위한 매크로.
-ifdef(DEBUG_MODE).
-define(DEBUG(Format, Args),
  (begin
     io:format("~nDebugMessage Module: ~p, Line: ~p~n", [?MODULE, ?LINE]),
     io:format(Format, Args)
   end)).
-define(DEBUG_LIST(List, Format),
  (begin
     lists:foreach(
       fun
         (Args) when is_tuple(Args) ->
           ?DEBUG(Format, [element(I, Args) || I <- lists:seq(1, tuple_size(Args))] );
         (Args) when is_list(Args) ->
           ?DEBUG(Format, Args );
         (Args) ->
           ?DEBUG(Format, [Args] )
       end,
       List)
   end)).
-else.
-define(DEBUG(Format, Args), true).
-define(DEBUG_LIST(Format, Args), true).
-endif.