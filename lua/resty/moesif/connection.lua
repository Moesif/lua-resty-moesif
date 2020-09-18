local _M = {}
local helper = require "helpers"
local HTTPS = "https"
local ngx_log = ngx.log
local ngx_log_ERR = ngx.ERR
local session 
local sessionerr

-- Create new connection
-- @param `conf`  Configuration table
-- @param `api_endpoint`  http endpoint details
-- @param `url_path`  api endpoint
-- @param `sock` Socket object
-- @return `sock` Socket object
-- @return `parsed_url` a table with host details like domain name, port, path etc
function _M.get_connection(config, api_endpoint, url_path, sock)
  local parsed_url = helper.parse_url(api_endpoint..url_path)
  local host = parsed_url.host
  local port = tonumber(parsed_url.port)
  local debug = config:get("debug")

  sock:settimeout(config:get("connect_timeout"))
  local ok, err = sock:connect(host, port)
  if not ok then
    if debug then
      ngx_log(ngx_log_ERR, "[moesif] failed to connect to " .. host .. ":" .. tostring(port) .. ": ", err)
    end
    return
  else
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] Successfully created connection " , ok)
    end
  end

  if parsed_url.scheme == HTTPS then
    if session ~= nil then 
      session, sessionerr = sock:sslhandshake(session, host, false)
    else 
      session, sessionerr = sock:sslhandshake(true, host, false)
    end

    if sessionerr then
      if debug then
        ngx_log(ngx.ERR, "[moesif] failed to do SSL handshake with " .. host .. ":" .. tostring(port) .. ": ", err)
      end
      session = nil
      return nil, nil
    end
  end
  return sock, parsed_url
end

return _M
