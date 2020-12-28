local ngx_now = ngx.now
local req_get_method = ngx.req.get_method
local req_start_time = ngx.req.start_time
local req_get_headers = ngx.req.get_headers
local res_get_headers = ngx.resp.get_headers
local cjson = require "cjson"
local cjson_safe = require "cjson.safe"
local random = math.random
local client_ip = require "client_ip"
local zzlib = require "zzlib"
local base64 = require "base64"
local helpers = require "helpers"
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
function mask_body(body, masks)
  if masks == nil then return body end
  if body == nil then return body end
  for mask_key, mask_value in pairs(masks) do
    mask_value = mask_value:gsub("%s+", "")
    if body[mask_value] ~= nil then body[mask_value] = nil end
    for body_key, body_value in next, body do
        if type(body_value)=="table" then mask_body(body_value, masks) end
    end
  end
  return body
end

function base64_encode_body(body)
  return base64.encode(body), 'base64'
end

function is_valid_json(body)
    return type(body) == "string" 
        and string.sub(body, 1, 1) == "{" or string.sub(body, 1, 1) == "["
end

function process_data(body, mask_fields)
  local body_entity = nil
  local body_transfer_encoding = nil
  local is_deserialised, deserialised_body = pcall(cjson_safe.decode, body)
  if not is_deserialised  then
      body_entity, body_transfer_encoding = base64_encode_body(body)
  else
      if next(mask_fields) == nil then
          body_entity, body_transfer_encoding = deserialised_body, 'json' 
      else
          local ok, mask_result = pcall(mask_body, deserialised_body, mask_fields)
          if not ok then
            body_entity, body_transfer_encoding = deserialised_body, 'json' 
          else
            body_entity, body_transfer_encoding = mask_result, 'json' 
          end
      end
  end
  return body_entity, body_transfer_encoding
end

function decompress_body(body, masks)
  local body_entity = nil
  local body_transfer_encoding = nil

  local ok, decompressed_body = pcall(zzlib.gunzip, body)
  if not ok then
    if debug then
      ngx.log(ngx.DEBUG, "[moesif] failed to decompress body: ", decompressed_body)
    end
    body_entity, body_transfer_encoding = base64_encode_body(body)
  else
    if debug then
      ngx.log(ngx.DEBUG, " [moesif]  ", "successfully decompressed body: ")
    end
    if is_valid_json(decompressed_body) then 
        body_entity, body_transfer_encoding = process_data(decompressed_body, masks)
    else 
        body_entity, body_transfer_encoding = base64_encode_body(decompressed_body)
    end
  end
  return body_entity, body_transfer_encoding
end

function mask_headers(headers, mask_fields)
  local mask_headers = nil

  for k,v in pairs(mask_fields) do
    mask_fields[k] = v:lower()
  end

  local ok, mask_result = pcall(mask_body, headers, mask_fields)
  if not ok then
    mask_headers = headers
  else
    mask_headers = mask_result
  end
  return mask_headers
end

function mask_body_fields(body_masks_config, deprecated_body_masks_config)
  if next(body_masks_config) == nil then
    return deprecated_body_masks_config
  else
    return body_masks_config
  end
end

function parse_body(headers, body, mask_fields, config)
  local body_entity = nil
  local body_transfer_encoding = nil

  if headers["content-type"] ~= nil and is_valid_json(body) then 
    body_entity, body_transfer_encoding = process_data(body, mask_fields)
  elseif headers["content-encoding"] ~= nil and type(body) == "string" and string.find(headers["content-encoding"], "gzip") then
    if not config:get("disable_gzip_payload_decompression") then 
      body_entity, body_transfer_encoding = decompress_body(body, mask_fields)
    else
      body_entity, body_transfer_encoding = base64_encode_body(body)
    end
  else
    body_entity, body_transfer_encoding = base64_encode_body(body)
  end
  return body_entity, body_transfer_encoding
end

