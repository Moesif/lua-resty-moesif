local _M = {}

local moesif_client = require "moesifapi.lua.moesif_client"
local socket = require "socket"
local helpers = require "helpers"

function _M.read_request_body()
    local start_access_phase_time = socket.gettime()*1000
    
    local req_body, res_body = "", ""
    local req_post_args = {}
    local err = nil
    local mimetype = nil

    local config = helpers.set_default_config_value(ngx.shared.moesif_conf)
    local method = ngx.req.get_method()
    local headers = ngx.req.get_headers()
    local content_length = headers["content-length"]

    local success, err = pcall(function()
        ngx.req.read_body()
        local read_request_body = ngx.req.get_body_data()

        if (content_length == nil and read_request_body ~= nil and string.len(read_request_body) <= config:get("request_max_body_size_limit")) or (content_length ~= nil and tonumber(content_length) <= config:get("request_max_body_size_limit")) then            
            req_body = read_request_body
            local content_type = headers["content-type"]
            if content_type and string.find(content_type:lower(), "application/x-www-form-urlencoded", nil, true) then
                req_post_args, err, mimetype = ngx.req.get_post_args()
              end
        end
    end)

    ngx.ctx.moesif = {
        req_body = req_body,
        res_body = res_body,
        req_post_args = req_post_args
      }

    moesif_client.govern_request(config, start_access_phase_time, method, headers)
end

_M.read_request_body()

return _M
