local lrucache = require "resty.lrucache"

user_id_cache, uic_err = lrucache.new(10000)  -- allow up to 10000 items in the cache
if not user_id_cache then
    ngx.log(ngx.CRIT, "failed to create the cache: " .. (uic_err or "unknown"))
end
