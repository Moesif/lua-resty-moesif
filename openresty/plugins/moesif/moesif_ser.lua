local ngx_now = ngx.now
local req_get_method = ngx.req.get_method
local req_start_time = ngx.req.start_time
local req_get_headers = ngx.req.get_headers
local res_get_headers = ngx.resp.get_headers
local cjson = require "cjson"
local random = math.random
local _M = {}


-- Function to get the Type of the Ip
function get_ip_type(ip)
  local R = {ERROR = 0, IPV4 = 1, IPV6 = 2, STRING = 3}
  if type(ip) ~= "string" then return R.ERROR end

  -- check for format 1.11.111.111 for ipv4
  local chunks = {ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
  if #chunks == 4 then
    for _,v in pairs(chunks) do
      if tonumber(v) > 255 then return R.STRING end
    end
    return R.IPV4
  end

  -- check for ipv6 format, should be 8 'chunks' of numbers/letters
  -- without leading/trailing chars
  -- or fewer than 8 chunks, but with only one `::` group
  local chunks = {ip:match("^"..(("([a-fA-F0-9]*):"):rep(8):gsub(":$","$")))}
  if #chunks == 8
  or #chunks < 8 and ip:match('::') and not ip:gsub("::","",1):match('::') then
    for _,v in pairs(chunks) do
      if #v > 0 and tonumber(v, 16) > 65535 then return R.STRING end
    end
    return R.IPV6
  end
  return R.STRING
end

-- Function to check if it is valid Ip Address
function is_ip(value)
 ip_type = get_ip_type(value)

 if ip_type == 1 or ip_type == 2 then
  return true
 else
  return false
 end
end


-- Function to get the client Ip from the X-forwarded-for header
function getClientIpFromXForwardedFor(value)

  if value == nil then
    return nil
  end

  if type(value) ~= "string" then
    return nil
  end

  -- x-forwarded-for may return multiple IP addresses in the format:
  -- "client IP, proxy 1 IP, proxy 2 IP"
  -- Therefore, the right-most IP address is the IP address of the most recent proxy
  -- and the left-most IP address is the IP address of the originating client.
  -- source: http://docs.aws.amazon.com/elasticloadbalancing/latest/classic/x-forwarded-headers.html
  -- Azure Web App's also adds a port for some reason, so we'll only use the first part (the IP)
  forwardedIps = {}

  for word in string.gmatch(value, '([^,]+)') do
    ip = string.gsub(word, "%s+", "")
    if string.match(value, ":") then
        splitted = string.match(value, "(.*)%:")
        table.insert(forwardedIps, splitted)
      else
        table.insert(forwardedIps, ip)
    end
  end


  for index, value in ipairs(forwardedIps) do
    if is_ip(value) then
      return value
    end
  end
end


-- Function to get the client Ip
function get_client_ip(req_headers)
  -- Standard headers used by Amazon EC2, Heroku, and others.
  if is_ip(req_headers["x-client-ip"]) then
     return req_headers["x-client-ip"]
  end

  -- Load-balancers (AWS ELB) or proxies.
  xForwardedFor = getClientIpFromXForwardedFor(req_headers["x-forwarded-for"]);
  if (is_ip(xForwardedFor)) then
      return xForwardedFor
  end

  -- Cloudflare.
  -- @see https://support.cloudflare.com/hc/en-us/articles/200170986-How-does-Cloudflare-handle-HTTP-Request-headers-
  -- CF-Connecting-IP - applied to every request to the origin.
  if is_ip(req_headers["cf-connecting-ip"]) then
      return req_headers["cf-connecting-ip"]
  end

  -- Fastly and Firebase hosting header (When forwared to cloud function)
  if (is_ip(req_headers["fastly-client-ip"])) then
      return req_headers["fastly-client-ip"]
  end

  -- Akamai and Cloudflare: True-Client-IP.
  if (is_ip(req_headers["true-client-ip"])) then
      return req_headers["true-client-ip"]
  end

  -- Default nginx proxy/fcgi; alternative to x-forwarded-for, used by some proxies.
  if (is_ip(req_headers["x-real-ip"])) then
      return req_headers["x-real-ip"]
  end

  -- (Rackspace LB and Riverbed's Stingray)
  -- http://www.rackspace.com/knowledge_center/article/controlling-access-to-linux-cloud-sites-based-on-the-client-ip-address
  -- https://splash.riverbed.com/docs/DOC-1926
  if (is_ip(req_headers["x-cluster-client-ip"])) then
      return req_headers["x-cluster-client-ip"]
  end

  if (is_ip(req_headers["x-forwarded"])) then
      return req_headers["x-forwarded"]
  end

  if (is_ip(req_headers["forwarded-for"])) then
      return req_headers["forwarded-for"]
  end

  if (is_ip(req_headers.forwarded)) then
      return req_headers.forwarded
  end

  -- Return remote address
  return ngx.var.remote_addr
end


-- Split the string
local function split(str, character)
  result = {}

  index = 1
  for s in string.gmatch(str, "[^"..character.."]+") do
    result[index] = s
    index = index + 1
  end

  return result
end


-- Mask Body
local function mask_body(body, masks)
  if masks == nil then return body end
  if body == nil then return body end
  for mask_key, mask_value in pairs(masks) do
    if body[mask_value] then body[mask_value] = nil end
      for body_key, body_value in next, body do
          if type(body_value)=="table" then mask_body(body_value, masks) end
      end
  end
  return body
end

-- function to generate uuid
math.randomseed(os.time())
local function uuid()
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
        return string.format('%x', v)
    end)
end

-- Prepare message
function _M.prepare_message(config)
  local moesif_ctx = ngx.ctx.moesif or {}
  local session_token_entity
  local request_body_entity
  local response_body_entity
  local user_id_header
  local user_id_entity
  local company_id_header
  local company_id_entity

  -- User Id
  user_id_header = string.lower(config:get("user_id_header"))
  user_id_entity = ngx.req.get_headers()[user_id_header] or ngx.resp.get_headers()[user_id_header]

  -- Company Id
  company_id_header = string.lower(config:get("company_id_header"))
  company_id_entity = ngx.req.get_headers()[company_id_header] or ngx.resp.get_headers()[company_id_header]

  -- Disable capture and mask request body
  if  config:get("disable_capture_request_body") then
      request_body_entity = nil
    else
      if next(split(config:get("request_masks"), ",")) == nil then
        request_body_entity = moesif_ctx.req_body
      else
        if moesif_ctx.req_body ~= nil then
          ok, mask_result = pcall(mask_body, cjson.decode(moesif_ctx.req_body), split(config:get("request_masks"), ","))
          if not ok then
            request_body_entity = moesif_ctx.req_body
          else
            request_body_entity = cjson.encode(mask_result)
          end
        else
          request_body_entity = moesif_ctx.req_body
        end

      end
    end


  -- Disable capture and mask response body
  if config:get("disable_capture_response_body") then
    response_body_entity = nil
  else
    if next(split(config:get("response_masks"), ",")) == nil then
      response_body_entity = moesif_ctx.res_body
    else
      ok, mask_result = pcall(mask_body, cjson.decode(moesif_ctx.res_body), split(config:get("response_masks"), ","))
      if not ok then
        response_body_entity = moesif_ctx.res_body
      else
        response_body_entity = cjson.encode(mask_result)
      end
    end
  end

  if ngx.ctx.authenticated_credential ~= nil then
    if ngx.ctx.authenticated_credential.key ~= nil then
      session_token_entity = tostring(ngx.ctx.authenticated_credential.key)
    elseif ngx.ctx.authenticated_credential.id ~= nil then
      session_token_entity = tostring(ngx.ctx.authenticated_credential.id)
    else
      session_token_entity = nil
    end
  else
    session_token_entity = nil
  end

  -- Access by log derivative
  local headers = ngx.req.get_headers()
  -- Add Transaction Id to the request header
  if not config:get("disable_transaction_id") then
    if headers["X-Moesif-Transaction-Id"] ~= nil then
      req_trans_id = headers["X-Moesif-Transaction-Id"]
      if req_trans_id ~= nil and req_trans_id:gsub("%s+", "") ~= "" then
        transaction_id = req_trans_id
      else
        transaction_id = uuid()
      end
    else
      transaction_id = uuid()
    end
  -- Add Transaction Id to the request header
  ngx.req.set_header("X-Moesif-Transaction-Id", transaction_id)
  end


  -- Response header transaction Id
  local response_headers
  response_headers = ngx.resp.get_headers()

  -- Add Transaction Id to the response header
  if not config:get("disable_transaction_id") and transaction_id ~= nil then
    response_headers["X-Moesif-Transaction-Id"] = transaction_id
  end

  return {
    request = {
      uri = ngx.var.scheme .. "://" .. ngx.var.host .. ":" .. ngx.var.server_port .. ngx.var.request_uri,
      headers = ngx.req.get_headers(),
      body = request_body_entity,
      verb = req_get_method(),
      ip_address = get_client_ip(ngx.req.get_headers()),
      api_version = ngx.ctx.api_version,
      time = os.date("!%Y-%m-%dT%H:%M:%S.", req_start_time()) .. string.format("%d",(req_start_time()- string.format("%d", req_start_time()))*1000)
    },
    response = {
      time = os.date("!%Y-%m-%dT%H:%M:%S.", ngx_now()) .. string.format("%d",(ngx_now()- string.format("%d",ngx_now()))*1000),
      status = ngx.status,
      ip_address = Nil,
      headers = response_headers,
      body = response_body_entity,
    },
    session_token = session_token_entity,
    user_id = user_id_entity,
    company_id = company_id_entity
  }
end

return _M
