# Moesif Plugin for NGINX OpenResty

NGINX [OpenResty](https://openresty.org/en/) plugin that logs API calls and sends to [Moesif](https://www.moesif.com) for API analytics and log analysis.

[Github Repo](https://github.com/Moesif/lua-resty-moesif)

## How to install

OpenResty provides its own package manager, OPM, which is the recommended installation method. 
There is also an alternative installation via Luarocks. 

For OPM, install [lua-resty-moesif](https://github.com/Moesif/lua-resty-moesif):

```bash
opm get Moesif/lua-resty-moesif
```

For Luarocks, install the [openresty-plugin-moesif](https://luarocks.org/modules/moesif/openresty-plugin-moesif) rock:
```bash
luarocks install --server=http://luarocks.org/manifests/moesif openresty-plugin-moesif
```

## Configuration Options

#### __`application_id`__
(__required__), _string_, Application Id to authenticate with Moesif. This is required.

#### __`user_id_header`__
(optional) _string_, The Request or Response Header containing the user id. Your downstream service should also set this header with the actual authenticated user id. 

#### __`company_id_header`__
(optional) _string_, The Request or Response Header containing the company id. Your downstream service should also set this header with the actual authenticated company id. 

#### __`api_version`__
(optional) _boolean_, An optional API Version you want to tag this request with in Moesif. `1.0` by default.

#### __`disable_capture_request_body`__
(optional) _boolean_, An option to disable logging of request body. `false` by default.

#### __`disable_capture_response_body`__
(optional) _boolean_, An option to disable logging of response body. `false` by default.

#### __`request_masks`__
(optional) _string_, An option to mask a specific request body fields. Separate multiple fields by comma such as `"field_a, field_b"`

#### __`response_masks`__
(optional) _string_, An option to mask a specific response body fields. Separate multiple fields by comma such as `"field_a, field_b"`

#### __`disable_transaction_id`__
(optional) _boolean_, Setting to true will prevent insertion of the <code>X-Moesif-Transaction-Id</code> header. `false` by default.

#### __`debug`__
(optional) _boolean_, Set to true to print debug logs if you're having integration issues.

## How to use

Edit your `nginx.conf` file to configure Moesif OpenResty plugin:
Replace `/usr/local/openresty/site/lualib` with the correct plugin installation path, if needed.

```nginx
lua_shared_dict conf 2m;

init_by_lua_block {
   local config = ngx.shared.conf;
   config:set("application_id", "Your Moesif Application Id")
   config:set("user_id_header", "X-Forwarded-User")
   config:set("company_id_header", "X-Forwarded-Company")
}


lua_package_path "/usr/local/openresty/site/lualib/plugins/moesif/?.lua;;";

server {
  listen 80;
  resolver 8.8.8.8;

  # This will make sure that any changes to the lua code file is picked up
  # without reloading or restarting nginx
  lua_code_cache off;

  access_by_lua '
    local req_body, res_body = "", ""
    local req_post_args = {}

    ngx.req.read_body()
    req_body = ngx.req.get_body_data()
    local content_type = ngx.req.get_headers()["content-type"]
    if content_type and string.find(content_type:lower(), "application/x-www-form-urlencoded", nil, true) then
      req_post_args = ngx.req.get_post_args()
    end
    ngx.ctx.api_version = ngx.shared.conf:get("api_version")
    -- keep in memory the bodies for this request
    ngx.ctx.moesif = {
      req_body = req_body,
      res_body = res_body,
      req_post_args = req_post_args
    }
  ';

  body_filter_by_lua '
    local chunk = ngx.arg[1]
    local moesif_data = ngx.ctx.moesif or {res_body = ""} -- minimize the number of calls to ngx.ctx while fallbacking on default value
    moesif_data.res_body = moesif_data.res_body .. chunk
    ngx.ctx.moesif = moesif_data
  ';


  location / {
    proxy_pass URL;
    log_by_lua_file /usr/local/openresty/site/lualib/plugins/moesif/send_event.lua;
  }
}
```

## Example
An example [Moesif integration](https://github.com/Moesif/lua-resty-moesif-example) is available based on the quick start tutorial of Openresty

Congratulations! If everything was done corectly, Moesif should now be tracking all network requests that match the route you specified earlier. If you have any issues with set up, please reach out to support@moesif.com.

## Other integrations

To view more documentation on integration options, please visit __[the Integration Options Documentation](https://www.moesif.com/docs/getting-started/integration-options/).__
