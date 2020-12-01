local url = require "socket.url"
local HTTPS = "https"
local _M = {}
local cjson = require "cjson"
local base64 = require "base64"

-- Read data from the socket
-- @param `socket`  socket
-- @param `config`  Configuration table
-- @return `response` a string with the api call response details
function _M.read_socket_data(socket, config)
  socket:settimeout(config:get("timeout"))
  local response, err, partial = socket:receive("*a")
  if (not response) and (err ~= 'timeout')  then
    return nil, err
  end
  response = response or partial
  if not response then return nil, 'timeout' end
  return response
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

-- function to parse user id from authorization/user-defined headers
function _M.parse_authorization_header(token, field)
  
  -- Decode the payload
  local base64_decode_ok, payload = pcall(base64.decode, token)
  if base64_decode_ok then
    -- Convert the payload into table
    local json_decode_ok, decoded_payload = pcall(cjson.decode, payload)
    if json_decode_ok then
      -- Fetch the user_id
      if type(decoded_payload) == "table" and next(decoded_payload) ~= nil and decoded_payload[field] ~= nil then 
        return tostring(decoded_payload[field])
      end
    end
  end
  return nil
end

return _M
