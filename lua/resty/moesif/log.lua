local cjson = require "cjson"
local HTTPS = "https"
local string_format = string.format
local configuration = nil
local config_hashes = {}
local queue_hashes = {}
local moesif_events = "moesif_events_"
local has_events = false
local ngx_md5 = ngx.md5
local compress = require "lib_deflate"
local helpers = require "helpers"
local connect = require "connection"
local sample_rate = 100
local _M = {}

function dump(o)
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

-- Get App Config function
function get_config(premature, config, application_id, debug)
  if premature then
    return
  end

  local sock, parsed_url = connect.get_connection(config, config:get("api_endpoint"), "/v1/config")

  -- Prepare the payload
  local payload = string_format(
    "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nX-Moesif-Application-Id: %s\r\n",
    "GET", parsed_url.path, parsed_url.host, application_id)

  -- Send the request
  local ok, err = sock:send(payload .. "\r\n")
  if not ok then
    if debug then
      ngx.log(ngx.ERR, "[moesif] failed to send data to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
    end
  else
    if debug then
      ngx.log(ngx.ERR, "[moesif] Successfully send request to fetch the application configuration " , ok)
    end
  end

  -- Read the response
  local config_response = helpers.read_socket_data(sock)

  ok, err = sock:setkeepalive(config:get("keepalive"))
  if not ok then
    if debug then
      ngx.log(ngx.ERR, "[moesif] failed to keepalive to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
    end
    return
   else
    if debug then
      ngx.log(ngx.ERR, "[moesif] success keep-alive", ok)
    end
  end

  -- Update the application configuration
  if config_response ~= nil then
    local response_body = cjson.decode(config_response:match("(%{.*})"))
    local config_tag = string.match(config_response, "ETag%s*:%s*(.-)\n")

    if config_tag ~= nil then
     config:set("ETag", config_tag)
    end

    if (config:get("sample_rate") ~= nil) and (response_body ~= nil) then
      if (response_body["user_sample_rate"] ~= nil) and (config:get("user_id") ~= nil) then
        config:set("user_sample_rate", response_body["user_sample_rate"][config:get("user_id")])
      else 
        config:set("sample_rate", response_body["sample_rate"])
      end
    end

    if config:get("last_updated_time") ~= nil then
     config:set("last_updated_time", os.time())
    end
  end
  config:set("is_config_fetched", true)
  return config_response
end

-- Generates http payload
local function generate_post_payload(parsed_url, message, application_id, debug)
  if debug then
    ngx.log(ngx.ERR, "[moesif] Generate Post Payload Message - " , dump(message))
    ngx.log(ngx.ERR, "[moesif] Generate Post Payload Message - " , type(message))
  end
  local body = cjson.encode(message)
  if debug then
    ngx.log(ngx.ERR, "[moesif] Generate Post Payload Body - " , dump(body))
    ngx.log(ngx.ERR, "[moesif] Generate Post Payload Body - " , type(body))
  end
  local ok, compressed_body = pcall(compress["CompressDeflate"], compress, body)
  if not ok then
    if debug then
      ngx.log(ngx.ERR, "[moesif] failed to compress body: ", compressed_body)
    end
  else
    if debug then
      ngx.log(ngx.ERR, " [moesif]  ", "successfully compressed body")
    end
    body = compressed_body
  end

  local payload = string_format(
    "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nX-Moesif-Application-Id: %s\r\nUser-Agent: %s\r\nContent-Encoding: %s\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s",
    "POST", parsed_url.path, parsed_url.host, application_id, "lua-resty-moesif/".."1.1.13", "deflate", #body, body)
  return payload
end

-- Send Payload
local function send_payload(sock, parsed_url, batch_events, config, debug)
  local application_id = config:get("application_id")
  local ok, err = sock:send(generate_post_payload(parsed_url, batch_events, application_id, debug) .. "\r\n")
  if not ok then
    if debug then
      ngx.log(ngx.ERR, "[moesif] failed to send data to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
    end
  else
    if debug then
      ngx.log(ngx.ERR, "[moesif] Events sent successfully " , ok)
    end
  end

  -- Read the response
  local send_event_response = helpers.read_socket_data(sock)

  if debug then
    ngx.log(ngx.ERR, "[moesif] Send Event Response - " , dump(send_event_response))
    ngx.log(ngx.ERR, "[moesif] Send Event Response - " , type(send_event_response))
  end

  -- Check if the application configuration is updated
  local response_etag = string.match(send_event_response, "ETag%s*:%s*(.-)\n")

  if (response_etag ~= nil) and (configuration["ETag"] ~= nil) and (configuration["ETag"] ~= response_etag) and (os.time() > config:get("last_updated_time") + 300) then
    local resp =  get_config(false, config, application_id, debug)
    if not resp then
      if debug then
        ngx.log(ngx.ERR, "[moesif] failed to get application config, setting the sample_rate to default ", err)
      end
    else
      if debug then
        ngx.log(ngx.ERR, "[moesif] successfully fetched the application configuration" , ok)
      end
    end
  end
end

-- Send Events Batch
local function send_events_batch(premature, config, debug)

  if premature then
    return
  end
  repeat
    for key, queue in pairs(queue_hashes) do
      if #queue > 0 then
        -- Getting the configuration for this particular key
        configuration = config_hashes[key]
        local sock, parsed_url = connect.get_connection(config, config:get("api_endpoint"), "/v1/events/batch")
        local batch_events = {}
        repeat
          local event = table.remove(queue)
          table.insert(batch_events, event)
          if (#batch_events == configuration:get("batch_size")) then
            send_payload(sock, parsed_url, batch_events, config, debug)
          else if(#queue ==0 and #batch_events > 0) then
              send_payload(sock, parsed_url, batch_events, config, debug)
            end
          end
        until #batch_events == configuration:get("batch_size") or next(queue) == nil

        if #queue > 0 then
          has_events = true
        else
          has_events = false
        end

        local ok, err = sock:setkeepalive(config:get("keepalive"))
        if not ok then
          if debug then
            ngx.log(ngx.ERR, "[moesif] failed to keepalive to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
          end
          return
         else
          -- if debug then
          --   ngx.log(ngx.DEBUG, "[moesif] success keep-alive", ok)
          -- end
        end
      else
        has_events = false
      end
    end
  until has_events == false

  if not has_events then
    if debug then
      ngx.log(ngx.ERR, "[moesif] No events to read from the queue")
    end
  end
end

-- Log to a Http end point.
local function log(premature, config, message, hash_key, debug)
  if premature then
    return
  end

  -- Sampling Events
  local random_percentage = math.random() * 100

  if config:get("sample_rate") == nil then
    config:set("sample_rate", 100)
  end

  if (config:get("user_sample_rate")) ~= nil then
    sampling_rate = config:get("user_sample_rate")
  else
    sampling_rate = config:get("sample_rate")
  end

  if sampling_rate >= random_percentage then
    if debug then
      ngx.log(ngx.ERR, "[moesif] Event added to the queue")
    end
    message["weight"] = (sampling_rate == 0 and 1 or math.floor(100 / sampling_rate))
    table.insert(queue_hashes[hash_key], message)
  else
    if debug then
      ngx.log(ngx.ERR, "[moesif] Skipped Event", " due to sampling percentage: " .. tostring(sampling_rate) .. " and random number: " .. tostring(random_percentage))
    end
  end
end


function _M.execute(config, message, debug)
  -- Get Application Id
  local application_id = config:get("application_id")

  -- Hash key of the config application Id
  local hash_key = ngx_md5(application_id)

  if message["user_id"] ~= nil then 
    config:set("user_id", message["user_id"])
  else 
    config:set("user_id", nil)
  end

  -- Execute
  if config_hashes[hash_key] == nil then
    if config:get("user_sample_rate") == nil then
      config:set("user_sample_rate", nil)
    end
    if config:get("is_config_fetched") == nil then
      local ok, err = ngx.timer.at(0, get_config, config, application_id, debug)
      if not ok then
        if debug then
          ngx.log(ngx.ERR, "[moesif] failed to get application config, setting the sample_rate to default ", err)
        end
      else
        if debug then
          ngx.log(ngx.ERR, "[moesif] successfully fetched the application configuration" , ok)
        end
      end
    end
    if config:get("sample_rate") == nil then
      config:set("sample_rate", 100)
    end
    if config:get("last_updated_time") == nil then
      config:set("last_updated_time", os.time())
    end
    if config:get("ETag") == nil then
      config:set("ETag", nil)
    end
    config_hashes[hash_key] = config
    local create_new_table = moesif_events..hash_key
    create_new_table = {}
    queue_hashes[hash_key] = create_new_table
  end

  local ok, err = ngx.timer.at(0, log, config, message, hash_key, debug)
  if not ok then
    if debug then
      ngx.log(ngx.ERR, "[moesif] failed to create timer: ", err)
    end
  end

  -- Schedule Events batch job
  local scheduleJob
  scheduleJob = function(premature)
    if not premature then
      send_events_batch(false, config, debug)
      local ok, err = ngx.timer.at(config:get("batch_max_time"), scheduleJob)
      if not ok then
          ngx.log(ngx.ERR, "[moesif] Error when scheduling the job:  ", err)
          return
      end
    end
  end

  if not config:get("is_batch_job_scheduled") then
    local scheduleJobOk, scheduleJobErr = ngx.timer.at(config:get("batch_max_time"), scheduleJob)
    if not scheduleJobOk then
      ngx.log(ngx.ERR, "[moesif] Error when scheduling the job:  ", scheduleJobErr)
    else
      config:set("is_batch_job_scheduled", true)
    end
  end
end

return _M
