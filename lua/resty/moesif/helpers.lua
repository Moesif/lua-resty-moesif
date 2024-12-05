local url = require "socket.url"
local HTTPS = "https"
local _M = {}
local cjson = require "cjson"
local base64 = require "moesifapi.lua.base64"

local function dump(o)
  if type(o) == 'table' then
    local s = '{ '
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. '['..k..'] = ' .. dump(v) .. ','
    end
    return s .. '} '
  else
    return tostring(o)
  end
end

-- Function to prepare config mapping
-- @param  `message`      Message to be logged
-- @return `regex_conifg` Regex config mapping
function _M.prepare_config_mapping(message)
  local regex_config = {}
  -- Config mapping for request.verb
  if (message["request"]["verb"] ~= nil) then 
      regex_config["request.verb"] = message["request"]["verb"]
  end 
  -- Config mapping for request.uri
  if (message["request"]["uri"] ~= nil) then 
      local extracted = string.match(message["request"]["uri"], "http[s]*://[^/]+(/[^?]+)")
      if extracted == nil then 
          extracted = '/'
      end
      regex_config["request.route"] = extracted
  end 
  -- Config mapping for request.ip_address
  if (message["request"]["ip_address"] ~= nil) then 
      regex_config["request.ip_address"] = message["request"]["ip_address"]
  end
  -- Config mapping for response.status
  if (message["response"]["status"] ~= nil) then 
      regex_config["response.status"] = message["response"]["status"]
  end

  return regex_config
end 


local function isempty(s)
  return s == nil or s == ''
end  

function _M.set_default_config_value(config)
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
  elseif config:get("batch_max_time") > 30 then 
    ngx.log(ngx.ERR, "[moesif] Resetting Batch max time config value (" .. tostring(config:get("batch_max_time")) .. ") to max allowed (30 seconds)");
    config:set("batch_max_time", 30)
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

  if isempty(config:get("authorization_company_id_field")) then
    config:set("authorization_company_id_field", "")
  end

  if isempty(config:get("enable_compression")) then
    config:set("enable_compression", false)
  end


  if isempty(config:get("request_max_body_size_limit")) then
    config:set("request_max_body_size_limit", 100000)
  end

  if isempty(config:get("response_max_body_size_limit")) then
    config:set("response_max_body_size_limit", 100000)
  end


  -- TODO: In NGINX's Lua module, shared dictionaries (ngx.shared.my_conf) are designed to hold string-based values or other simple types like numbers, booleans, etc. 
  -- They are not meant to store Lua tables directly, including empty tables, in the same way you would work with Lua's native data structures.
  -- TODO: Figure out - request_query_masks = {default = {}, type = "array", elements = typedefs.header_name}
  if isempty(config:get("request_query_masks")) then
    ngx.log(ngx.DEBUG, "config set to default in helpers - ")  
    config:set("request_query_masks", "[]") -- default value may be [] or {}
  else
    ngx.log(ngx.DEBUG, "config not set to default in helpers - ")  
  end

  for _, key in ipairs({"application_id", "debug", "request_query_masks"}) do
    local value = config:get(key)
    ngx.log(ngx.ERR, "Key: ", key, ", Value: ", dump(value) or "nil")
  end

  ngx.log(ngx.DEBUG, "config return from helpers - ", dump(config))

  return config
end

return _M
