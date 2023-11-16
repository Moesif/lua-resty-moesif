local _M = {}
 
function _M.read_response_body()
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
end

_M.read_response_body()

return _M