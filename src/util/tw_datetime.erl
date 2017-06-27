%%%-------------------------------------------------------------------
%%% @author psw
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 26. 6월 2017 오후 6:56
%%%-------------------------------------------------------------------
-module(tw_datetime).
-author("psw").
-include("src/include/db_record.hrl").

-include("src/include/tw_macro.hrl").

%-record(tw_datetime, {year = 0, month = 0, day = 0, hour = 0, min = 0, sec = 0}).
%----[time]----
-export([
  get_current_time_in_unix_timestamp/0,
  get_current_time_in_unix_timestamp_in_mils/0,
  iso_8601_basic_time/1,
  iso_8601_basic_time/0,
  timestamp_to_datetime/1,
  get_datetime_now_in_kst/0,
  get_datetime_now_in_utc/0,
  add_seconds_to_datetime/2,
  shift_datetime/3,
  compare_datetime/2,
datetime_to_record/1,
  get_datetime_to_list/1
]).


get_current_time_in_unix_timestamp() ->
  {Mega, Secs, _} = erlang:timestamp(),
  Timestamp = Mega * 1000000 + Secs,
  Timestamp.

get_current_time_in_unix_timestamp_in_mils() ->

  {Mega, Secs, Micro} = erlang:timestamp(),
  Timestamp = Mega * 1000000 + Secs,
  (Timestamp * 1000) + (Micro div 1000).

iso_8601_basic_time(NowTime) ->
  {{Year, Month, Day}, {Hour, Min, Sec}} = calendar:now_to_universal_time(NowTime),
  lists:flatten(io_lib:format(
    "~4.10.0B-~2.10.0B-~2.10.0BT~2.10.0B:~2.10.0B:~2.10.0BZ",
    [Year, Month, Day, Hour, Min, Sec])).
iso_8601_basic_time() ->
  {{Year, Month, Day}, {Hour, Min, Sec}} = calendar:now_to_universal_time(os:timestamp()),
  lists:flatten(io_lib:format(
    "~4.10.0B~2.10.0B~2.10.0BT~2.10.0B~2.10.0B~2.10.0BZ",
    [Year, Month, Day, Hour, Min, Sec])).



timestamp_to_datetime(Second) ->
  BaseDate = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
  Seconds = BaseDate + (Second),
  {Date, _Time} = calendar:gregorian_seconds_to_datetime(Seconds),
  {Y, M, D} = Date, {H, MM, S} = _Time,
  {Date, _Time}.

get_datetime_now_in_kst() ->
  Now1 = get_current_time_in_unix_timestamp(),
  timestamp_to_datetime(Now1 + 32400).

get_datetime_now_in_utc() ->
  Now1 = get_current_time_in_unix_timestamp(),
  timestamp_to_datetime(Now1).


get_datetime_to_list(Datetime) ->
  {{Y, M, D}, {H, MM, S}} = Datetime,
  Return =
    tw_util:to_list(Y) ++ "-" ++ tw_util:to_list(M) ++ "-" ++ tw_util:to_list(D) ++ " " ++
    tw_util:to_list(H) ++ ":" ++ tw_util:to_list(MM) ++ ":" ++ tw_util:to_list(S),
  Return.

shift_datetime(DateTime, Value, Unit) ->

  case Unit of
    days -> add_days_to_datetime(DateTime, Value);
    seconds -> add_seconds_to_datetime(DateTime, Value)
  end.


add_seconds_to_datetime(DateTime, Seconds) ->
  calendar:gregorian_seconds_to_datetime(calendar:datetime_to_gregorian_seconds(DateTime) + Seconds).

add_days_to_datetime(DateTime, Days) ->
  calendar:gregorian_seconds_to_datetime(calendar:datetime_to_gregorian_seconds(DateTime) + Days * 86400).

compare_datetime(DateTime1, DateTime2) ->

  Seconds1 = calendar:datetime_to_gregorian_seconds(DateTime1),
  Seconds2 = calendar:datetime_to_gregorian_seconds(DateTime2),
  if (Seconds1 > Seconds2)
    -> 1;
    true ->
      if (Seconds1 =:= Seconds2) -> 0;
        true -> -1
      end
  end.


datetime_to_record({{Year, Month, Day}, {Hour, Min, Sec}}) ->
  #tw_datetime{year = Year, month = Month, day = Day, hour = Hour, min = Min, sec = Sec}.