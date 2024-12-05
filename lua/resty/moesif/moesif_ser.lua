local ngx_now = ngx.now
local req_get_method = ngx.req.get_method
local req_start_time = ngx.req.start_time
local cjson = require "cjson"
local cjson_safe = require "cjson.safe"
local random = math.random
local moesif_client = require "moesifapi.lua.moesif_client"
local zzlib = require "moesifapi.lua.zzlib"
local base64 = require "moesifapi.lua.base64"
local helpers = require "helpers"
local _M = {}
local ngx_log = ngx.log
local ser_helper = require "moesifapi.lua.serializaiton_helper"

local function dump(o)
  if type(o) == 'table' then
    local s = '{ '
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. '['..k..'] = ' .. dump(v) .. ','
    end
    return s .. '} '
  else
    return tostring(o)
  end
end

-- Split the string
local function split(str, character)
  local result = {}

  local index = 1
  for s in string.gmatch(str, "[^"..character.."]+") do
    result[index] = s
    index = index + 1
  end

  return result
end

-- Prepare message
function _M.prepare_message(config)
  local moesif_ctx = ngx.ctx.moesif or {}
  local session_token_entity
  local request_body_entity
  local response_body_entity
  local blocked_by_entity
  local user_id_entity
  local company_id_entity
  local api_version
  local transaction_id = nil
  local req_body_transfer_encoding = nil
  local rsp_body_transfer_encoding = nil
  local request_uri = ngx.var.request_uri
  local request_headers = ngx.req.get_headers()
  local response_headers = ngx.resp.get_headers()

  local debug = config:get("debug")

  if debug then
    ngx_log(ngx.DEBUG, "[moesif] request headers from ngx.req while preparing message ", dump(request_headers))
    ngx_log(ngx.DEBUG, "[moesif] response headers from ngx.resp while preparing message ", dump(response_headers))
  end


  -- User Id
  if ngx.var.credentials ~= nil and ngx.var.credentials.app_id ~= nil then
    user_id_entity = ngx.var.credentials.app_id
  elseif ngx.var.arg_app_id ~= nil then
    user_id_entity = ngx.var.arg_app_id
  elseif ngx.var.credentials ~= nil and ngx.var.credentials.user_key ~= nil then
    user_id_entity = ngx.var.credentials.user_key
  elseif ngx.var.user_key ~= nil then
    user_id_entity = ngx.var.user_key
  elseif ngx.var.userid ~= nil then
    user_id_entity = ngx.var.userid
  elseif ngx.var.moesif_user_id ~= nil and ngx.var.moesif_user_id ~= "nil" and ngx.var.moesif_user_id ~= "null" and ngx.var.moesif_user_id ~= '' then
    user_id_entity = ngx.var.moesif_user_id
  elseif ngx.var.remote_user ~= nil then
    user_id_entity = ngx.var.remote_user
  elseif ngx.var.application_id ~= nil then
    user_id_entity = ngx.var.application_id
  elseif string.lower(config:get("authorization_header_name")) ~= nil and string.lower(config:get("authorization_user_id_field")) ~= nil then
    user_id_entity, company_id_entity = moesif_client.get_identity_from_auth_header(config, request_headers)
  end

  -- Company Id
  if ngx.var.moesif_company_id ~= nil and ngx.var.moesif_company_id ~= "nil" and ngx.var.moesif_company_id ~= "null" and ngx.var.moesif_company_id ~= '' then
    company_id_entity = ngx.var.moesif_company_id
  elseif ngx.var.account_id ~= nil then
    company_id_entity = ngx.var.account_id
  end

  if ngx.var.moesif_api_version ~= nil then
    api_version = ngx.var.moesif_api_version
  end

  -- Request body
  local request_content_length = ngx.req.get_headers()["content-length"]
  if moesif_ctx.req_body == nil or config:get("disable_capture_request_body") or (request_content_length ~= nil and tonumber(request_content_length) > config:get("max_body_size_limit")) then
    request_body_entity = nil
  else
    local request_body_masks = ser_helper.mask_body_fields(split(config:get("request_body_masks"), ","), split(config:get("request_masks"), ","))
    request_body_entity, req_body_transfer_encoding = moesif_client.parse_body(request_headers, moesif_ctx.req_body, request_body_masks, config)
  end

  -- Response body
  local response_content_length = ngx.resp.get_headers()["content-length"]
  if moesif_ctx.res_body == nil or config:get("disable_capture_response_body") or (response_content_length ~= nil and tonumber(response_content_length) > config:get("max_body_size_limit")) then
    response_body_entity = nil
  else
    local response_body_masks = ser_helper.mask_body_fields(split(config:get("response_body_masks"), ","), split(config:get("response_masks"), ","))
    response_body_entity, rsp_body_transfer_encoding = moesif_client.parse_body(response_headers, moesif_ctx.res_body, response_body_masks, config)
  end

  -- Headers
  local request_header_masks = split(config:get("request_header_masks"), ",")
  local response_header_masks = split(config:get("response_header_masks"), ",")
  
  -- Mask request headers
  if next(request_header_masks) ~= nil then
    request_headers = ser_helper.mask_headers(ngx.req.get_headers(), request_header_masks)
  end

  -- Mask response headers
  if next(response_header_masks) ~= nil then
    response_headers = ser_helper.mask_headers(ngx.resp.get_headers(), response_header_masks)
  end

  -- Get session token
  if ngx.ctx.authenticated_credential ~= nil then
    if ngx.ctx.authenticated_credential.key ~= nil then
      session_token_entity = tostring(ngx.ctx.authenticated_credential.key)
    elseif ngx.ctx.authenticated_credential.id ~= nil then
      session_token_entity = tostring(ngx.ctx.authenticated_credential.id)
    else
      session_token_entity = nil
    end
  elseif ngx.ctx.moesif_session_token ~= nil then
    session_token_entity = tostring(ngx.ctx.moesif_session_token)
  else
    session_token_entity = nil
  end

  -- Add Transaction Id to the request header
  if not config:get("disable_transaction_id") then
    if request_headers["X-Moesif-Transaction-Id"] ~= nil then
      local req_trans_id = request_headers["X-Moesif-Transaction-Id"]
      if req_trans_id ~= nil and req_trans_id:gsub("%s+", "") ~= "" then
        transaction_id = req_trans_id
      else
        transaction_id = ngx.var.request_id
      end
    else
      transaction_id = ngx.var.request_id
    end
  -- Add Transaction Id to the request header
  request_headers["X-Moesif-Transaction-Id"] = transaction_id
  end

  -- Add Transaction Id to the response header
  if not config:get("disable_transaction_id") and transaction_id ~= nil then
    response_headers["X-Moesif-Transaction-Id"] = transaction_id
  end

  if debug then
    ngx_log(ngx.DEBUG, "[moesif] request headers before sending to moesif ", dump(request_headers))
    ngx_log(ngx.DEBUG, "[moesif] response headers before sending to moesif ", dump(response_headers))
  end

  -- Add blocked_by field to the event to determine the rule by which the event was blocked
  ngx_log(ngx.DEBUG, "[moesif] ngx ctx ", dump(ngx.ctx))
  if ngx.ctx.moesif ~= nil and ngx.ctx.moesif.blocked_by ~= nil then 
    blocked_by_entity = ngx.ctx.moesif.blocked_by
  end

  if request_uri ~= nil then
    return moesif_client.prepare_event(config, request_headers, request_body_entity, req_body_transfer_encoding, api_version,
                                          response_headers, response_body_entity, rsp_body_transfer_encoding,
                                          session_token_entity, user_id_entity, company_id_entity, blocked_by_entity)
  else
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] SKIPPED Sending event as request uri is not valid, the request uri found is: - ", request_uri);
    end
    return {}
  end
end

return _M
