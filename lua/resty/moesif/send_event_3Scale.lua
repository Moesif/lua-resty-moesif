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
local moesif_global = require "moesif_global"

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

if isempty(config:get("3scale_user_id_name")) then
  config:set("3scale_user_id_name", "id")
end

if isempty(config:get("3scale_auth_api_key")) then
  config:set("3scale_auth_api_key", "user_key")
end

if isempty(config:get("3scale_auth_app_id")) then
  config:set("3scale_auth_app_id", "app_id")
end

if isempty(config:get("3scale_auth_app_key_pair")) then
  config:set("3scale_auth_app_key_pair", "app_key")
end

-- Get 3Scale Application configuration function
function get_3Scale_config(premature, config, auth_api_key, auth_app_id, auth_app_key_pair, is_auth_pair_method, debug)

    if premature then
        return
    end
    
    local domain_name = string.lower(config:get("3scale_domain"))
    local access_token = config:get("3scale_access_token")
    local sock, parsed_url = nil, nil
    if is_auth_pair_method then 
        sock, parsed_url = connect.get_connection(config, "https://" .. domain_name, "/admin/api/applications/find.xml?access_token=" .. access_token .. "&app_id=" .. auth_app_id .. "&app_key=" .. auth_app_key_pair)
    else 
        sock, parsed_url = connect.get_connection(config, "https://" .. domain_name, "/admin/api/applications/find.xml?access_token=" .. access_token .. "&user_key=" .. auth_api_key)
    end

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
    if is_auth_pair_method then
        scale_config_response_dict[auth_app_id .. "-" .. auth_app_key_pair] = response_body
        scale_last_updated_time_dict[auth_app_id .. "-" .. auth_app_key_pair] = os.time()
    else 
        scale_config_response_dict[auth_api_key] = response_body
        scale_last_updated_time_dict[auth_api_key] = os.time()
    end
    return response_body
end

-- Function to fetch credentials
function fetch_credentials(auth_key_name, headers, queryparams)
    local fetched_key = nil
    if headers[auth_key_name] ~= nil then
        fetched_key = headers[auth_key_name]
    else 
        local queryparams = ngx.req.get_uri_args()
        if queryparams[auth_key_name] ~= nil then
            fetched_key = queryparams[auth_key_name]
        end
    end
    return fetched_key
end

-- Function to parse XML response
function parseXML(user_id_name, auth_key_name, debug)
    local response_body = scale_config_response_dict[auth_key_name]
    if response_body ~= nil then 
        local xobject = xml.eval(response_body)
        local xapplication = xobject:find("application")
        if xapplication ~= nil then
            local xtable = {}
            for k, v in pairs(xapplication) do
                if v ~= nil and type(v) == "table" then 
                    xtable[v:tag()] = k
                end
            end

            local key = xapplication[xtable[user_id_name]]
            if key ~= nil then 
                if debug then
                    ngx.log(ngx.CRIT, "[moesif] Successfully fetched the userId ")
                end
                scale_user_id_dict[auth_key_name] = key[1]
            else 
                if debug then
                    ngx.log(ngx.CRIT, "[moesif] The user_id_name provided by user does not exist ")
                end
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
end

-- Set User Id
function set_user_id(auth_key_name, debug)
    if nonEmpty(scale_user_id_dict[auth_key_name]) then
        if debug then
            ngx.log(ngx.CRIT, "[moesif] Using the previously fetched 3Scale userId ")
        end
        ngx.var.user_id = scale_user_id_dict[auth_key_name]
    else
        if debug then
            ngx.log(ngx.CRIT, "[moesif] No 3Scale userId found ")
        end
    end
end

-- Function to check if the application config is fetched
function is_app_config_fetched(ok, err, debug)
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

-- 3Scale application configuration helper function
function config_helper(config, user_id_name, auth_api_key, auth_app_id, auth_app_key_pair, is_auth_pair_method, debug)
    local ok, err = nil, nil
    if is_auth_pair_method then 
        if scale_config_response_dict[auth_app_id .. "-" .. auth_app_key_pair] == nil or (os.time() > (scale_last_updated_time_dict[auth_app_id .. "-" .. auth_app_key_pair] + 3600)) then
            ok, err = ngx.timer.at(0, get_3Scale_config, config, auth_api_key, auth_app_id, auth_app_key_pair, is_auth_pair_method, debug)
            is_app_config_fetched(ok, err, debug)
        end
    else 
        if scale_config_response_dict[auth_api_key] == nil or (os.time() > (scale_last_updated_time_dict[auth_api_key] + 3600)) then
            ok, err = ngx.timer.at(0, get_3Scale_config, config, auth_api_key, auth_app_id, auth_app_key_pair, is_auth_pair_method, debug)
            is_app_config_fetched(ok, err, debug)
        end
    end
    
    if is_auth_pair_method then
        if scale_config_response_dict[auth_app_id .. "-" .. auth_app_key_pair] ~= nil then
            if debug then
                ngx.log(ngx.CRIT, "[moesif] Using the previously fetched 3Scale application configuration ")
            end
            parseXML(user_id_name, auth_app_id .. "-" .. auth_app_key_pair, debug)
        end
    else 
        if scale_config_response_dict[auth_api_key] ~= nil then
            if debug then
                ngx.log(ngx.CRIT, "[moesif] Using the previously fetched 3Scale application configuration ")
            end
            parseXML(user_id_name, auth_api_key, debug)
        end
    end
end

if nonEmpty(config:get("3scale_domain")) and nonEmpty(config:get("3scale_access_token")) then
    
    local debug = config:get("debug")
    local auth_api_key = nil
    local auth_app_id = nil
    local auth_app_key_pair = nil
    local user_id_name = string.lower(config:get("3scale_user_id_name"))
    local auth_api_key_name = string.lower(config:get("3scale_auth_api_key"))
    local auth_app_id_name = string.lower(config:get("3scale_auth_app_id"))
    local auth_app_key_pair_name = string.lower(config:get("3scale_auth_app_key_pair"))

    -- Read Request headers / query params
    local req_headers = ngx.req.get_headers()
    local req_query_params = ngx.req.get_uri_args()
    
    -- Fetch credential from request header or query parameter location
    auth_api_key = fetch_credentials(auth_api_key_name, req_headers, req_query_params)
    auth_app_id = fetch_credentials(auth_app_id_name, req_headers, req_query_params)
    auth_app_key_pair = fetch_credentials(auth_app_key_pair_name, req_headers, req_query_params)

    -- Authentication Mode
    local is_auth_pair_method = nil
    if nonEmpty(auth_api_key) then
        is_auth_pair_method = false
    else
        is_auth_pair_method = true
    end

    if is_auth_pair_method then 
        if nonEmpty(auth_app_id) and nonEmpty(auth_app_key_pair) then
            config_helper(config, user_id_name, nil, auth_app_id, auth_app_key_pair, true, debug)
            set_user_id(auth_app_id .. "-" .. auth_app_key_pair, debug)
        else
            if debug then
                ngx.log(ngx.CRIT, "No 3Scale userId found")
            end
        end 
    else 
        if nonEmpty(auth_api_key) then 
            config_helper(config, user_id_name, auth_api_key, nil, nil, false, debug)
            set_user_id(auth_api_key, debug)
        else
            if debug then
                ngx.log(ngx.CRIT, "No 3Scale userId found")
            end
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