local helpers = require "helpers"
local HTTPS = "https"
local _M = {}

-- Create new connection
-- @param `url_path`  api endpoint
-- @return `sock` Socket object
-- @return `parsed_url` a table with host details like domain name, port, path etc
function _M.get_connection(config, url_path)
  local parsed_url = helpers.parse_url(config:get("api_endpoint")..url_path)
  local host = parsed_url.host
  local port = tonumber(parsed_url.port)
  local sock = ngx.socket.tcp()
  local debug = config:get("debug")

  sock:settimeout(config:get("timeout"))
  local ok, err = sock:connect(host, port)
  if not ok then
    if debug then
      ngx.log(ngx.CRIT, "[moesif] failed to connect to " .. host .. ":" .. tostring(port) .. ": ", err)
    end
    return
  else
    if debug then
      ngx.log(ngx.CRIT, "[moesif] Successfully created connection " , ok)
    end
  end

  if parsed_url.scheme == HTTPS then
    local _, err = sock:sslhandshake(true, host, false)
    if err then
      if debug then
        ngx.log(ngx.CRIT, "[moesif] failed to do SSL handshake with " .. host .. ":" .. tostring(port) .. ": ", err)
      end
    end
  end
  return sock, parsed_url
end

return _M
