local cjson = require "cjson"
local HTTPS = "https"
local string_format = string.format
local configuration = nil
local config_hashes = {}
local queue_hashes = {}
local moesif_events = "moesif_events_"
local has_events = false
local ngx_md5 = ngx.md5
local compress = require "usr.local.openresty.site.lualib.plugins.moesif.lib_deflate"
local helper = require "usr.local.openresty.site.lualib.plugins.moesif.helpers"
local connect = require "usr.local.openresty.site.lualib.plugins.moesif.connection"
local _M = {}

-- Get App Config function
function get_config(premature, config)
  if premature then
    return
  end

  local sock, parsed_url = connect.get_connection(config, "/v1/config")

  -- Prepare the payload
  local payload = string_format(
    "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nX-Moesif-Application-Id: %s\r\n",
    "GET", parsed_url.path, parsed_url.host, application_id)

  -- Send the request
  ok, err = sock:send(payload .. "\r\n")
  if not ok then
    ngx.log(ngx.CRIT, "[moesif] failed to send data to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
  else
    ngx.log(ngx.CRIT, "[moesif] Successfully send request to fetch the application configuration " , ok)
  end

  -- Read the response
  config_response = helper.read_socket_data(sock)

  ok, err = sock:setkeepalive(config:get("keepalive"))
  if not ok then
    ngx.log(ngx.CRIT, "[moesif] failed to keepalive to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
    return
   else
     ngx.log(ngx.CRIT, "[moesif] success keep-alive", ok)
  end

  -- Update the application configuration
  if config_response ~= nil then
    local response_body = cjson.decode(config_response:match("(%{.-%})"))
    local config_tag = string.match(config_response, "ETag: (%a+)")

    if config_tag ~= nil then
     config:set("ETag", config_tag)
    end

    if (config:get("sample_rate") ~= nil) and (response_body ~= nil) then
     config:set("sample_rate", response_body["sample_rate"])
    end

    if config:get("last_updated_time") ~= nil then
     config:set("last_updated_time", os.time())
    end
  end
  return config_response
end

-- Generates http payload
local function generate_post_payload(parsed_url, message, application_id)

  local body = cjson.encode(message)

  local ok, compressed_body = pcall(compress["CompressDeflate"], compress, body)
  if not ok then
    ngx.log(ngx.CRIT, "[moesif] failed to compress body: ", compressed_body)
  else
    ngx.log(ngx.CRIT, " [moesif]  ", "successfully compressed body")
    body = compressed_body
  end


  local payload = string_format(
    "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nX-Moesif-Application-Id: %s\r\nUser-Agent: %s\r\nContent-Encoding: %s\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s",
    "POST", parsed_url.path, parsed_url.host, application_id, "openresty-plugin-moesif/".."0.1.0", "deflate", #body, body)
  return payload
end

-- Send Payload
local function send_payload(sock, parsed_url, batch_events, config)

  ok, err = sock:send(generate_post_payload(parsed_url, batch_events, application_id) .. "\r\n")
  if not ok then
    ngx.log(ngx.CRIT, "[moesif] failed to send data to " .. host .. ":" .. tostring(port) .. ": ", err)
  else
    ngx.log(ngx.CRIT, "[moesif] Events sent successfully " , ok)
  end

  -- Read the response
  send_event_response = helper.read_socket_data(sock)

  -- Check if the application configuration is updated
  local response_etag = string.match(send_event_response, "ETag: (%a+)")

  if (response_etag ~= nil) and (config:get("ETag") ~= response_etag) and (os.time() > config:get("last_updated_time") + 300) then
    local resp =  get_config(false, config)
    if not resp then
      ngx.log(ngx.CRIT, "[moesif] failed to get application config, setting the sample_rate to default ", err)
    else
      ngx.log(ngx.CRIT, "[moesif] successfully fetched the application configuration" , ok)
    end
  end
end

-- Send Events Batch
local function send_events_batch(config)

  repeat
    for key, queue in pairs(queue_hashes) do
      if #queue > 0 then
        -- Getting the configuration for this particular key
        configuration = config_hashes[key]
        local sock, parsed_url = connect.get_connection(config, "/v1/events/batch")
        local batch_events = {}
        repeat
          event = table.remove(queue)
          table.insert(batch_events, event)
          if (#batch_events == configuration.batch_size) then
            send_payload(sock, parsed_url, batch_events, config)
          else if(#queue ==0 and #batch_events > 0) then
              send_payload(sock, parsed_url, batch_events, config)
            end
          end
        until #batch_events == configuration.batch_size or next(queue) == nil

        if #queue > 0 then
          has_events = true
        else
          has_events = false
        end

        ok, err = sock:setkeepalive(config:get("keepalive"))
        if not ok then
          ngx.log(ngx.CRIT, "[moesif] failed to keepalive to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
          return
         else
           ngx.log(ngx.CRIT, "[moesif] success keep-alive", ok)
        end
      else
        has_events = false
      end
    end
  until has_events == false

  if not has_events then
    ngx.log(ngx.CRIT, "[moesif] No events to read from the queue")
  end
end


-- Log to a Http end point.
local function log(premature, config, message, hash_key)
  if premature then
    return
  end

  -- Sampling Events
  local random_percentage = math.random() * 100

  if config:get("sample_rate") == nil then
    config:set("sample_rate", 100)
  end

  if config:get("sample_rate") >= random_percentage then
    ngx.log(ngx.CRIT, "[moesif] Event added to the queue")
    table.insert(queue_hashes[hash_key], message)
    send_events_batch(config)
  else
    ngx.log(ngx.CRIT, "[moesif] Skipped Event", " due to sampling percentage: " .. tostring(config:get("sample_rate")) .. " and random number: " .. tostring(random_percentage))
  end
end


function _M.execute(config, message)
  -- Get Application Id
  application_id = config:get("application_id")

  -- Hash key of the config application Id
  hash_key = ngx_md5(application_id)

  -- Execute
  if config_hashes[hash_key] == nil then
    local ok, err = ngx.timer.at(0, get_config, config)
    if not ok then
      ngx.log(ngx.CRIT, "[moesif] failed to get application config, setting the sample_rate to default ", err)
    else
      ngx.log(ngx.CRIT, "[moesif] successfully fetched the application configuration" , ok)
    end
    config:set("sample_rate", 100)
    config:set("last_updated_time", os.time())
    config:set("ETag", nil)
    config_hashes[hash_key] = config
    local create_new_table = moesif_events..hash_key
    create_new_table = {}
    queue_hashes[hash_key] = create_new_table
  end

  local ok, err = ngx.timer.at(0, log, config, message, hash_key)
  if not ok then
    ngx.log(ngx.CRIT, "[moesif] failed to create timer: ", err)
  end
end

return _M
