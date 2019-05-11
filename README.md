# Moesif OpenResty plugin

# Moesif OpenResty plugin

The [Moesif OpenResty plugin](https://github.com/Moesif/lua-resty-moesif) integrates [OpenResty](https://openresty.org/en/)
with [Moesif API Analytics](https://www.moesif.com).

- OpenResty is a dynamic web platform based on NGINX and LuaJIT.
- Moesif is an API analytics and debugging service.

When enabled, this plugin will capture API requests and responses and log to Moesif API Insights for easy inspecting and real-time debugging of your API traffic.
Support for REST, GraphQL, Ethereum Web3, JSON-RPC, SOAP, & more

[Source Code on GitHub](https://github.com/Moesif/lua-resty-moesif)

## How to install

The plugin can be installed using OpenResty Package Manager(opm) by doing:

```shell
opm get Moesif/lua-resty-moesif
```

## Configuraion Options

#### __`application_id`__
(__required__), _string_, is obtained via your Moesif Account, this is required.

#### __`api_version`__
(optional) _boolean_, An optional API Version you want to tag this request with in Moesif. `1.0` by default.

#### __`disable_capture_request_body`__
(optional) _boolean_, An option to disable logging of request body. `false` by default.

#### __`disable_capture_response_body`__
(optional) _boolean_, An option to disable logging of response body. `false` by default.

#### __`request_masks`__
(optional) _string_, An option to mask a specific request body field. To mask multiple fields, seperate it by comma. For Example - "header1, header2"

#### __`response_masks`__
(optional) _string_, An option to mask a specific response body field. To mask multiple fields, seperate it by comma. For Example - "header1, header2"

#### __`disable_transaction_id`__
(optional) _boolean_, Setting to true will prevent insertion of the <code>X-Moesif-Transaction-Id</code> header. `false` by default.

#### __`user_id_header`__
(optional) _string_, Request / Response Header to Identify User. `userId` by default.

#### __`company_id_header`__
(optional) _string_, Request / Response Header to Identify Company. `companyId` by default.

## How to use

Edit your `nginx.conf` file to configure Moesif OpenResty plugin:

```nginx
lua_shared_dict conf 2m;

init_by_lua_block {
   local config = ngx.shared.conf;
   config:set("application_id", "Your Moesif Application Id")
   config:set("api_version", "1.0")
   config:set("disable_capture_request_body", false)
   config:set("disable_capture_response_body", false)
   config:set("request_masks", "req_mask")
   config:set("response_masks", "resp_mask")
   config:set("disable_transaction_id", false)
   config:set("user_id_header", "userId")
   config:set("company_id_header", "companyId")
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
An example Moesif integration based on quick start tutorial of Openresty: [Moesif OpenResty Example](https://github.com/Moesif/lua-resty-moesif-example)

Congratulations! If everything was done corectly, Moesif should now be tracking all network requests that match the route you specified earlier. If you have any issues with set up, please reach out to support@moesif.com.

## Other integrations

To view more more documentation on integration options, please visit __[the Integration Options Documentation](https://www.moesif.com/docs/getting-started/integration-options/).__
