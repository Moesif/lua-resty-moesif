local json = require("json")
local socket = require("socket")
local url = require "socket.url"
local HTTPS = "https"
local moesif_ser = require "usr.local.openresty.site.lualib.plugins.moesif.moesif_ser"
local log = require "usr.local.openresty.site.lualib.plugins.moesif.log"

local function isempty(s)
  return s == nil or s == ''
end

-- Global config
config = ngx.shared.conf;

-- Set Default values.
if isempty(config:get("disable_transaction_id")) then
  config:set("disable_transaction_id", false)
end

if isempty(config:get("api_endpoint")) then
  config:set("api_endpoint", "https://api.moesif.net")
end

if isempty(config:get("timeout")) then
  config:set("timeout", 10000)
end

if isempty(config:get("keepalive")) then
  config:set("keepalive", 10000)
end

if isempty(config:get("api_version")) then
  config:set("api_version", "1.0")
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

if isempty(config:get("response_masks")) then
  config:set("response_masks", "")
end

if isempty(config:get("batch_size")) then
  config:set("batch_size", 25)
end

if isempty(config:get("user_id_header")) then
  config:set("user_id_header", "userId")
end

if isempty(config:get("company_id_header")) then
  config:set("company_id_header", "companyId")
end


-- Log Event
if isempty(config:get("application_id")) then
  ngx.log(ngx.ERR, "[moesif] Please provide the Moesif Application Id");
else
  local message = moesif_ser.prepare_message(config)

  -- Execute/Log message
  log.execute(config, message)
end