-- Prepare message
function _M.prepare_message(config)
  local session_token_entity
  local request_body_entity
  local response_body_entity
  local user_id_entity
  local company_id_entity
  local api_version
  local transaction_id = nil
  local req_body_transfer_encoding = nil
  local rsp_body_transfer_encoding = nil
  local request_headers = ngx.req.get_headers()
  local response_headers = ngx.resp.get_headers()

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
    -- Split authorization header name by comma
    local auth_header_names = split(string.lower(config:get("authorization_header_name")), ",")    
    local token = nil
    -- Fetch the token and field from the config
    for _, name in pairs(auth_header_names) do
      local auth_name = name:gsub("%s+", "")
      if request_headers[auth_name] ~= nil then 
        if type(request_headers[auth_name]) == "table" and (request_headers[auth_name][0] ~= nil or request_headers[auth_name][1] ~= nil) then 
            token = request_headers[auth_name][0] or request_headers[auth_name][1]
        else
            token = request_headers[auth_name]
        end
        break
      end
    end
    local field = string.lower(config:get("authorization_user_id_field"))

    if token ~= nil then 

      -- Check if token is of type Bearer
      if string.match(token, "Bearer") then
          -- Fetch the bearer token
          token = token:gsub("Bearer", "")

          -- Split the bearer token by dot(.)
          local split_token = helpers.fetch_token_payload(token)

          -- Check if payload is not nil
          if split_token[2] ~= nil then 
              -- Parse and set user Id
              user_id_entity = helpers.parse_authorization_header(split_token[2], field)
          else
              user_id_entity = nil  
          end 
      -- Check if token is of type Basic
      elseif string.match(token, "Basic") then
          -- Fetch the basic token
          token = token:gsub("Basic", "")
          -- Decode the token
          local decoded_token = base64.decode(token)
          -- Fetch the username and password
          local username, _ = decoded_token:match("(.*):(.*)")

          -- Set the user_id
          if username ~= nil then
              user_id_entity = username 
          else
              user_id_entity = nil 
          end 
      -- Check if token is of user-defined custom type
      else
          -- Split the bearer token by dot(.)
          local split_token = helpers.fetch_token_payload(token)

            -- Check if payload is not nil
          if split_token[2] ~= nil then 
              -- Parse and set user Id
              user_id_entity = helpers.parse_authorization_header(split_token[2], field)
          else
              -- Parse and set the user_id
              user_id_entity = helpers.parse_authorization_header(token, field)
          end 
      end
    else
      user_id_entity = nil
    end
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
  if ngx.var.moesif_req_body == nil or config:get("disable_capture_request_body") or (request_content_length ~= nil and tonumber(request_content_length) > config:get("max_body_size_limit")) then
    request_body_entity = nil
  else
    local request_body_masks = mask_body_fields(split(config:get("request_body_masks"), ","), split(config:get("request_masks"), ","))
    request_body_entity, req_body_transfer_encoding = parse_body(request_headers, ngx.var.moesif_req_body, request_body_masks, config)
  end

  -- Response body
  local response_content_length = ngx.resp.get_headers()["content-length"]
  if ngx.var.moesif_res_body == nil or config:get("disable_capture_response_body") or (response_content_length ~= nil and tonumber(response_content_length) > config:get("max_body_size_limit")) then
    response_body_entity = nil
  else
    local response_body_masks = mask_body_fields(split(config:get("response_body_masks"), ","), split(config:get("response_masks"), ","))
    response_body_entity, rsp_body_transfer_encoding = parse_body(response_headers, ngx.var.moesif_res_body, response_body_masks, config)
  end

  -- Headers
  local request_header_masks = split(config:get("request_header_masks"), ",")
  local response_header_masks = split(config:get("response_header_masks"), ",")
  
  -- Mask request headers
  if next(request_header_masks) ~= nil then
    request_headers = mask_headers(ngx.req.get_headers(), request_header_masks)
  end

  -- Mask response headers
  if next(response_header_masks) ~= nil then
    response_headers = mask_headers(ngx.resp.get_headers(), response_header_masks)
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

  return {
    request = {
      uri = ngx.var.scheme .. "://" .. ngx.var.host .. ":" .. ngx.var.server_port .. ngx.var.request_uri,
      headers = request_headers,
      body = request_body_entity,
      verb = req_get_method(),
      ip_address = client_ip.get_client_ip(request_headers),
      api_version = api_version,
      time = os.date("!%Y-%m-%dT%H:%M:%S.", req_start_time()) .. string.format("%d",(req_start_time()- string.format("%d", req_start_time()))*1000),
      transfer_encoding = req_body_transfer_encoding,
    },
    response = {
      time = os.date("!%Y-%m-%dT%H:%M:%S.", ngx_now()) .. string.format("%d",(ngx_now()- string.format("%d",ngx_now()))*1000),
      status = ngx.status,
      ip_address = Nil,
      headers = response_headers,
      body = response_body_entity,
      transfer_encoding = rsp_body_transfer_encoding,
    },
    session_token = session_token_entity,
    user_id = user_id_entity,
    company_id = company_id_entity,
    direction = "Incoming"
  }
end

return _M
