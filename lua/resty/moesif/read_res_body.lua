local _M = {}

local helpers = require "helpers"

function _M.read_response_body()

    local headers = ngx.resp.get_headers()
    local content_length = headers["content-length"]

    local config = helpers.set_default_config_value(ngx.shared.moesif_conf)

    if (content_length == nil) or (tonumber(content_length) <= config:get("response_max_body_size_limit")) then

        local status, err = pcall(function()
            local chunk = ngx.arg[1]
            ngx.ctx.buffered = (ngx.ctx.buffered or "") .. chunk
            if ngx.arg[2] then
                ngx.var.moesif_res_body = ngx.ctx.buffered
            end
        end)

        if not status then
            ngx.var.moesif_res_body = nil
        end
    else
        ngx.var.moesif_res_body = nil
    end
end

_M.read_response_body()

return _M