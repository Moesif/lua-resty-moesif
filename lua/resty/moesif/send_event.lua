local socket = require("socket")
local url = require "socket.url"
local HTTPS = "https"
local moesif_ser = require "moesif_ser"
local log = require "log"

local function isempty(s)
  return s == nil or s == ''
end

-- Global config
local config = ngx.shared.moesif_conf;

-- Set Default values.
if isempty(config:get("disable_transaction_id")) then
  config:set("disable_transaction_id", false)
end

if isempty(config:get("api_endpoint")) then
  config:set("api_endpoint", "https://api.moesif.net")
end

if isempty(config:get("timeout")) then
  config:set("timeout", 1000)
end

if isempty(config:get("connect_timeout")) then
  config:set("connect_timeout", 1000)
end

if isempty(config:get("send_timeout")) then
  config:set("send_timeout", 2000)
end

if isempty(config:get("keepalive")) then
  config:set("keepalive", 5000)
end

if isempty(config:get("disable_capture_request_body")) then
  config:set("disable_capture_request_body", false)
end

if isempty(config:get("disable_capture_response_body")) then
  config:set("disable_capture_response_body", false)
end

if isempty(config:get("request_masks")) then
  config:set("request_masks", "")
end

if isempty(config:get("request_body_masks")) then
  config:set("request_body_masks", "")
end

if isempty(config:get("request_header_masks")) then
  config:set("request_header_masks", "")
end

if isempty(config:get("response_masks")) then
  config:set("response_masks", "")
end

if isempty(config:get("response_body_masks")) then
  config:set("response_body_masks", "")
end

if isempty(config:get("response_header_masks")) then
  config:set("response_header_masks", "")
end

if isempty(config:get("batch_size")) then
  config:set("batch_size", 200)
end

if isempty(config:get("debug")) then
  config:set("debug", false)
end

if isempty(config:get("batch_max_time")) then
  config:set("batch_max_time", 2)
end

if isempty(config:get("max_callback_time_spent")) then
  config:set("max_callback_time_spent", 2000)
end

if isempty(config:get("disable_gzip_payload_decompression")) then
  config:set("disable_gzip_payload_decompression", false)
end

if isempty(config:get("queue_scheduled_time")) then
  config:set("queue_scheduled_time", os.time{year=1970, month=1, day=1, hour=0})
end

if isempty(config:get("max_body_size_limit")) then
  config:set("max_body_size_limit", 100000)
end

if isempty(config:get("authorization_header_name")) then
  config:set("authorization_header_name", "authorization")
end

if isempty(config:get("authorization_user_id_field")) then
  config:set("authorization_user_id_field", "sub")
end

-- User Agent String
local user_agent_string = "lua-resty-moesif/1.3.7"

-- Log Event
if isempty(config:get("application_id")) then
  ngx.log(ngx.ERR, "[moesif] Please provide the Moesif Application Id");
else
  local logEvent = ngx.var.moesif_log_event
  if (logEvent == nil or logEvent == '') or (string.lower(logEvent) == "true") then
    local message = moesif_ser.prepare_message(config)

    -- Execute/Log message
    log.execute(config, message, user_agent_string, config:get("debug"))
  end
end
