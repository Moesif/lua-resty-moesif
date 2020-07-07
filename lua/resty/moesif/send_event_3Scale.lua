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

if isempty(config:get("3scale_company_id_name")) then
    config:set("3scale_company_id_name", "user_account_id")
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

if isempty(config:get("3Scale_cache_ttl")) then
    config:set("3Scale_cache_ttl", 3600)
end

if isempty(config:get("batch_max_time")) then
    config:set("batch_max_time", 5)
end

if isempty(config:get("is_batch_job_scheduled")) then
    config:set("is_batch_job_scheduled", false)
end

if isempty(config:get("enable_compression")) then
    config:set("enable_compression", true)
end

if isempty(config:get("queue_scheduled_time")) then
    config:set("queue_scheduled_time", os.time{year=1970, month=1, day=1, hour=0})
end

-- User Agent String
local user_agent_string = "lua-resty-moesif-3scale/1.2.6"

function dump(o)
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

-- Get 3Scale Application configuration function
function get_3Scale_config(premature, config, auth_api_key, auth_app_id, auth_app_key_pair, is_auth_pair_method, user_id_name, company_id_name, logEvent, message, debug)

    if premature then
        return
    end
    
    local domain_name = string.lower(config:get("3scale_domain"))
    local access_token = config:get("3scale_access_token")
    if debug then
        ngx.log(ngx.ERR, "[moesif] Domain name when fetching 3Scale config - ", domain_name)
        ngx.log(ngx.ERR, "[moesif] Access Token name when fetching 3Scale config - ", access_token)
    end
    local sock, parsed_url = nil, nil
    local auth_key_name

    if is_auth_pair_method then 
        auth_key_name = auth_app_id .. "-" .. auth_app_key_pair
        if debug then
            ngx.log(ngx.ERR, "[moesif] Calling the 3Scale admin api to fetch application context with App_Id-App_Key authentication method - ", auth_key_name)
        end
        sock, parsed_url = connect.get_connection(config, "https://" .. domain_name, "/admin/api/applications/find.xml?access_token=" .. access_token .. "&app_id=" .. auth_app_id .. "&app_key=" .. auth_app_key_pair)
    else 
        auth_key_name = auth_api_key
        if debug then
            ngx.log(ngx.ERR, "[moesif] Calling the 3Scale admin api to fetch application context with API Key (user_key) authentication method - ", auth_key_name)
        end
        sock, parsed_url = connect.get_connection(config, "https://" .. domain_name, "/admin/api/applications/find.xml?access_token=" .. access_token .. "&user_key=" .. auth_api_key)
    end

    -- Prepare the payload
    local payload = string_format("%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\n",
    "GET", parsed_url.path .. "?" .. parsed_url.query, parsed_url.host)

    if debug then
        ngx.log(ngx.ERR, "[moesif] Payload when calling the 3Scale admin api to fetch application context - ", payload)
    end

    local ok, err = sock:send(payload .. "\r\n")
    if not ok then
        if debug then
            ngx.log(ngx.ERR, "[moesif] failed to send data to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
        end
    else
        if debug then
            ngx.log(ngx.ERR, "[moesif] Successfully send request to fetch 3Scale application configuration " , ok)
        end
    end

    -- Read the response
    local config_response = helpers.read_socket_data(sock)
    if debug then
        ngx.log(ngx.ERR, "[moesif] Response after calling the 3Scale admin api to fetch application context - ", config_response)
    end
    ok, err = sock:setkeepalive(10000)
    if not ok then
        if debug then
            ngx.log(ngx.ERR, "[moesif] failed to keepalive to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
        end
    else
        if debug then
            ngx.log(ngx.ERR, "[moesif] success keep-alive", ok)
        end
    end

    local response_body = config_response:match("(%<.*>)")
    if debug then
        ngx.log(ngx.ERR, "[moesif] After fetching the application context from the 3Scale API Response - ", response_body)
    end
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
                    ngx.log(ngx.ERR, "[moesif] Successfully fetched the userId from the application context", key[1])
                end
                if key[1] ~= nil and key[1] ~= "nil" and key[1] ~= "null" and key[1] ~= '' then
                    ngx.shared.user_id_cache:set(auth_key_name, key[1], config:get("3Scale_cache_ttl"))
                    message["user_id"] = key[1]
                else
                    if debug then
                        ngx.log(ngx.ERR, "[moesif] The fetched userId from the application context is empty, skipped caching the userId")
                    end 
                end
            else 
                if debug then
                    ngx.log(ngx.ERR, "[moesif] The user_id_name provided by the user does not exist in the response. The user_id_name provided is - ", user_id_name)
                end
            end

            local companyKey = xapplication[xtable[company_id_name]]
            if companyKey ~= nil then 
                if debug then
                    ngx.log(ngx.ERR, "[moesif] Successfully fetched the companyId from the application context ", companyKey[1])
                end
                if companyKey[1] ~= nil and companyKey[1] ~= "nil" and companyKey[1] ~= "null" and companyKey[1] ~= '' then
                    ngx.shared.company_id_cache:set(auth_key_name, companyKey[1], config:get("3Scale_cache_ttl"))
                    message["company_id"] = companyKey[1]
                else
                    if debug then
                        ngx.log(ngx.ERR, "[moesif] The fetched companyId from the application context is empty, skipped caching the companyId")
                    end 
                end
            else 
                if debug then
                    ngx.log(ngx.ERR, "[moesif] The company_id_name provided by the user does not exist in the response. The company_id_name provided is - ", company_id_name)
                end
            end
        else
            if debug then
                ngx.log(ngx.ERR, "[moesif] application tag does not exist in the application context ")
            end
        end
    else
        if debug then
            ngx.log(ngx.ERR, "[moesif] The response body does not exist or is not in xml format")
        end
    end

    if debug then
        ngx.log(ngx.ERR, "[moesif] Calling the function to log the Event ")
    end

    logEvent(config, message)

    if debug then
        ngx.log(ngx.ERR, "[moesif] Successfully called the function to log the Event ")
    end

    return response_body
end

-- Function to fetch credentials
function fetch_credentials(auth_key_name, headers, queryparams)
    if debug then
        ngx.log(ngx.ERR, "[moesif] Inside the fetch_credentials helper function to fetch key - ", auth_key_name)
        ngx.log(ngx.ERR, "[moesif] Inside the fetch_credentials helper function to fetch key from headers - ", dump(headers))
        ngx.log(ngx.ERR, "[moesif] Inside the fetch_credentials helper function to fetch key from queryparams - ", dump(queryparams))
    end

    local fetched_key = nil
    if headers[auth_key_name] ~= nil then
        fetched_key = headers[auth_key_name]
    else 
        if queryparams[auth_key_name] ~= nil then
            fetched_key = queryparams[auth_key_name]
        end
    end
    return fetched_key
end

-- Set User Id
function set_user_id(auth_key_name, message, debug)
    if nonEmpty(ngx.shared.user_id_cache:get(auth_key_name)) then
        if debug then
            ngx.log(ngx.ERR, "[moesif] Using the previously fetched 3Scale userId from the cache - ", auth_key_name)
        end
        message["user_id"] = ngx.shared.user_id_cache:get(auth_key_name)
    else
        if debug then
            ngx.log(ngx.ERR, "[moesif] No previously fetched 3Scale userId found in the cache - ", auth_key_name)
        end
    end
    return message
end

-- Set Company Id
function set_company_id(auth_key_name, message, debug)
    if nonEmpty(ngx.shared.company_id_cache:get(auth_key_name)) then
        if debug then
            ngx.log(ngx.ERR, "[moesif] Using the previously fetched 3Scale companyId from the cache - ", auth_key_name)
        end
        message["company_id"] = ngx.shared.company_id_cache:get(auth_key_name)
    else
        if debug then
            ngx.log(ngx.ERR, "[moesif] No previously fetched 3Scale companyId found in the cache - ", auth_key_name)
        end
    end
    return message
end

-- Function to check if the application config is fetched
function is_app_config_fetched(ok, err, debug)
    if not ok then
        if debug then
            ngx.log(ngx.ERR, "[moesif] failed to get 3Scale application config ", err)
        end
    else
        if debug then
            ngx.log(ngx.ERR, "[moesif] successfully fetched the 3Scale application configuration" , ok)
        end
    end
end

-- Prepare the Message
local message = moesif_ser.prepare_message(config) 

 -- Execute/Log message
function logEvent(config, message)
    log.execute(config, message, user_agent_string, config:get("debug"))
end

-- Log Event
if isempty(config:get("application_id")) then
    ngx.log(ngx.ERR, "[moesif] Please provide the Moesif Application Id");
  else
      if nonEmpty(config:get("3scale_domain")) and nonEmpty(config:get("3scale_access_token")) then
      
          local debug = config:get("debug")
          if debug then 
            ngx.log(ngx.ERR, "[moesif] 3Scale accessToken and domainName are provided. Will fetch the application configuration. - ")
          end

          local auth_api_key = nil
          local auth_app_id = nil
          local auth_app_key_pair = nil
          local user_id_name = string.lower(config:get("3scale_user_id_name"))
          local company_id_name = string.lower(config:get("3scale_company_id_name"))
          local auth_api_key_name = string.lower(config:get("3scale_auth_api_key"))
          local auth_app_id_name = string.lower(config:get("3scale_auth_app_id"))
          local auth_app_key_pair_name = string.lower(config:get("3scale_auth_app_key_pair"))

          if debug then 
            ngx.log(ngx.ERR, "[moesif] 3Scale User Id Name - ", user_id_name)
            ngx.log(ngx.ERR, "[moesif] 3Scale Company Id Name - ", company_id_name)
            ngx.log(ngx.ERR, "[moesif] 3Scale Auth API Key Name - ", auth_api_key_name)
            ngx.log(ngx.ERR, "[moesif] 3Scale Auth App Id Name - ", auth_app_id_name)
            ngx.log(ngx.ERR, "[moesif] 3Scale Auth App Key Pari Name - ", auth_app_key_pair_name)
         end
      
          -- Read Request headers / query params
          local req_headers = ngx.req.get_headers()
          if debug then 
            ngx.log(ngx.ERR, "[moesif] Reading the request headers to fetch the credentials like app_id, app_key or user_key - ", dump(req_headers))
          end
          local req_query_params = ngx.req.get_uri_args()
          if debug then 
            ngx.log(ngx.ERR, "[moesif] Reading the request query params to fetch the credentials like app_id, app_key or user_key - ", dump(req_query_params))
          end
      
          -- Fetch credential from request header or query parameter location
          auth_api_key = fetch_credentials(auth_api_key_name, req_headers, req_query_params)
          auth_app_id = fetch_credentials(auth_app_id_name, req_headers, req_query_params)
          auth_app_key_pair = fetch_credentials(auth_app_key_pair_name, req_headers, req_query_params)

          if debug then
            ngx.log(ngx.ERR, "[moesif] Auth Api key after reading the request headers and query params - ", auth_api_key)
            ngx.log(ngx.ERR, "[moesif] Auth App Id after reading the request headers and query params - ", auth_app_id)
            ngx.log(ngx.ERR, "[moesif] Auth App key Pair after reading the request headers and query params - ", auth_app_key_pair)
          end
      
          -- Authentication Mode
          if nonEmpty(auth_app_id) and nonEmpty(auth_app_key_pair) then
            message["session_token"] = auth_app_key_pair
            if nonEmpty(ngx.shared.user_id_cache:get(auth_app_id .. "-" .. auth_app_key_pair)) or nonEmpty(ngx.shared.company_id_cache:get(auth_app_id .. "-" .. auth_app_key_pair)) then
                if debug then 
                    ngx.log(ngx.ERR, "[moesif] Calling the helper function to Set User ID with AppId and App_Key Auth method - ", auth_app_id .. "-" .. auth_app_key_pair)
                end
                message = set_user_id(auth_app_id .. "-" .. auth_app_key_pair, message, debug)
                if debug then 
                    ngx.log(ngx.ERR, "[moesif] Calling the helper function to Set Company ID with AppId and App_Key Auth method - ", auth_app_id .. "-" .. auth_app_key_pair)
                end
                message = set_company_id(auth_app_id .. "-" .. auth_app_key_pair, message, debug)
                if debug then 
                    ngx.log(ngx.ERR, "[moesif] Log the Event for AppId and App_Key Auth method - ", auth_app_id .. "-" .. auth_app_key_pair)
                end
                logEvent(config, message)
            else
                if debug then 
                  ngx.log(ngx.ERR, "[moesif] Calling the function to fetch the 3Scale config with AppId and App_Key Auth method and log the Event - ", auth_app_id .. "-" .. auth_app_key_pair)
                end
                authPairConfig, authPairConfigErr = ngx.timer.at(0, get_3Scale_config, config, auth_api_key, auth_app_id, auth_app_key_pair, true, user_id_name, company_id_name, logEvent, message, debug)
                if not authPairConfig then
                    if debug then
                        ngx.log(ngx.ERR, "[moesif] Error while getting the 3Scale Application config for AppId and App_Key Auth method  ", authPairConfigErr)
                    end
                end
            end
          elseif nonEmpty(auth_api_key) then 
              message["session_token"] = auth_api_key
              if nonEmpty(ngx.shared.user_id_cache:get(auth_api_key)) or nonEmpty(ngx.shared.company_id_cache:get(auth_api_key)) then
                  if debug then 
                    ngx.log(ngx.ERR, "[moesif] Calling the helper function to Set User ID with API Key (user_key) Auth method - ", auth_api_key)
                  end
                  message = set_user_id(auth_api_key, message, debug)
                  if debug then 
                    ngx.log(ngx.ERR, "[moesif] Calling the helper function to Set Company ID with API Key (user_key) Auth method - ", auth_api_key)
                  end
                  message = set_company_id(auth_api_key, message, debug)
                  if debug then 
                    ngx.log(ngx.ERR, "[moesif] Log the Event for API Key (user_key) Auth method - ", auth_api_key)
                  end
                  logEvent(config, message)
              else
                  if debug then 
                    ngx.log(ngx.ERR, "[moesif] Calling the function to fetch the 3Scale config with API Key (user_key) Auth method and log the Event - ", auth_api_key)
                  end
                  authKeyConfig, authKeyConfigErr = ngx.timer.at(0, get_3Scale_config, config, auth_api_key, auth_app_id, auth_app_key_pair, false, user_id_name, company_id_name, logEvent, message, debug)
                  if not authKeyConfig then
                      if debug then
                          ngx.log(ngx.ERR, "[moesif] Error while getting the 3Scale Application config for API Key (user_key) Auth method  ", authKeyConfigErr)
                      end
                  end
              end
          else
              if debug then
                  ngx.log(ngx.ERR, "No 3Scale userId found as authentication key - user_key or app_id/app_key is not provided in headers or query params.")
              end
              logEvent(config, message)
          end
      else
          if config:get("debug") then 
              ngx.log(ngx.ERR, "3Scale accessToken or userKey or domainName is not provided")  
          end
          logEvent(config, message)
      end
  end