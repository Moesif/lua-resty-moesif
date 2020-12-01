# Moesif Plugin for NGINX OpenResty

[NGINX](https://www.nginx.com/) [OpenResty](https://openresty.org/en/) plugin that logs API calls to [Moesif](https://www.moesif.com) for API analytics and monitoring.
This plugin can be used with a generic NGINX OpenResty installation or for API gateways that are built on top of OpenResty such as [3Scale API Gateway](https://www.3scale.net/). 

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

## How to use (Generic OpenResty)

Edit your `nginx.conf` file to configure Moesif OpenResty plugin:
Replace `/usr/local/openresty/luajit/share/lua/5.1/resty` with the correct lua plugin installation path, if necessary.

_If you're unsure of the installation path, you can find it via: `find / -name "moesif" -type d`. Sometimes luarocks installs packages in multiple locations, just choose one._

```nginx
lua_shared_dict moesif_conf 5m;

init_by_lua_block {
   local config = ngx.shared.moesif_conf;
   config:set("application_id", "Your Moesif Application Id")
}

lua_package_cpath ";;${prefix}?.so;${prefix}src/?.so;/usr/share/lua/5.1/lua/resty/moesif/?.so;/usr/share/lua/5.1/?.so;/usr/lib64/lua/5.1/?.so;/usr/lib/lua/5.1/?.so;/usr/local/openresty/luajit/share/lua/5.1/lua/resty?.so";
lua_package_path ";;${prefix}?.lua;${prefix}src/?.lua;/usr/share/lua/5.1/lua/resty/moesif/?.lua;/usr/share/lua/5.1/?.lua;/usr/lib64/lua/5.1/?.lua;/usr/lib/lua/5.1/?.lua;/usr/local/openresty/luajit/share/lua/5.1/lua/resty?.lua";

server {
  listen 80;
  resolver 8.8.8.8;

  # Customer identity variables that Moesif will read downstream
  set $moesif_user_id "";
  set $moesif_company_id "";

  # Request/Response body variable that Moesif will use downstream
  set $moesif_req_body "";
  set $moesif_res_body "";

  # Optionally, identify the user and the company (account)
  # from a request or response header, query param, NGINX var, etc
  header_filter_by_lua_block  { 
    ngx.var.moesif_user_id = ngx.req.get_headers()["X-User-Id"]
    ngx.var.moesif_company_id = ngx.req.get_headers()["X-Company-Id"]
  }

  access_by_lua_file /usr/local/openresty/luajit/share/lua/5.1/resty/moesif/read_req_body.lua;
  body_filter_by_lua_file /usr/local/openresty/luajit/share/lua/5.1/resty/moesif/read_res_body.lua;
  log_by_lua_file /usr/local/openresty/luajit/share/lua/5.1/resty/moesif/send_event.lua;

  # Sample Hello World API
  location /api {
     add_header Content-Type "application/json";
     return 200 '{\r\n  \"message\": \"Hello World\",\r\n  \"completed\": true\r\n}';
  }
}
```

## How to use (3Scale API Gateway)

Installing Moesif plugin for [3Scale API Gateway](https://www.3scale.net/) is the same as vanilla installation except for two changes:
1. Add 3scale specific configuration options to fetch additional user context from 3scale management API
2. Replace `send_event.lua`, with `send_event_3Scale.lua` 

Edit your `nginx.conf` file to configure Moesif OpenResty plugin:
Replace `/usr/share/lua/5.1/lua/resty` with the correct lua plugin installation path, if necessary.

_If you're unsure of the installation path, you can find it via: `find / -name "moesif" -type d`. Sometimes luarocks installs packages in multiple locations, just choose one._

Below is a sample configuration for 3scale:

```nginx
lua_shared_dict moesif_conf 5m;
lua_shared_dict user_id_cache 5m;
lua_shared_dict company_id_cache 5m;

init_by_lua_block {
   local config = ngx.shared.moesif_conf;
   config:set("application_id", "Your Moesif Application Id")
   config:set("3scale_domain", "YOUR_ACCOUNT-admin.3scale.net")
   config:set("3scale_access_token", "Your 3scale Access Token")
}

lua_package_cpath ";;${prefix}?.so;${prefix}src/?.so;/usr/share/lua/5.1/lua/resty/moesif/?.so;/usr/share/lua/5.1/?.so;/usr/lib64/lua/5.1/?.so;/usr/lib/lua/5.1/?.so;/usr/local/openresty/luajit/share/lua/5.1/lua/resty?.so";
lua_package_path ";;${prefix}?.lua;${prefix}src/?.lua;/usr/share/lua/5.1/lua/resty/moesif/?.lua;/usr/share/lua/5.1/?.lua;/usr/lib64/lua/5.1/?.lua;/usr/lib/lua/5.1/?.lua;/usr/local/openresty/luajit/share/lua/5.1/lua/resty?.lua";

server {
  listen 80;
  resolver 8.8.8.8;

  # Customer identity variables that Moesif will read downstream
  # Set automatically from 3scale management API
  set $moesif_user_id "";
  set $moesif_company_id "";

  # Request/Response body variable that Moesif will use downstream
  set $moesif_req_body "";
  set $moesif_res_body "";

  access_by_lua_file /usr/share/lua/5.1/lua/resty/moesif/read_req_body.lua;
  body_filter_by_lua_file /usr/share/lua/5.1/lua/resty/moesif/read_res_body.lua;
  log_by_lua_file /usr/share/lua/5.1/lua/resty/moesif/send_event_3Scale.lua;

  # Sample Hello World API
  location /api {
      add_header Content-Type "application/json";
      return 200 '{\r\n  \"message\": \"Hello World\",\r\n  \"completed\": true\r\n}';
  }
}
```

## Configuration options

Static options that are set once on startup such as in `init_by_lua_block`.

#### __`application_id`__
(__required__), _string_, Application Id to authenticate with Moesif.

#### __`disable_capture_request_body`__
(optional) _boolean_, An option to disable logging of request body. `false` by default.

#### __`disable_capture_response_body`__
(optional) _boolean_, An option to disable logging of response body. `false` by default.

#### __`request_header_masks`__
(optional) _string_, An option to mask a specific request header fields. Separate multiple fields by comma such as `"header_a, header_b"`

#### __`request_body_masks`__
(optional) _string_, An option to mask a specific request body fields. Separate multiple fields by comma such as `"field_a, field_b"`

#### __`response_header_masks`__
(optional) _string_, An option to mask a specific response header fields. Separate multiple fields by comma such as `"header_a, header_b"`

#### __`response_body_masks`__
(optional) _string_, An option to mask a specific response body fields. Separate multiple fields by comma such as `"field_a, field_b"`

#### __`disable_transaction_id`__
(optional) _boolean_, Setting to true will prevent insertion of the <code>X-Moesif-Transaction-Id</code> header. `false` by default.

#### __`debug`__
(optional) _boolean_, Set to true to print debug logs if you're having integration issues.

#### __`authorization_header_name`__
(optional) _string_, Request header field name to use to identify the User in Moesif. Defaults to `authorization`.

#### __`authorization_user_id_field`__
(optional) _string_, A field name use to parse the User from authorization header in Moesif. Defaults to `sub`.

### 3Scale specific options

If you installed for [3Scale API Gateway](https://www.3scale.net/) using `send_event_3Scale.lua`, 
you have additional static options:

#### __`3scale_domain`__
(__required__), _string_, your full 3Scale admin domain such as  `YOUR_ACCOUNT-admin.3scale.net`.

#### __`3scale_access_token`__
(__required__), _string_, an admin `ACCESS_TOKEN`, that you can get from your 3scale admin portal.

#### __`3scale_user_id_name`__
(optional) _string_, The 3scale field name from 3scale's application XML entity used to identify the user in Moesif. 
This is `id` by default., but other valid examples include `user_account_id` and `service_id`. [More info](https://access.redhat.com/documentation/en-us/red_hat_3scale_api_management/2.8/html-single/admin_portal_guide/index#find-application).

#### __`3scale_auth_api_key`__
(optional) _string_, If you configured 3scale to authenticate via a single _user_key_ string, set the field name here. 
This is `user_key` by default. [More info](https://access.redhat.com/documentation/en-us/red_hat_3scale_api_management/2.8/html/administering_the_api_gateway/authentication-patterns#api_key).

#### __`3scale_auth_app_id`__
(optional) _string_, If you configured 3scale to authenticate via _app_id_ and _app_key_ pair, set app_id field name here.  
This is `app_id` by default. If set, you need to set `3scale_auth_app_key_pair`. [More info](https://access.redhat.com/documentation/en-us/red_hat_3scale_api_management/2.8/html/administering_the_api_gateway/authentication-patterns#app_id_and_app_key_pair).

#### __`3scale_auth_app_key_pair`__
(optional) _string_, If you configured 3scale to authenticate via _app_id_ and _app_key_ pair, set app_key field name here. 
This is `app_key` by default. If set, you need to set `3scale_auth_app_id`. [More info](https://access.redhat.com/documentation/en-us/red_hat_3scale_api_management/2.8/html/administering_the_api_gateway/authentication-patterns#app_id_and_app_key_pair).

## Dynamic variables

Variables that are dynamic for each HTTP request. Set these variables on the `ngx.var` dictionary such as in `header_filter_by_lua_block` 
or in a `body_filter_by_lua_block`.

```nginx
header_filter_by_lua_block  { 
  -- Read user id from request query param
  ngx.var.moesif_user_id     = ngx.req.arg_user_id
  
  -- Read version from request header
  ngx.var.moesif_api_version = ngx.req.get_headers()["X-API-Version"]
}

body_filter_by_lua_block  { 
  -- Read company id from response header
  ngx.var.moesif_company_id  = ngx.resp.get_headers()["X-Company-Id"]
}
```

#### __`moesif_user_id`__
(optional) _string_, Attribute API requests to individual users so you can track who calling your API. This can also be used with `ngx.var.moesif_company_id` to track account level usage.
_If you installed for 3scale, you do not need to set this field as this is handled automatically_

#### __`moesif_company_id`__
(optional) _string_, Attribute API requests to companies or accounts so you can track who calling your API. This can be used with `ngx.var.moesif_company_id`. 
_If you installed for 3scale, you do not need to set this field as this is handled automatically_

#### __`moesif_api_version`__
(optional) _boolean_, An optional API Version you want to tag this request with.

## Troubleshooting

### Response body not being logged
If you find response body is not being logged in Moesif, your setup may require
an internal `proxy_pass` which can be added with a few lines of code to your `nginx.conf`.

For the following sample server:
```nginx
server {
  listen 80;
  resolver 8.8.8.8;

  # Sample Hello World API
  location /api {
     add_header Content-Type "application/json";
     return 200 '{\r\n  \"message\": \"Hello World\",\r\n  \"completed\": true\r\n}';
  }
}
```

 One with `proxy_pass` would look like so:

```nginx
server {
  listen 80;
  resolver 8.8.8.8;

  # Sample Hello World API
  location /api {
    proxy_pass http://127.0.0.1:80/internal;
  }

  location /internal {
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
