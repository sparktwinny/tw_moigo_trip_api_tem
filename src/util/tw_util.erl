%%%-------------------------------------------------------------------
%%% @author psw
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 30. 12월 2015 오후 2:23
%%%-------------------------------------------------------------------
-module(tw_util).
-author("psw").
-include("src/include/db_record.hrl").
-export([]).
-include("src/include/tw_macro.hrl").
-import(lists, [reverse/1]).
-export([
  env/2,
  env/1,
  env/3,



  to_two_digit_list/1,
  to_integer/1,
  datetime_to_sec/1,
  new_tw_datetime/6,
  datetime_to_tw_datetime/1,
  local_time_to_datetime/1,
  datetime_time_difference/2,
  get_timestamp_to_mil/0,
  escape_uri/1,
  get_timestamp_in_mil/0,
  datetime_to_string/1,
  datetime_to_string_til_min/1,

  datetime_in_days/1,


  get_server_position/0,
  get_pure_unique_id/1,
  format_phone_number/1,
  %%---------[Thumbor]--------
  get_thumbor_url/3,
  get_thumbor_meta_url/3,
  %%-----------[ETC]---------

  ets_each/3,

  type_of/1,

  get_extention/1,
  
  time_check_start/0,
  time_check_end/0,
  time_check_end/1,
  is_laster_time/2,
  dump/3,
  get_server_ip/0,
  get_instance_id/0,



  check_interval/2,


  decode_web_safe_base64/1,
  encode_web_safe_base64/1,


  unicode_length/1,
  binary_trim/1, binary_trim/2,
  list_join/2, list_some/2,
  %%------[MD5]--------
  get_md5/1
]).

-export([
  partial/2,
  compose/1,
  record_to_list/2,
  record_to_json/2,
  list_to_record/3,
  record_assign/4,
  get_record_from_map/3,
  first_or/2,
  first_or_undefined/1
]).

-export([
  get_phone_number_in_format/1,
  get_phone_number_in_format/2]).
%----[etc]----
-export([
  warn_l/1,
  index_of/2,
  get_randome_num/0]
).

-export([
  bool/1,
  to_list/1,
  to_binary/1]
).


-export([
  download_file_to_path/2]).
-export([
  decode_web_safe_base64/1,
  encode_web_safe_base64/1]).
-export([
  get_db_recrod_to_tuple/2,
  bin_array_to_bin/1,
  bin_array_to_atom_array/1,
  get_ip_from_tuple/1]).
-export([
  get_server_ip/0,
  get_server_position/0,
  get_instance_id/0,
  get_unique_id_keyset_idx/2
]).
-export([
  get_thumbor_url/3,
  get_thumbor_meta_url/3

]).
%----[print memory]---

-export([
  print_current_memory/1,
  print_current_memory/0
]
).
-export([
  get_server_launch_time_in_sec/0
]
).


warn_l(Cont) ->
  ?WARNL("cont:~p", [Cont]),
  ok.
index_of(Item, List) -> index_of(Item, List, 1).
index_of(_, [], _) -> not_found;
index_of(Item, [Item | _], Index) -> Index;
index_of(Item, [_ | Tl], Index) -> index_of(Item, Tl, Index + 1).

get_randome_num() ->
  {A1, A2, A3} = now(),
  random:seed(A1, A2, A3),
  Num = random:uniform(1000000).



%----[converter]---


bool("0") -> false;
bool("1") -> true.

