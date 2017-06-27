%%%-------------------------------------------------------------------
%%% @author psw
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 25. 1월 2016 오후 5:02
%%%-------------------------------------------------------------------
-module(tw_aws).
-author("psw").
-include("src/include/db_record.hrl").
-include("deps/erlcloud/include/erlcloud.hrl").
-include("deps/erlcloud/include/erlcloud_aws.hrl").
-include("src/include/tw_macro.hrl").
%% API
-export([

  %ec2
set_ec2_instance_tag/3,
  %kinesis
  upload_kinesis_firehose_stream/2,
  %autoscale
  handleOnTerminate/1, handleOnTerminate_internal/1,
  %s3
  get_file_from_s3/2,

  get_upload_signed_url_with_filename/9,
  get_upload_information_with_filename/8,


  get_s3_temp_crendential/2,


  get_signed_url/3, get_signed_url_with_filename/4
]).



set_ec2_instance_tag(InstanceId, Name, Value) ->


  DT = lists:append([" aws ec2 create-tags --resources ", tw_util:to_list(InstanceId), " --tag Key=", tw_util:to_list(Name), ",Value=", tw_util:to_list(Value), " --region=ap-northeast-2"]),
  DD = os:cmd(DT),
  ?INFOL("DD:~p", [DT]),
  ok.


upload_kinesis_firehose_stream(Data, StreamName) ->

  {ok, Config} = erlcloud_aws:update_config(#aws_config{}),
  Config2 = Config#aws_config{firehose_host = "firehose.us-west-2.amazonaws.com",
    ddb_host = "dynamodb.ap-northeast-2.amazonaws.com", timeout = 20000},


  Rest = erlcloud_firehose:put_record(StreamName, Data, Config2).


handleOnTerminate_internal(InstanceId) ->
  ?WARNL("handleOnTerminate_internal:~p", [InstanceId]),
  MyInstanceId = tw_util:get_instance_id(),
  case MyInstanceId of
    InstanceId ->
      tw_db_log_manager:onTerminate();
    _ -> ok
  end.
handleOnTerminate(Received) ->

  ?WARNL("Handling ONTERMINATE:~p", [Received]),
  EC2InstanceId = maps:get(<<"EC2InstanceId">>, Received, undefined),
  LifecycleTransition = maps:get(<<"LifecycleTransition">>, Received, undefined),
  ?WARNL("Handling ONTERMINATE InstanceId:~p,ACtion:~p", [EC2InstanceId, LifecycleTransition]),
  case LifecycleTransition of
    <<"autoscaling:EC2_INSTANCE_TERMINATING">> ->
      handleOnTerminate_internal(EC2InstanceId),
      case eredis_pool:q(node_manage, ["LRANGE", "known_relay_host", 0, -1]) of
        {ok, Value} when Value =/= undefined ->

          lists:foreach(
            fun(Host) ->


              ?INFOL("Pinging Hosts:~p", [Host]),
              Relay = binary_to_atom(Host, utf8),

              REsult = rpc:call(Relay, tw_aws, handleOnTerminate_internal, [EC2InstanceId]),
              ?INFOL("Result:~p", [REsult])

            end, Value),
          ok;
        _ ->
          failed
      end;
    _ -> ok
  end,


  ok.











get_file_from_s3(Bucket, Path) ->
  ConfT = #aws_config{
    s3_host = "s3-ap-northeast-2.amazonaws.com"},

  {ok, Conf} = erlcloud_aws:update_config(ConfT),

  ssl:start(),
  Res = erlcloud_s3:get_object(Bucket, Path, Conf),
  %%ssl:stop(),
  Res.
