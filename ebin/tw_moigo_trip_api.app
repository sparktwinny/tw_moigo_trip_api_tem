{application,tw_moigo_trip_api,
             [{description,[]},
              {vsn,"1"},
              {registered,[]},
              {applications,[kernel,stdlib]},
              {modules,[tw_aws,tw_datetime,tw_moigo_trip_api_app,
                        tw_moigo_trip_http_base,tw_moigo_trip_log_manager,
                        tw_moigo_trip_redis,tw_moigo_trip_sup,tw_monitor,
                        tw_monitor_sup,tw_node_manager_gen,tw_reloader,
                        tw_util]},
              {mod,{tw_moigo_trip_api_app,[]}},
              {env,[]}]}.