to_binary(Data) ->
  Type = type_of(Data),
  case Type of
    integer -> integer_to_binary(Data);
    float -> float_to_binary(Data);
    bitstring -> (Data);
    boolean -> atom_to_binary(Data, utf8);
    list -> list_to_binary(Data);
    atom ->
      case Data of
        undefined -> <<"undef">>;
        _ -> atom_to_binary(Data, utf8)
      end;
    tuple ->
      [H | T] = tuple_to_list(Data),
      case H of
        tw_datetime ->
          {tw_datetime, {{Year, Month, Day}, {Hour, Min, Sec}}} = Data,
          Str = lists:append([
            integer_to_list(Year), "-",
            string:right(integer_to_list(Month), 2, $0), "-",
            %%integer_to_list(MyDateTime#tw_datetime.month), "-",
            string:right(integer_to_list(Day), 2, $0), " ",
            string:right(integer_to_list(Hour), 2, $0), ":",
            string:right(integer_to_list(Min), 2, $0), ":",
            string:right(integer_to_list(Sec), 2, $0)]),
          list_to_binary(Str);
        _ -> <<"undef tubple">>
      end;
    _ ->
      <<"undef">>
  end.
to_integer(X) when is_list(X) ->
  try
    list_to_integer(X)
  catch
    Error:Er -> ?WARNL("List->Integer Conver Error:~p", [X]), 0
  end;
to_integer(X) when is_binary(X) ->
  try
    binary_to_integer(X)
  catch
    Error:Er ->
      ClientVersion = try
                        ?WARNL("Binary->Integer Conver Error:~p,~p,~p", [X, Error, Er]),
                        TT = binary_to_float(X),
                        TT2 = float_to_list(TT, [{decimals, 0}]),
                        list_to_integer(TT2)
                      catch
                        Er:Err -> ?WARNL("Binary->Integer Conver Error:~p", [X]),
                          0
                      end
  end;
to_integer(X) when is_integer(X) ->
  X;
to_integer(X) ->
  ?ERRORL("Invalid to_integer input:~p",[X]),
  throw(lists:append(["Invalid Type of ", to_list(type_of(X))])).

to_list(X) when is_bitstring(X) ->
  bitstring_to_list(X);
to_list(X) when is_float(X) ->
  float_to_list(X);
to_list(X) when is_pid(X) ->
  pid_to_list(X);
to_list(X) when is_atom(X) ->
  atom_to_list(X);
to_list(X) when is_integer(X) ->
  integer_to_list(X);
to_list(X) when is_binary(X) ->
  binary_to_list(X);
to_list(X) when is_list(X) ->
  X;
to_list(X) when is_tuple(X) ->
  io_lib:fwrite("~p", [X]);
to_list(X) ->
  ?ERRORL("Invalid to_integer input:~p",[X]),
  throw(lists:append(["Invalid Type of ", to_list(type_of(X))])).




print_current_memory(Text) ->
  [{total, TotalMem}, {processes, ProcessMem}, {processes_used, ProcessUsedMem}, {system, SystemMem}, {atom, AtomMem}, {atom_used, AtomUsedMem}, {binary, BinMem}, {code, CodeMem}, {ets, EtsMem}] = erlang:memory(),
  ?WARNL("Text:~p,SYSTEM MEM: Total:~.2fmb,Process:~.2fmb,ProcessUsed:~.2fmb,System:~.2fmb,Atom:~.2fmb,AtomUsed:~.2fmb,Binary:~.2fmb,Code:~.2fmb,Ets:~.2fmb", [Text,
    (TotalMem / 1048576),
    (ProcessMem / 1048576),
    (ProcessUsedMem / 1048576),
    (SystemMem / 1048576),
    (AtomMem / 1048576),
    (AtomUsedMem / 1048576),
    (BinMem / 1048576),
    (CodeMem / 1048576),
    (EtsMem / 1048576)]).
print_current_memory() ->
  [{total, TotalMem}, {processes, ProcessMem}, {processes_used, ProcessUsedMem}, {system, SystemMem}, {atom, AtomMem}, {atom_used, AtomUsedMem}, {binary, BinMem}, {code, CodeMem}, {ets, EtsMem}] = erlang:memory(),
  ?WARNL("SYSTEM MEM: Total:~.2fmb,Process:~.2fmb,ProcessUsed:~.2fmb,System:~.2fmb,Atom:~.2fmb,AtomUsed:~.2fmb,Binary:~.2fmb,Code:~.2fmb,Ets:~.2fmb", [
    (TotalMem / 1048576),
    (ProcessMem / 1048576),
    (ProcessUsedMem / 1048576),
    (SystemMem / 1048576),
    (AtomMem / 1048576),
    (AtomUsedMem / 1048576),
    (BinMem / 1048576),
    (CodeMem / 1048576),
    (EtsMem / 1048576)]).




%---[phonenumber]----


get_phone_number_in_format(PhoneNumberT) ->
  get_phone_number_in_format(PhoneNumberT, "82").
get_phone_number_in_format(PhoneNumberT, DefaultCountryCode) ->
  PhoneNumberBin = tw_util:to_binary(PhoneNumberT),
  <<H:8/bitstring, T/binary>> = PhoneNumberBin,
  case H of
    %첫 스트링이 +로시작한다면, 그대로 포팅. +는 제거한다.
    <<"+">> ->
      NewPhoneNumber = format_phone_number(T);
    _ ->
      %82를 붙이고 0을 제외시킨 다음 처리한다.
      NewPhoneNumber = tw_util:to_list(DefaultCountryCode) ++ format_phone_number(T)
  end.
format_phone_number(PhoneNumber) ->
  PhoneNumberList = tw_util:to_list(PhoneNumber),
  PhoneNumber0 = re:replace(PhoneNumberList, " ", "", [global, {return, list}]),
  PhoneNumber1 = re:replace(PhoneNumber0, "\\+", "", [global, {return, list}]),
  PhoneNumber2 = re:replace(PhoneNumber1, "-", "", [global, {return, list}]),
  PhoneNumber3 = re:replace(PhoneNumber2, "\\/", "", [global, {return, list}]).

%---[crypt]----


decode_web_safe_base64(RawData) ->
  case RawData of
    undefined -> undefined;
    <<"">> -> <<"">>;
    _ -> %%Raw1=binary:replace(RawData,<<"\n">>,<<"">>,[global]),
      Raw2 = binary:replace(RawData, <<"-">>, <<"+">>, [global]),
      Raw3 = binary:replace(Raw2, <<"_">>, <<"/">>, [global]),
      %% io:format("decodeed raw:~p~n", [Raw3]),
      base64:decode(Raw3)
  end.

encode_web_safe_base64(RawDataT) ->
  RawData = base64:encode(RawDataT),
  Raw2 = binary:replace(RawData, <<"+">>, <<"-">>, [global]),
  Raw3 = binary:replace(Raw2, <<"/">>, <<"_">>, [global]),
  Raw3.


%---[file]----

download_file_to_path(FilePath, URL) ->
  ?INFOL("Downloading file, from:~p,To~:p",[URL,FilePath]),
  ResultImage = httpc:request(tw_util:to_list(URL)),
  {ok, Res} = ResultImage,
  {SL, Headers, Body} = Res,
  ResultWrite = file:write_file(FilePath, Body, []),
  ResultWrite.


%---[parse]----



%% @doc
%% Description: JSON으로 만들기 쉽게 레코드를 변경
%% Parameter:
%% Return:TimeStampe의 {Mega,Secs,Micro}
get_db_recrod_to_tuple(Record, Fields) ->

  Seq = lists:seq(1, length(Fields)),
  [H | T] = tuple_to_list(Record),
  RecordData = [{atom_to_binary(lists:nth(Pos, Fields), utf8), to_binary(lists:nth(Pos, T))} || Pos <- Seq].

get_ip_from_tuple(Tuple) ->
  {A, B, C, D} = Tuple,
  lists:append([tw_util:to_list(A), ".", tw_util:to_list(B), ".", tw_util:to_list(C), ".", tw_util:to_list(D)]).



bin_array_to_bin([H | T]) ->
  bin_array_to_bin(T, H).
bin_array_to_bin([H | T], Result) ->
  Bin = <<Result/binary, ",", H/binary>>,
  bin_array_to_bin(T, Bin);
bin_array_to_bin([], Result) ->
  Result.
bin_array_to_atom_array(StringArray) ->
  Sum1 = [],
  ResultList1 = lists:foldl(
    fun(String, RR) ->
      Atom = binary_to_atom(String, utf8),
      case RR of
        [] -> [Atom];
        [A] -> [A | Atom]
      end
    end
    , Sum1, StringArray),
  ResultList1.

%---[getter]----


get_server_ip() ->
  case ets:lookup(global_variables, "instance_public_ip") of
    [{Key, Val}] ->
      Val;
    _ -> undef
  end.
get_server_position() ->
  tw_util:env(position, position).
get_instance_id() ->
  case ets:lookup(global_variables, "ec2_instance_id") of
    [{Key, Val}] ->
      Val;
    _ -> undef
  end.


get_unique_id_keyset_idx(UniqueId1, UniqueId2)  ->
  U1 = tw_util:to_list(UniqueId1),
  U2 = tw_util:to_list(UniqueId2),
  if (U1 < U2) ->
    lists:append([U1, "_", U2]);
    true ->
      lists:append([U1, "_", U2])
  end.


%---[thumbor]----


get_thumbor_url(Type, Parm, ImageAddress) ->

  Result = case Type of
             <<"resize">> ->
               {X, Y} = Parm,
               lists:append([to_list(X), "x", to_list(Y), "/", ImageAddress]);
             _ ->
               ImageAddress
           end,
  Res = crypto:hmac(sha, "Tjaqhdjqlalfzl", Result),
  Encryp = encode_web_safe_base64((Res)),
  Add = lists:append([to_list(Encryp), "/", Result]),
  Add.

get_thumbor_meta_url(Type, Parm, ImageAddress) ->
  Result = case Type of
             <<"resize">> ->
               {X, Y} = Parm,
               lists:append(["meta/", to_list(X), "x", to_list(Y), "/", ImageAddress]);
             _ ->
               lists:append(["meta/", ImageAddress])
           end,
  Res = crypto:hmac(sha, "Tjaqhdjqlalfzl", Result),
  Encryp = encode_web_safe_base64((Res)),
  Add = lists:append(["unsafe", "/", Result]),
  Add.




%%mnesia-----------
dump(ets, Table, Fun) ->
  dump(ets, Table, ets:first(Table), Fun, "").

dump(ets, _Table, '$end_of_table', _Fun, Str) ->
  Str;

dump(ets, Table, Key, Fun, Str) ->
  St2 = case ets:lookup(Table, Key) of
          [Record] ->
            SS = (to_list(Fun(Record))),

            Str ++ SS;
          [] -> Str
        end,

  (dump(ets, Table, ets:next(Table, Key), Fun, St2)).




%%----------------[MD5]---------------

get_md5(Data) ->
  MD5 = erlang:md5(Data),
  lists:flatten([io_lib:format("~2.16.0b", [B]) || <<B>> <= MD5]).






%%---------------[DATETIME 관련]---------------
%% @doc
%% Description: TimeStampe의 {Mega,Secs,Micro}형식
%% Parameter:
%% Return:TimeStampe의 {Mega,Secs,Micro}
get_timestamp_to_mil() ->
  erlang:timestamp().
%% @doc
%% Description: TimeStampe의 int
%% Parameter:
%% Return:TimeStampe의 mill까지의 int값
get_timestamp_in_mil() ->
  erlang:system_time(milli_seconds).


%% Description: emsql 내부에서 쓰는 datetime을 tw_datetime으로 바꾼다.
%% Parameter:[datetime])
%% Return: tw_datetime값
datetime_to_tw_datetime({datetime, {{Year, Month, Day}, {Hour, Min, Sec}}}) ->
  #tw_datetime{year = Year, month = Month, day = Day, hour = Hour, min = Min, sec = Sec};
