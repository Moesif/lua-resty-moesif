local _M = {}
 
function _M.read_request_body()
    local req_body = ""
    local req_post_args = {}
    ngx.req.read_body()
    req_body = ngx.req.get_body_data()
    -- keep in memory the bodies for this request
    ngx.var.req_body = req_body
end

_M.read_request_body()

return _M