upload_to_s3(Bucket, Key, ValueT, Host) ->
  ConfT = #aws_config{
    s3_host = Host,
    timeout = 30000},
  {ok, Conf} = erlcloud_aws:update_config(ConfT),
  ssl:start(),
  Value = case ValueT of
            {file, FileNameOfF} -> {ok, DataFromFile} = file:read_file(FileNameOfF),
              DataFromFile;
            _ -> ValueT
          end,
  ?INFOL("S3 Uploading: Bucket:~p, Path:~p", [Bucket, Key]),
  try
    Result = erlcloud_s3:put_object(Bucket, tw_util:to_list(Key), (Value), [{meta, [{"uploaded_by", "api_server"}]}], Conf),
    erlang:garbage_collect(self()),
    Key
  catch
    Er:Error ->
      ?ERRORL("error:~p,~p,~p", [Er, Error, erlang:get_stacktrace()]),
      {Er, Error}
  end.


get_s3_temp_crendential(UserUniqueId, DurationInSeconds) ->

  {ok, DD} = erlcloud_aws:update_config(#aws_config{}),

  {AssumedConfig, Cred} = erlcloud_sts:assume_role(DD, "arn:aws:iam::274740264677:role/moigo-s3-upload-role", tw_util:to_list(UserUniqueId), DurationInSeconds, tw_util:to_list(UserUniqueId)),
  AssumedConfig.
%%  ?WARNL("ABC:~p", [AssumedConfig]),
%%  jsx:encode([
%%    {<<"result">>, 0},
%%    {<<"access_key_id">>, tw_util:to_binary(AssumedConfig#aws_config.access_key_id)},
%%    {<<"secret_access_key">>, tw_util:to_binary(AssumedConfig#aws_config.secret_access_key)},
%%    {<<"security_token">>, tw_util:to_binary(AssumedConfig#aws_config.security_token)}
%%  ]).

get_upload_information_with_filename(Bucket, PathKey, Type, TargetUniqueId, Filesize, OriginalFileName, MyUniqueId, TempIdx) ->
  BucketBin = tw_util:to_binary(Bucket),
  PathKeyBin = tw_util:to_binary(PathKey),

  TypeBin = tw_util:to_binary(Type),
  OriginalFileNameBin = tw_util:encode_web_safe_base64(tw_util:to_binary(OriginalFileName)),
  TargetUniqueIdBin = tw_util:to_binary(TargetUniqueId),
  MyUniqueIdBin = tw_util:to_binary(MyUniqueId),
  TempIdxBin = tw_util:to_binary(TempIdx),
  jsx:encode([
    {<<"result">>, 0},
    {<<"key">>, tw_util:to_binary(PathKey)},

    {<<"bucket">>, tw_util:to_binary(BucketBin)},

    {<<"orgfilename">>, tw_util:to_binary(OriginalFileNameBin)},
    {<<"writeruniqueid">>, tw_util:to_binary(MyUniqueIdBin)},
    {<<"targetuniqueid">>, tw_util:to_binary(TargetUniqueIdBin)},
    {<<"tempidx">>, tw_util:to_binary(TempIdxBin)},


    {<<"type">>, tw_util:to_binary(Type)},
    {<<"targetuniqueid">>, TargetUniqueId}

  ]).

get_upload_signed_url_with_filename(Bucket, PathKey, Type, TargetUniqueId, Expire, Filesize, OriginalFileName, MyUniqueId, TempIdx) ->


  Date = tw_util:iso_8601_basic_time(),
  ConfT = #aws_config{
    s3_host = "s3-ap-northeast-2.amazonaws.com"},


  {ok, Conf} = erlcloud_aws:update_config(ConfT),

  SigningKey = signing_key(Conf, Date, "ap-northeast-2", "s3"),


  {A, B, C} = os:timestamp(),
  ExpireDate = tw_util:iso_8601_basic_time({A, B + Expire, C}),

  Time = tw_util:local_time_to_datetime(calendar:universal_time()),
  ?INFOL("time:~p", [ExpireDate]),

  Date2 = tw_util:to_list(Time#tw_datetime.year) ++ string:right(tw_util:to_list(Time#tw_datetime.month), 2, $0) ++ string:right(tw_util:to_list(Time#tw_datetime.day), 2, $0),

  Crendent = lists:append([tw_util:to_list(Conf#aws_config.access_key_id), "/", Date2, "/", "ap-northeast-2", "/", "s3", "/", "aws4_request"]),


  FilesizeBin1 = tw_util:to_binary(Filesize),
  FilesizeBin2 = tw_util:to_binary(Filesize + 1),
  CredentBin = tw_util:to_binary(Crendent),
  ExpBin = tw_util:to_binary(ExpireDate),
  BucketBin = tw_util:to_binary(Bucket),
  PathKeyBin = tw_util:to_binary(PathKey),
  DateBin = tw_util:to_binary(Date),
  TypeBin = tw_util:to_binary(Type),
  OriginalFileNameBin = tw_util:encode_web_safe_base64(tw_util:to_binary(OriginalFileName)),
  TargetUniqueIdBin = tw_util:to_binary(TargetUniqueId),
  MyUniqueIdBin = tw_util:to_binary(MyUniqueId),
  TempIdxBin = tw_util:to_binary(TempIdx),
  TokenBin = tw_util:to_binary(Conf#aws_config.security_token),
  ?WARNL("original file Name:~ts", [OriginalFileNameBin]),
  Policy =
    <<"{\"expiration\":\"", ExpBin/binary, "\",", "\"conditions\":[",
      "{\"", "x-amz-credential", "\":", "\"", CredentBin/binary, "\"", "},",
      "{\"", "acl", "\":", "\"", "public-read", "\"", "},",
      "{\"", "bucket", "\":", "\"", BucketBin/binary, "\"", "},",
      "{\"", "key", "\":", "\"", PathKeyBin/binary, "\"", "},",
      "{\"", "x-amz-meta-tempidx", "\":", "\"", TempIdxBin/binary, "\"", "},",
      "{\"", "x-amz-meta-orgfilename", "\":", "\"", OriginalFileNameBin/binary, "\"", "},",
      "{\"", "x-amz-meta-writeruniqueid", "\":", "\"", MyUniqueIdBin/binary, "\"", "},",
      "{\"", "x-amz-meta-targetuniqueid", "\":", "\"", TargetUniqueIdBin/binary, "\"", "},",
      "{\"", "X-Amz-Security-Token", "\":", "\"", TokenBin/binary, "\"", "},",


      "{\"", "x-amz-meta-type", "\":", "\"", TypeBin/binary, "\"", "},",
      "{\"", "x-amz-algorithm", "\":", "\"", "AWS4-HMAC-SHA256", "\"", "},",
      "{\"", "x-amz-date", "\":", "\"", DateBin/binary, "\"", "},",
      "[\"", "content-length-range\"", ",", FilesizeBin1/binary, ",", FilesizeBin2/binary, "]"
      , "]}">>,


  PolicyBase64 = base64:encode(Policy),
  Signature = base16(erlcloud_util:sha256_mac(SigningKey, tw_util:to_list(PolicyBase64))),
  jsx:encode([
    {<<"result">>, 0},
    {<<"key">>, tw_util:to_binary(PathKey)},
    {<<"X-Amz-Credential">>, tw_util:to_binary(Crendent)},
    {<<"bucket">>, tw_util:to_binary(BucketBin)},

    {<<"x-amz-meta-orgfilename">>, tw_util:to_binary(OriginalFileNameBin)},
    {<<"x-amz-meta-writeruniqueid">>, tw_util:to_binary(MyUniqueIdBin)},
    {<<"x-amz-meta-targetuniqueid">>, tw_util:to_binary(TargetUniqueIdBin)},
    {<<"x-amz-meta-tempidx">>, tw_util:to_binary(TempIdxBin)},
    {<<"X-Amz-Security-Token">>, tw_util:to_binary(TokenBin)},
    {<<"X-Amz-Algorithm">>, <<"AWS4-HMAC-SHA256">>},
    {<<"acl">>, <<"public-read">>},
    {<<"x-amz-meta-type">>, tw_util:to_binary(Type)},
    {<<"x-amz-meta-targetuniqueid">>, TargetUniqueId},
    {<<"X-Amz-Date">>, tw_util:to_binary(Date)},
    {<<"Policy">>, tw_util:to_binary(PolicyBase64)},
    {<<"X-Amz-Signature">>, tw_util:to_binary(Signature)}
  ]).




get_signed_url_with_filename(Bucket, Path, Expire, FileNameT) ->

  %%파일명에 대해 escape_uri처리를 해주어야 한다.
  FileNameStr = (tw_util:escape_uri(tw_util:to_list(FileNameT))),

  FileName = FileNameStr,
  ExtraHeader = "&response-content-disposition=attachment%3B%20filename%3D" ++ tw_util:to_list(FileName),
  Time = tw_util:local_time_to_datetime(calendar:universal_time()),
  ?INFOL("time:~p", [Time]),

  Date2 = tw_util:to_list(Time#tw_datetime.year) ++ string:right(tw_util:to_list(Time#tw_datetime.month), 2, $0) ++ string:right(tw_util:to_list(Time#tw_datetime.day), 2, $0),
  ConfT = #aws_config{
    s3_host = "s3-ap-northeast-2.amazonaws.com"},


  {ok, Conf} = erlcloud_aws:update_config(ConfT),
  Date = tw_util:iso_8601_basic_time(),


  QueryParm = lists:flatten(["X-Amz-Algorithm=AWS4-HMAC-SHA256",
    "&X-Amz-Credential=", erlcloud_http:url_encode(Conf#aws_config.access_key_id), "%2F", Date2, "%2Fap-northeast-2%2Fs3%2Faws4_request",
    "&X-Amz-Date=", Date,
    "&X-Amz-Expires=", tw_util:to_list(Expire),
    "&X-Amz-Security-Token=", erlcloud_http:url_encode((Conf#aws_config.security_token)),
    "&X-Amz-SignedHeaders=host",
    ExtraHeader]),

  Scope = credential_scope(Date, "ap-northeast-2", "s3"),

  URI = get_object_url(tw_util:to_list(Bucket), Path, Conf),
  CRequest = canonical_request(get, Path, QueryParm, tw_util:to_list(Bucket) ++ ".s3-ap-northeast-2.amazonaws.com", "UNSIGNED-PAYLOAD"),

  print_hex(CRequest),
  ?INFOL("CRequest:~ts", [CRequest]),


  ToSign = to_sign(Date, Scope, CRequest),

  SigningKey = signing_key(Conf, Date, "ap-northeast-2", "s3"),

  Signature = base16(erlcloud_util:sha256_mac(SigningKey, ToSign)),

  lists:flatten([URI,
    "?X-Amz-Algorithm=AWS4-HMAC-SHA256",
    "&X-Amz-Credential=", erlcloud_http:url_encode(Conf#aws_config.access_key_id), "%2F", Date2, "%2Fap-northeast-2%2Fs3%2Faws4_request",
    "&X-Amz-Date=", Date,
    "&X-Amz-Expires=", tw_util:to_list(Expire),
    "&X-Amz-Security-Token=", erlcloud_http:url_encode((Conf#aws_config.security_token)),
    "&X-Amz-SignedHeaders=host", ExtraHeader,
    "&X-Amz-Signature=", Signature]).

get_signed_url(Bucket, Path, Expire) ->
  Time = tw_util:local_time_to_datetime(calendar:universal_time()),
  ?INFOL("time:~p", [Time]),

  Date2 = tw_util:to_list(Time#tw_datetime.year) ++ string:right(tw_util:to_list(Time#tw_datetime.month), 2, $0) ++ string:right(tw_util:to_list(Time#tw_datetime.day), 2, $0),
  ConfT = #aws_config{
    s3_host = "s3-ap-northeast-2.amazonaws.com"},

  {ok, Conf} = erlcloud_aws:update_config(ConfT),
  Date = tw_util:iso_8601_basic_time(),


  QueryParm = lists:flatten(["X-Amz-Algorithm=AWS4-HMAC-SHA256",
    "&X-Amz-Credential=", erlcloud_http:url_encode(Conf#aws_config.access_key_id), "%2F", Date2, "%2Fap-northeast-2%2Fs3%2Faws4_request",
    "&X-Amz-Date=", Date,
    "&X-Amz-Expires=", tw_util:to_list(Expire),
    "&X-Amz-Security-Token=", erlcloud_http:url_encode((Conf#aws_config.security_token)),
    "&X-Amz-SignedHeaders=host"]),

  Scope = credential_scope(Date, "ap-northeast-2", "s3"),

  URI = get_object_url(tw_util:to_list(Bucket), Path, Conf),
  CRequest = canonical_request(get, Path, QueryParm, tw_util:to_list(Bucket) ++ ".s3-ap-northeast-2.amazonaws.com", "UNSIGNED-PAYLOAD"),

  print_hex(CRequest),
  ?INFOL("CRequest:~ts", [CRequest]),


  ToSign = to_sign(Date, Scope, CRequest),
  ?INFOL("ToSign:~ts", [ToSign]),
  SigningKey = signing_key(Conf, Date, "ap-northeast-2", "s3"),

  Signature = base16(erlcloud_util:sha256_mac(SigningKey, ToSign)),

  lists:flatten([URI,
    "?X-Amz-Algorithm=AWS4-HMAC-SHA256",
    "&X-Amz-Credential=", erlcloud_http:url_encode(Conf#aws_config.access_key_id), "%2F", Date2, "%2Fap-northeast-2%2Fs3%2Faws4_request",
    "&X-Amz-Date=", Date,
    "&X-Amz-Expires=", tw_util:to_list(Expire),
    "&X-Amz-Security-Token=", erlcloud_http:url_encode((Conf#aws_config.security_token)),
    "&X-Amz-SignedHeaders=host",
    "&X-Amz-Signature=", Signature]).


print_hex(String) ->
  StringBin = tw_util:to_binary(String),
  io:format("<<~s>>~n", [[io_lib:format("~2.16.0B", [StringBin]) || <<StringBin:8>> <= <<255, 16>>]]).

hash_encode(Data) ->
  Hash = erlcloud_util:sha256(Data),
  base16(Hash).

base16(Data) ->
  io_lib:format("~64.16.0b", [binary:decode_unsigned(Data)]).
credential_scope(Date, Region, Service) ->
  DateOnly = string:left(Date, 8),
  lists:append([DateOnly, "/", Region, "/", Service, "/aws4_request"]).
to_sign(Date, CredentialScope, Request) ->

  Hash = hash_encode(Request),
  ?INFOL("Hash:~p", [{Hash, CredentialScope}]),
  ["AWS4-HMAC-SHA256", $\n,
    Date, $\n,
    CredentialScope, $\n,
    hash_encode(Request)].
canonical_request(Method, CanonicalURI, QParams, Host, PayloadHash) ->

  ?INFOL("ST:~p", [{Method, CanonicalURI, QParams, Host, PayloadHash}]),
  [string:to_upper(atom_to_list(Method)), $\n,
    "/", CanonicalURI, $\n,
    QParams, $\n,
    "host:", Host, $\n, $\n,
    "host", $\n,
    PayloadHash].
%%
get_object_url(BucketName, Key, Config) ->
  case Config#aws_config.s3_bucket_after_host of
    false ->
      lists:flatten([Config#aws_config.s3_scheme, BucketName, ".", Config#aws_config.s3_host, port_spec(Config), "/", Key]);
    true ->
      lists:flatten([Config#aws_config.s3_scheme, Config#aws_config.s3_host, port_spec(Config), "/", BucketName, "/", Key])
  end.

signing_key(Config, Date, Region, Service) ->
  %% TODO cache the signing key so we don't have to recompute for every request
  DateOnly = string:left(Date, 8),
  KDate = erlcloud_util:sha256_mac("AWS4" ++ Config#aws_config.secret_access_key, DateOnly),
  KRegion = erlcloud_util:sha256_mac(KDate, Region),
  KService = erlcloud_util:sha256_mac(KRegion, Service),
  erlcloud_util:sha256_mac(KService, "aws4_request").
port_spec(#aws_config{s3_port = 80}) ->
  "";
port_spec(#aws_config{s3_port = Port}) ->
  [":", erlang:integer_to_list(Port)].

