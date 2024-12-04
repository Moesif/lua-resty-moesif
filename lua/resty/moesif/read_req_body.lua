local _M = {}

local moesif_client = require "moesifapi.lua.moesif_client"
local socket = require "socket"
local helpers = require "helpers"
 
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

-- local config = ngx.shared.moesif_conf
-- config = moesif_client.set_default_config_value(config)
local config = helpers.set_default_config_value(ngx.shared.moesif_conf)

local req_get_method = ngx.req.get_method()
local req_get_headers = ngx.req.get_headers()

ngx.log(ngx.DEBUG, "[moesif] req_get_methody: ", dump(req_get_method))
ngx.log(ngx.DEBUG, "[moesif] req_get_headers: ", dump(req_get_headers))
ngx.log(ngx.DEBUG, "[moesif] config: ", dump(config))

for _, key in ipairs({"application_id", "debug"}) do
    local value = config:get(key)
    ngx.log(ngx.ERR, "Key: ", key, ", Value: ", dump(value) or "nil")
end

function _M.read_request_body()
    local start_access_phase_time = socket.gettime()*1000
    
    -- local req_body = ""
    local req_body, res_body = "", ""
    -- TODO: Figure out
    local req_post_args = {}
    local success, err = pcall(function()
        ngx.req.read_body()
        req_body = ngx.req.get_body_data()
        -- keep in memory the bodies for this request
        ngx.var.moesif_req_body = req_body
    end)

    ngx.ctx.moesif = {
        req_body = req_body,
        res_body = res_body,
        req_post_args = req_post_args
      }

    moesif_client.govern_request(config, start_access_phase_time, req_get_method, req_get_headers)
end

_M.read_request_body()

return _M
