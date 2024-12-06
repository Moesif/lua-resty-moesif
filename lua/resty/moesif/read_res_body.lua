local _M = {}

local helpers = require "helpers"

function _M.read_response_body()

    local config = helpers.set_default_config_value(ngx.shared.moesif_conf)
    local moesif_data = ngx.ctx.moesif or {res_body = ""} -- minimize the number of calls to ngx.ctx while fallbacking on default value
    local headers = ngx.resp.get_headers()
    local content_length = headers["content-length"]

    if (content_length == nil) or (tonumber(content_length) <= config:get("response_max_body_size_limit")) then
        local status, err = pcall(function()
            local chunk = ngx.arg[1]
            ngx.ctx.buffered = (ngx.ctx.buffered or "") .. chunk
            moesif_data.res_body = ngx.ctx.buffered
            if ngx.arg[2] then
                ngx.ctx.moesif = moesif_data
            end
        end)
    end
end

_M.read_response_body()

return _M