local socket = require("socket")
local url = require "socket.url"
local HTTPS = "https"
local moesif_ser = require "moesif_ser"
local log = require "log"
local connect = require "connection"
local helpers = require "helpers"
local string_format = string.format
local luaxml = require('LuaXML')
local http = require "socket.http"

local function nonEmpty(s)
    return s ~= nil and s ~= ''
end

local function isempty(s)
    return s == nil or s == ''
end

-- Global config
config = ngx.shared.moesif_conf;

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

if isempty(config:get("debug")) then
  config:set("debug", false)
end

if isempty(config:get("3scale_domain")) then
    config:set("3scale_domain", "")
end

if isempty(config:get("3scale_access_token")) then
  config:set("3scale_access_token", "")
end

if isempty(config:get("3scale_user_key")) then
  config:set("3scale_user_key", "")
end

if isempty(config:get("3Scale_user_id")) then
  config:set("3Scale_user_id", "")
end

if isempty(config:get("3Scale_last_updated_time")) then
  config:set("3Scale_last_updated_time", os.time())
end

if isempty(config:get("3Scale_config_fetched")) then
    config:set("3Scale_config_fetched", false)
end

 -- Get 3Scale Application configuration function
function get_3Scale_config(premature, config, debug)

    if premature then
        return
    end
    
    local access_token = config:get("3scale_access_token")
    local user_key = config:get("3scale_user_key")
    local domain_name = string.lower(config:get("3scale_domain"))
    local sock, parsed_url = connect.get_connection(config, "https://" .. domain_name, "/admin/api/applications/find.xml?access_token=" .. access_token .. "&user_key=" .. user_key)

    -- Prepare the payload
    local payload = string_format("%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\n",
    "GET", parsed_url.path .. "?" .. parsed_url.query, parsed_url.host)

    local ok, err = sock:send(payload .. "\r\n")
    if not ok then
        if debug then
            ngx.log(ngx.CRIT, "[moesif] failed to send data to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
        end
    else
        if debug then
            ngx.log(ngx.CRIT, "[moesif] Successfully send request to fetch 3Scale application configuration " , ok)
        end
    end

    -- Read the response
    local config_response = helpers.read_socket_data(sock)
    ok, err = sock:setkeepalive(10000)
    if not ok then
        if debug then
            ngx.log(ngx.CRIT, "[moesif] failed to keepalive to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
        end
    else
        if debug then
            ngx.log(ngx.CRIT, "[moesif] success keep-alive", ok)
        end
    end

    local response_body = config_response:match("(%<.*>)")
    if response_body ~= nil then 
        local xobject = xml.eval(response_body)
        local xapplication = xobject:find("application")
        if xapplication ~= nil then
            config:set("3Scale_user_id", xapplication[1][1])
            config:set("3Scale_last_updated_time", os.time())
            if debug then
                ngx.log(ngx.CRIT, "[moesif] Successfully fetched the userId ")
            end
        else
            config:set("3Scale_last_updated_time", os.time())
            if debug then
                ngx.log(ngx.CRIT, "[moesif] application tag does not exist ")
            end
        end
    else
        config:set("3Scale_last_updated_time", os.time())
        if debug then
            ngx.log(ngx.CRIT, "[moesif] xml response body does not exist ")
        end
    end

    config:set("3Scale_config_fetched", true)
    return config_response
end

-- 3Scale application configuration helper function
function config_helper(config, debug)
    local ok, err = ngx.timer.at(0, get_3Scale_config, config, debug)
    if not ok then
        if debug then
            ngx.log(ngx.CRIT, "[moesif] failed to get 3Scale application config ", err)
        end
    else
        if debug then
            ngx.log(ngx.CRIT, "[moesif] successfully fetched the 3Scale application configuration" , ok)
        end
    end
end

-- 3Scale application configuration
if nonEmpty(config:get("3scale_domain")) and nonEmpty(config:get("3scale_access_token")) and nonEmpty(config:get("3scale_user_key")) then
    
    local debug = config:get("debug")
    if not config:get("3Scale_config_fetched") then
        if debug then
            ngx.log(ngx.CRIT, "[moesif] fetching the 3Scale application configuration ")
        end
        config_helper(config, debug)
    end

    if (os.time() > (config:get("3Scale_last_updated_time") + 3600)) then   
        if debug then
            ngx.log(ngx.CRIT, "[moesif] fetching the updated 3Scale application configuration ")
        end
        config_helper(config, debug)
    end

    if nonEmpty(config:get("3Scale_user_id")) then
        if debug then
            ngx.log(ngx.CRIT, "[moesif] Using the previously fetched 3Scale userId: ")
        end
        ngx.var.user_id = config:get("3Scale_user_id")
    else
        if debug then
            ngx.log(ngx.CRIT, "[moesif] No 3Scale userId found ")
        end
    end
else
    if config:get("debug") then 
        ngx.log(ngx.CRIT, "3Scale accessToken or userKey or domainName is not provided")  
    end
end

-- Log Event
if isempty(config:get("application_id")) then
  ngx.log(ngx.ERR, "[moesif] Please provide the Moesif Application Id");
else
  local message = moesif_ser.prepare_message(config)

  -- Execute/Log message
  log.execute(config, message, config:get("debug"))
end
