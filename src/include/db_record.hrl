%%%-------------------------------------------------------------------
%%% @author psw
%%% @copyright (C) 2015, <COMPANY>
%%%
%%% @doc
%%% @end
%%% Created : 29. 12월 2015 오후 8:10
%%%-------------------------------------------------------------------



-author("psw").
-include("deps/emysql/include/emysql.hrl").
-record(db_date_info,{num,lunar_date,solar_date,yun,ganji,memo }).
-record(group_random_pick_record,{max_user_idx,low_user_idx,max=0,low=100000   }).
-record(word_game_record_const,{
  a0=0, %%ㄱ
  %%a1,%%ㄲ
  a2=0, %%ㄴ
  a3=0, %%ㄷ
  %%a4,%%ㄸ
  a5=0, %%ㄹ
  a6=0, %%ㅁ
  a7=0, %%ㅂ
  %%a8,%%ㅃ
  a9=0, %%ㅅ
  %%a10,%%ㅆ
  a11=0, %%ㅇ
  a12=0, %%ㅈ
  %% a13,%%ㅉ

  a14=0, %%ㅊ
  a15=0, %%ㅋ
  a16=0, %%ㅌ
  a17=0, %%ㅍ
  a18=0 %%ㅎ


}).

-record(word_game_record_vow,{
  a0=0,%% ㅏ
  a1=0,%% ㅑ
  a2=0,%% ㅓ
  a3=0,%% ㅕ
  a4=0,%% ㅗ
  a5=0,%% ㅛ
  a6=0,%% ㅜ
  a7=0,%% ㅠ
  a8=0,%% ㅡ
  a9=0%% ㅣ

}).
-record(tw_datetime, {year = 0, month = 0, day = 0, hour = 0, min = 0, sec = 0}).
-record(user_state, {session_key,user_phone, user_idx, client_type, ip_address, last_call_time, user_unique_id, client_info, user_nick, version, expire_time = 1000000 * 10000, aes_key, created_timestamp,fake,region= <<"kor">>}).