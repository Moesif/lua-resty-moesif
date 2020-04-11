# Moesif Plugin for NGINX OpenResty

NGINX [OpenResty](https://openresty.org/en/) plugin that logs API calls and sends to [Moesif](https://www.moesif.com) for API analytics and log analysis.

[Github Repo](https://github.com/Moesif/lua-resty-moesif)

## How to install

The recommended way to install Moesif is via Luarocks:

```bash
luarocks install --server=http://luarocks.org/manifests/moesif lua-resty-moesif
```

Alternatively, OpenResty provides its own package manager, OPM, which can be used to install Moesif.
Keep in mind OPM is not well maintained and release acceptance may be delayed by a few days, which is why we recommend LuaRocks, if possible.

```bash
opm get Moesif/lua-resty-moesif
```

## Shared Configuration (ngx.shared)

The below options are static for all requests. Set these options on the shared dictionary, `ngx.shared.moesif_conf`:

```nginx
lua_shared_dict moesif_conf 2m;

init_by_lua_block {
   local config = ngx.shared.moesif_conf;
   config:set("application_id", "Your Moesif Application Id")
}
```

#### __`application_id`__
(__required__), _string_, Application Id to authenticate with Moesif. This is required.

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

## Dynamic Variables (ngx.var)

The below variables are dynamic for each request. Set these variables on the `ngx.var` dictionary:

```nginx
header_filter_by_lua_block  { 
  ngx.var.user_id = ngx.resp.get_headers()["User-Id"]
}
```

#### __`user_id`__
(optional) _string_, This enables Moesif to attribute API requests to individual users so you can understand who calling your API. This can be used simultaneously with `company_id`. A company can have one or more users. 

#### __`company_id`__
(optional) _string_, If your business is B2B, this enables Moesif to attribute API requests to companies or accounts so you can understand who is calling your API. This can be used simultaneously with `user_id`. A company can have one or more users. 

#### __`api_version`__
(optional) _boolean_, An optional API Version you want to tag this request with.

#### 3Scale Application configuration

Additionally, if you're using (3Scale API Management)[https://www.3scale.net/] you could use these configuration options.

#### __`3scale_domain`__
(__required__), _string_, 3Scale domain name, for example `YOUR_ACCOUNT-admin.3scale.net`. This is required.

#### __`3scale_access_token`__
(__required__), _string_, an `ACCESS_TOKEN`, that you can get from the 3scale admin portal, and also your `ADMIN_PORTAL_DOMAIN`. This is required.

#### __`3scale_user_id_name`__
(optional) _string_, The key to be used to parse user_id from the application context XML based response like - `id`, `user_account_id`, `service_id`, and more. `id` by default.

#### __`3scale_auth_api_key`__
(optional) _string_, The key which is used to identify and authenticate application via a single string. `user_key` by default.

#### __`3scale_auth_app_id`__
(optional) _string_, The key which is used to identify application. `app_id` by default.

#### __`3scale_auth_app_key_pair`__
(optional) _string_, The key which is used to authenticate the application. `app_key` by default. 

## How to use

Edit your `nginx.conf` file to configure Moesif OpenResty plugin:
Replace `/usr/share/lua/5.1/lua/resty` with the correct plugin installation path, if needed.
This may be logged to screen during installation of luarock. If in doubt, find the path via: `find / -name "moesif" -type d`

```nginx
lua_shared_dict moesif_conf 2m;

init_by_lua_block {
   local config = ngx.shared.moesif_conf;
   config:set("application_id", "Your Moesif Application Id")
}

lua_package_cpath ";;${prefix}?.so;${prefix}src/?.so;/usr/share/lua/5.1/lua/resty/moesif/?.so;/usr/share/lua/5.1/?.so;/usr/lib64/lua/5.1/?.so;/usr/lib/lua/5.1/?.so;/usr/local/openresty/luajit/share/lua/5.1/lua/resty?.so";
lua_package_path ";;${prefix}?.lua;${prefix}src/?.lua;/usr/share/lua/5.1/lua/resty/moesif/?.lua;/usr/share/lua/5.1/?.lua;/usr/lib64/lua/5.1/?.lua;/usr/lib/lua/5.1/?.lua;/usr/local/openresty/luajit/share/lua/5.1/lua/resty?.lua";

server {
  listen 80;
  resolver 8.8.8.8;

  # Default values for Moesif variables
  set $user_id nil;
  set $company_id nil;

  header_filter_by_lua_block  { 

    # Optionally, identify the user such as by a header value
    ngx.var.user_id = ngx.req.get_headers()["User-Id"]

    # Optionally, identify the company (account) such as by a header value
    ngx.var.company_id = ngx.req.get_headers()["Company-Id"]
  }

  access_by_lua_file /usr/share/lua/5.1/lua/resty/moesif/read_req_body.lua;
  body_filter_by_lua_file /usr/share/lua/5.1/lua/resty/moesif/read_res_body.lua;
  log_by_lua_file /usr/share/lua/5.1/lua/resty/moesif/send_event.lua;

  # Sample Hello World API
  location /api {
    add_header Content-Type "application/json";
    return 200 '{\r\n  \"message\": \"Hello World\",\r\n  \"completed\": true\r\n}';
  }
}
```

## Example
An example [Moesif integration](https://github.com/Moesif/lua-resty-moesif-example) is available based on the quick start tutorial of Openresty

Congratulations! If everything was done correctly, Moesif should now be tracking all network requests that match the route you specified earlier. If you have any issues with set up, please reach out to support@moesif.com.

## Other integrations

To view more documentation on integration options, please visit __[the Integration Options Documentation](https://www.moesif.com/docs/getting-started/integration-options/).__
