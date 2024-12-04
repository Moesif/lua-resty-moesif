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

-- Read data from the socket
-- @param `socket`  socket
-- @param `config`  Configuration table
-- @return `response` a string with the api call response details
function _M.read_socket_data(socket, config)
  socket:settimeout(config.timeout)
  local response, err, partial = socket:receive("*a")
  if (not response) and (err ~= 'timeout')  then
    return nil, err
  end
  response = response or partial
  if not response then return nil, 'timeout' end
  return response, nil
end

-- Parse host url
-- @param `url`  host url
-- @return `parsed_url`  a table with host details like domain name, port, path etc
function _M.parse_url(host_url)
  local parsed_url = url.parse(host_url)
  if not parsed_url.port then
    if parsed_url.scheme == "http" then
      parsed_url.port = 80
     elseif parsed_url.scheme == HTTPS then
      parsed_url.port = 443
     end
  end
  if not parsed_url.path then
    parsed_url.path = "/"
  end
  return parsed_url
end

-- function to fetch jwt token payload
function _M.fetch_token_payload(token)
  -- Split the bearer token by dot(.)
  local split_token = {}
  for line in token:gsub("%f[.]%.%f[^.]", "\0"):gmatch"%Z+" do 
      table.insert(split_token, line)
   end
   return split_token
end

-- function to parse user id from authorization/user-defined headers
function _M.parse_authorization_header(token, field)
  
  -- Decode the payload
  local base64_decode_ok, payload = pcall(base64.decode, token)
  if base64_decode_ok then
    -- Convert the payload into table
    local json_decode_ok, decoded_payload = pcall(cjson.decode, payload)
    if json_decode_ok then
      -- Fetch the user_id
      if type(decoded_payload) == "table" and next(decoded_payload) ~= nil then 
        -- Convert keys to lowercase
        for k, v in pairs(decoded_payload) do
          decoded_payload[string.lower(k)] = v
        end   
        if decoded_payload[field] ~= nil then 
          return tostring(decoded_payload[field])
        end
      end
    end
  end
  return nil
end

-- Function to perform the regex matching with event value and condition value
-- @param  `event_value`     Value associated with event (request)
-- @param  `condition_value` Value associated with the regex config condition
-- @return `regex_matched`   Boolean flag to determine if the regex match was successful 
local function regex_match (event_value, condition_value)
  -- Perform regex match between event value and regex config condition value
  return string.match(event_value, condition_value)
end

-- Function to fetch the sample rate and determine if request needs to be block or not
-- @param  `gr_regex_configs`        Regex configs associated with the governance rule
-- @param  `request_config_mapping`  Config associated with the request
-- @return `sample_rate, block`      Sample rate and boolean flag (block or not)
function _M.fetch_sample_rate_block_request_on_regex_match(gr_regex_configs, request_config_mapping)
  -- Iterate through the list of governance rule regex configs
  for _, regex_rule in pairs(gr_regex_configs) do
      -- Fetch the sample rate
      local sample_rate = regex_rule["sample_rate"]
      -- Fetch the conditions
      local conditions = regex_rule["conditions"]
      -- Bool flag to determine if the regex conditions are matched
      local regex_matched = nil 
      -- Create a table to hold the conditions mapping (path and value)
      local condition_table = {}

      -- Iterate through the regex rule conditions and map the path and value
      for _, condition in pairs(conditions) do
          -- Add condition path -> value to the condition table
          condition_table[condition["path"]] = condition["value"]
      end

      -- Iterate through conditions table and perform `and` operation between each conditions
      for path, values in pairs(condition_table) do 
          -- Check if the path exists in the request config mapping
          if request_config_mapping[path] ~= nil then 
              -- Fetch the value of the path in request config mapping
              local event_data = request_config_mapping[path]
              -- Perform regex matching with event value
              regex_matched = regex_match(event_data, values)     
          else 
              -- Path does not exists in request config mapping, so no need to match regex condition rule
              regex_matched = false
          end
          
          -- If one of the rule does not match, skip the condition and avoid matching other rules for the same condition
          if not regex_matched then 
              break
          end
      end

      -- If regex conditions matched, return sample rate and block request (true)
      if regex_matched then 
          return sample_rate, true
      end
  end
  -- If regex conditions are not matched, return default sample rate (nil) and do not block request (false)
  return nil, false
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
