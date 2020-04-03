local req_body, res_body = "", ""
local req_post_args = {}
ngx.req.read_body()
req_body = ngx.req.get_body_data()
local content_type = ngx.req.get_headers()["content-type"]
if content_type and string.find(content_type:lower(), "application/x-www-form-urlencoded", nil, true) then
    req_post_args = ngx.req.get_post_args()
end
-- keep in memory the bodies for this request
ngx.ctx.moesif = {
    req_body = req_body,
    res_body = res_body,
    req_post_args = req_post_args
}