datetime_to_tw_datetime({{Year, Month, Day}, {Hour, Min, Sec}}) ->
  #tw_datetime{year = Year, month = Month, day = Day, hour = Hour, min = Min, sec = Sec}.
local_time_to_datetime({{Year, Month, Day}, {Hour, Min, Sec}}) ->
  #tw_datetime{year = Year, month = Month, day = Day, hour = Hour, min = Min, sec = Sec}.


-spec datetime_time_difference(#tw_datetime{}, #tw_datetime{}) -> #tw_datetime{}.
%% Description: 두 tw_datetime의 값을 비교하여 그 차를 tw_datetime으로 나타낸 값을 구한다.

%% Parameter:[tw_datetime1,tw_datetime2]
%% Return: tw_datetime으로 표현된 두 시간의 차이
datetime_time_difference(Date1, Date2) ->

  Dt1 = datetime_to_sec(Date1),
  Dt2 = datetime_to_sec(Date2),


  %%각각의 초의 차를 구한다.
  TotalSecs = Dt1 - Dt2,
  %%% io:format("dt1:~p,dt2:~p diff:~p ~n", [Dt1, Dt2, TotalSecs]),
  %%  Year = TotalSecs div 31557600,
  %%  Sec1=TotalSecs rem 31557600,
  %%  Month = (Sec1) div 2592000,
  %%  Sec2=Sec1 rem 2592000,
  Sec2 = TotalSecs,
  Day = (Sec2) div 86400,
  Sec3 = Sec2 rem 86400,

  Hour = Sec3 div 3600,
  Min = (Sec3 rem 3600) div 60,
  Sec = (Sec3 rem 3600) rem 60,


  %%마지막으로 tw_datetime으로 변환한다.

  Dt = new_tw_datetime(0, 0, Day, Hour, Min, Sec),
  Dt.
check_interval({datetime, {{A, B, C}, {D, E, F}}} = NormalTime, Interval) ->
  check_interval(tw_util:datetime_to_tw_datetime(NormalTime), Interval);
check_interval({{A, B, C}, {D, E, F}} = NormalTime, Interval) ->
  check_interval(tw_util:datetime_to_tw_datetime(NormalTime), Interval);
check_interval(#tw_datetime{} = DateTime, #tw_datetime{} = Interval) ->


  CurrentTime = tw_util:datetime_to_tw_datetime(calendar:local_time()),
  Difference = tw_util:datetime_time_difference(CurrentTime, DateTime),


  Set = is_laster_time(Interval, Difference),
  if (Set) -> true;
    true -> false
  end.

is_laster_time(Date1, Date2) ->

  Dt1 = datetime_to_sec(Date1),
  Dt2 = datetime_to_sec(Date2),


  %%각각의 초의 차를 구한다.
  Secs = Dt1 - Dt2,


  if (Secs < 0) ->
    false;true -> true
  end.


%% Description: 새로운 tw_datetime을 만든다.
%% Parameter:[year,month,day,hour,min,sec]
%% Return: tw_datetime
new_tw_datetime(Year, Month, Day, Hour, Min, Sec) ->
  #tw_datetime{year = Year, month = Month, day = Day, hour = Hour, min = Min, sec = Sec}.

datetime_to_string(#tw_datetime{year = Year, month = Month, day = Day, hour = Hour, min = Min, sec = Sec} = DT) ->
  lists:append([
    tw_util:to_list(Year), "-", string:right(tw_util:to_list(Month), 2, $0), "-",
    string:right(tw_util:to_list(Day), 2, $0), " ", string:right(integer_to_list(Hour), 2, $0),
    ":", string:right(integer_to_list(Min), 2, $0), ":", string:right(integer_to_list(Sec), 2, $0)]).


datetime_to_string_til_min(#tw_datetime{year = Year, month = Month, day = Day, hour = Hour, min = Min, sec = Sec} = DT) ->
  lists:append([
    tw_util:to_list(Year), "-", string:right(tw_util:to_list(Month), 2, $0), "-",
    string:right(tw_util:to_list(Day), 2, $0), " ", string:right(integer_to_list(Hour), 2, $0),
    ":", string:right(integer_to_list(Min), 2, $0)]).


get_days_of_month(0) ->
  0;
get_days_of_month(Month) ->
  get_days_of_month(Month, 0).
get_days_of_month(1, Res) ->
  Res;
get_days_of_month(Mon, Res) ->
  MonthDay = case (Mon) of
               2 -> 31;
               3 -> 28;
               4 -> 31;
               5 -> 30;
               6 -> 31;
               7 -> 30;
               8 -> 31;
               9 -> 31;
               10 -> 30;
               11 -> 31;
               12 -> 30

             end,
  get_days_of_month(Mon - 1, Res + MonthDay).


datetime_to_sec(#tw_datetime{} = DT) ->

  MonthDay = get_days_of_month(DT#tw_datetime.month),
  %% io:format("monthSec:~p,~n", [MonthDay]),
  DT#tw_datetime.year * 31557600 + (DT#tw_datetime.day + DT#tw_datetime.year div 4 + MonthDay) * 86400 + DT#tw_datetime.hour * 3600 + DT#tw_datetime.min * 60 + DT#tw_datetime.sec.
%%윤년  DT#tw_datetime.year/4.

datetime_in_days(#tw_datetime{} = Dt) ->
  %%[todo: 데이트타임을 날자로 변환 구현]
  Dt#tw_datetime.day.

%%--------------------------------------------------------------------
%% @doc
%% uri_escaape를 한다. AWS규격에 맞추기 위해 치환된 문자는 upper case 로 맞춘다.edoc_lib에 있는 동일한 함수를 가져다 변형함.
%%
%% @end
%%--------------------------------------------------------------------
escape_uri([C | Cs]) when C >= $a, C =< $z ->
  [C | escape_uri(Cs)];
escape_uri([C | Cs]) when C >= $A, C =< $Z ->
  [C | escape_uri(Cs)];
escape_uri([C | Cs]) when C >= $0, C =< $9 ->
  [C | escape_uri(Cs)];
escape_uri([C = $. | Cs]) ->
  [C | escape_uri(Cs)];
escape_uri([C = $- | Cs]) ->
  [C | escape_uri(Cs)];
escape_uri([C = $_ | Cs]) ->
  [C | escape_uri(Cs)];
escape_uri([C | Cs]) when C > 16#7f ->
  %% This assumes that characters are at most 16 bits wide.
  escape_byte(((C band 16#c0) bsr 6) + 16#c0)
  ++ escape_byte(C band 16#3f + 16#80)
    ++ escape_uri(Cs);
escape_uri([C | Cs]) ->
  escape_byte(C) ++ escape_uri(Cs);
escape_uri([]) ->
  [].

escape_byte(C) when C >= 0, C =< 255 ->
  %%기존의 함수에는 to_upper 부분이 없다.
  string:to_upper([$%, hex_digit(C bsr 4), hex_digit(C band 15)]).

hex_digit(N) when N >= 0, N =< 9 ->
  N + $0;
hex_digit(N) when N > 9, N =< 15 ->
  N + $a - 10.

%%파일의 확장자를 가져온다.
get_extention(FileName1) ->
  FileName = to_list(FileName1),
  case re:run(FileName, "[^.]+$") of
    {match, RangeList} ->
      {From, Length} = lists:nth(1, RangeList),

      Name = string:substr(FileName, From + 1, Length),

      Name;
    _ ->
      false
  end.

get_pure_unique_id(UserUniqueIdTem) ->
  UserUniqueIdT = to_list(UserUniqueIdTem),
  case re:run(UserUniqueIdT, "[^_]+$") of
    {match, RangeList} ->
      {From, Length} = lists:nth(1, RangeList),

      Name = string:substr(UserUniqueIdT, From + 1, Length),

      Name;
    _ ->
      UserUniqueIdT
  end.

type_of(X) when is_integer(X) -> integer;
type_of(X) when is_float(X) -> float;
type_of(X) when is_list(X) -> list;
type_of(X) when is_tuple(X) -> tuple;
type_of(X) when is_bitstring(X) -> bitstring;  % will fail before e12
type_of(X) when is_binary(X) -> binary;
type_of(X) when is_boolean(X) -> boolean;
type_of(X) when is_function(X) -> function;
type_of(X) when is_pid(X) -> pid;
type_of(X) when is_port(X) -> port;
type_of(X) when is_reference(X) -> reference;
type_of(X) when is_atom(X) -> atom;

type_of(_X) -> unknown.

to_two_digit_list(M) ->
  string:right(to_list(M), 2, $0).



unicode_length(Str) when is_binary(Str) ->
  unicode_length(Str, 0).
unicode_length(<<Char/utf8, Str/binary>>, Count) ->
  unicode_length(Str, Count + 1);
unicode_length(<<>>, Count) ->
  Count.

binary_trim(Bin, Opts) when is_list(Opts) ->
  NoEmpty = list_some(no_empty, Opts),
  TrimedBin = binary_trim(Bin),
  case NoEmpty andalso TrimedBin == <<"">> of
    true -> undefined;
    _ -> TrimedBin
  end.

binary_trim(undefined) -> undefined;
binary_trim(Bin) when is_binary(Bin) ->
  Str = binary_to_list(Bin),
  StrippedStr = string:strip(Str),
  StrippedBin = list_to_binary(Str),
  StrippedBin.

list_some(Item, []) -> false;
list_some(Fun, [H | T]) when is_function(Fun) ->
  case Fun(H) of
    true -> ture;
    _ -> list_some(Fun, T)
  end;
list_some(Item, [H | T]) when H == Item -> true;
list_some(Item, [_ | T]) -> list_some(Item, T).

list_join(Sep, []) -> [];
list_join(Sep, [Item]) -> [Item];
list_join(Sep, [Item | T]) -> [Item, Sep | list_join(Sep, T)].

%%----------------[ETS]--------------------------
-spec ets_each(
    TableRef :: ets:tid(),
    Fun :: fun((Key :: term(), [Element :: term()], Extra :: term()) -> ok),
    Extra :: term()
) ->
  ok.
ets_each(TableRef, Fun, Extra) ->
  ets:safe_fixtable(TableRef, true),
  First = ets:first(TableRef),
  try
    do_ets_each(TableRef, Fun, Extra, First)
  after
    ets:safe_fixtable(TableRef, false)
  end.

%% @doc
%% Recursive helper function for ets_each.
-spec do_ets_each(
    TableRef :: ets:tid(),
    Fun :: fun((Key :: term(), [Element :: term()], Extra :: term()) -> ok),
    Extra :: term(),
    Key :: term()
) ->
  ok.
do_ets_each(_TableRef, _Fun, _Extra, '$end_of_table') ->
  ok;
do_ets_each(TableRef, Fun, Extra, Key) ->
  Extra:Fun(Key, ets:lookup(TableRef, Key), Extra),
  do_ets_each(TableRef, Fun, Extra, ets:next(TableRef, Key)).


partial(Fun, Params) when is_list(Params) ->
  fun
    ([_ | _] = RestParams) ->
      apply(Fun, Params ++ RestParams);
    (RestParam) ->
      apply(Fun, Params ++ [RestParam])
  end;
partial(Fun, Param) ->
  partial(Fun, [Param]).

compose(Funs) ->
  fun(Param) ->
    lists:foldl(
      fun(Fun, Result) ->
        Fun(Result)
      end,
      Param,
      Funs
    )
  end.

record_to_list(Fields, Record) ->
  lists:zip(Fields, tl(tuple_to_list(Record))).

list_to_record(RecordName, Fields, RecordList) ->
  list_to_tuple([RecordName | [proplists:get_value(F, RecordList) || F <- Fields]]).

record_assign(RecordName, Fields, RecordTo, RecordFrom) ->
  RecordToList = record_to_list(Fields, RecordTo),
  RecordFromList = record_to_list(Fields, RecordFrom),
  MergedRecordList =
    lists:foldl(
      fun(Field, Recording) ->
        Value = proplists:get_value(Field, RecordToList, undefined),
        ValueToAssign =
          case Value of
            undefined -> proplists:get_value(Field, RecordFromList, undefined);
            NewValue -> NewValue
          end,
        [{Field, ValueToAssign} | Recording]
      end,
      [],
      Fields
    ),
  list_to_record(RecordName, Fields, MergedRecordList).

get_record_from_map(RecordName, Fields, Map) ->
  RecordTupleList =
    lists:foldl(
      fun(Field, Recording) ->
        [{Field, maps:get(atom_to_binary(Field, utf8), Map, undefined)} | Recording]
      end,
      [],
      Fields
    ),
  list_to_record(RecordName, Fields, RecordTupleList).

record_to_json(Fields, Record) ->
  RecordToJSON = record_to_list(Fields, Record),
  jsx:encode(RecordToJSON).

first_or([H | _], _Else) -> H;
first_or(_, Else) -> Else.

first_or_undefined([H | _]) -> H;
first_or_undefined(_) -> undefined.

%%----------------[TIme Check]---------------
time_check_start() ->
  statistics(runtime),
  statistics(wall_clock).
time_check_end() ->
  %%[Debug]
  {_, Time1} = statistics(runtime),
  {_, Time2} = statistics(wall_clock),
  U1 = Time1 * 1000,
  U2 = Time2,
  U2.
time_check_end(Cont) ->
  %%[Debug]
  {_, Time1} = statistics(runtime),
  {_, Time2} = statistics(wall_clock),
  U1 = Time1 * 1000,
  U2 = Time2,
  ?INFOL("Code time For :~p, =~p (~p) mil", [Cont, U1, U2]),
  U2.
env(Module, Group, Name) ->
  proplists:get_value(Name, application:get_env(Module, Group, [])).

env(Group) ->
  application:get_env(tw_moigo_trip_api, Group, []).

env(Group, Name) ->
  proplists:get_value(Name, env(Group)).


get_server_launch_time_in_sec() ->

  ServerPosition = tw_util:get_server_position(),
  ?INFOL("serverposition:~p", [ServerPosition]),
  DBNODE = case ServerPosition of
             local -> 0;
             _ ->
               LT = tw_twinny_util:get_server_launch_time(),

               LT2 = try iso8601:parse_exact(LT)
                     catch
                       _:badarg -> {{0,0,0},{0,0,0}}
                     end,
               {{Y, M, D}, {H, MM, S}} = LT2,

               Dt = tw_util:new_tw_datetime(Y, M, D, H, MM, S),


               Sec = tw_util:datetime_to_sec(Dt),
               Sec
           end.