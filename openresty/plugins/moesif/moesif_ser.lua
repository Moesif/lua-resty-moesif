local ngx_now = ngx.now
local req_get_method = ngx.req.get_method
local req_start_time = ngx.req.start_time
local req_get_headers = ngx.req.get_headers
local res_get_headers = ngx.resp.get_headers
local cjson = require "cjson"
local random = math.random
local transaction_id = nil
local client_ip = require "usr.local.openresty.site.lualib.plugins.moesif.client_ip"
local zzlib = require "usr.local.openresty.site.lualib.plugins.moesif.zzlib"
local _M = {}


-- Split the string
local function split(str, character)
  local result = {}

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
      local req_trans_id = headers["X-Moesif-Transaction-Id"]
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

  if (response_headers["content-encoding"] ~= nil) and (response_headers["content-encoding"] == 'gzip') then 
    local ok, decompressed_body = pcall(zzlib.gunzip, response_body_entity)
      if not ok then
        if config:get("debug") then
          ngx.log(ngx.CRIT, "[moesif] failed to decompress body: ", decompressed_body)
        end
      else
        if config:get("debug") then
          ngx.log(ngx.CRIT, " [moesif]  ", "successfully decompressed body: ")
        end
        response_body_entity = decompressed_body
      end
  end

  return {
    request = {
      uri = ngx.var.scheme .. "://" .. ngx.var.host .. ":" .. ngx.var.server_port .. ngx.var.request_uri,
      headers = ngx.req.get_headers(),
      body = request_body_entity,
      verb = req_get_method(),
      ip_address = client_ip.get_client_ip(ngx.req.get_headers()),
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
    company_id = company_id_entity,
    direction = "Incoming"
  }
end

return _M
