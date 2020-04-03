local chunk = ngx.arg[1]
local moesif_data = ngx.ctx.moesif or {res_body = ""} -- minimize the number of calls to ngx.ctx while fallbacking on default value
moesif_data.res_body = moesif_data.res_body .. chunk
ngx.ctx.moesif = moesif_data