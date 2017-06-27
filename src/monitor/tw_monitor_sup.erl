%%%-------------------------------------------------------------------
%%% @author psw
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 11. 3월 2016 오후 10:14
%%%-------------------------------------------------------------------
-module(tw_monitor_sup).
-author("psw").
-include("src/include/tw_macro.hrl").


-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

start_link() ->

  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->



  Env = tw_util:env(monitoring),

  {ok, {{one_for_one, 10, 100},
    [{tw_monitor, {tw_monitor, start_link, [Env]},
      permanent, 5000, worker, [tw_monitor]}]}}.

