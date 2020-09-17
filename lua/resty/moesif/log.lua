local cjson = require "cjson"
local HTTPS = "https"
local string_format = string.format
local configuration = nil
local config_hashes = {}
local queue_hashes = {}
local queue_scheduled_time
local moesif_events = "moesif_events_"
local has_events = false
local compress = require "lib_deflate"
local helpers = require "helpers"
local connect = require "connection"
local sample_rate = 100
local ngx_log = ngx.log
local ngx_log_ERR = ngx.ERR
local ngx_timer_at = ngx.timer.at
local gc = 0
local health_check = 0
local rec_event = 0
local sent_event = 0
local _M = {}

-- Generates http payload
local function generate_post_payload(config, parsed_url, message, application_id, user_agent_string, debug)

  local payload = nil
  local body = cjson.encode(message)

  local ok, compressed_body = pcall(compress["CompressDeflate"], compress, body)
  if not ok then
    if debug then
      ngx_log(ngx_log_ERR, "[moesif] failed to compress body: ", compressed_body)
    end

    payload = string_format(
      "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nX-Moesif-Application-Id: %s\r\nUser-Agent: %s\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s",
      "POST", parsed_url.path, parsed_url.host, application_id, user_agent_string, #body, body)
    return payload
  else
    if debug then
      ngx_log(ngx.DEBUG, " [moesif]  ", "successfully compressed body")
    end
    payload = string_format(
      "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nX-Moesif-Application-Id: %s\r\nUser-Agent: %s\r\nContent-Encoding: %s\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s",
      "POST", parsed_url.path, parsed_url.host, application_id, user_agent_string, "deflate", #compressed_body, compressed_body)
    return payload
  end  
end


-- Send Payload
local function send_payload(sock, parsed_url, batch_events, config, user_agent_string, debug)
  local application_id = config:get("application_id")
  local ok, err = sock:send(generate_post_payload(config, parsed_url, batch_events, application_id, user_agent_string, debug) .. "\r\n")
  if not ok then
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] failed to send data to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
    end
  else
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] Events sent successfully " , ok)
    end
  end
end

-- Get App Config function
-- @param `conf`     Configuration table, holds http endpoint details
function get_config_internal(config, debug)
  
  local config_socket = ngx.socket.tcp()
  config_socket:settimeout(config:get("connect_timeout"))
  local sock, parsed_url = connect.get_connection(config, config:get("api_endpoint"), "/v1/config", config_socket)

  if type(config_socket) == "table" and next(config_socket) ~= nil then
    -- Prepare the payload
    local payload = string_format(
      "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nX-Moesif-Application-Id: %s\r\n",
      "GET", parsed_url.path, parsed_url.host, config:get("application_id"))

      -- Send the request
      local ok, err = config_socket:send(payload .. "\r\n")
      if not ok then
        if debug then
          ngx_log(ngx_log_ERR, "[moesif] failed to send data to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
        end
      else
        if debug then
          ngx_log(ngx.DEBUG, "[moesif] Successfully send request to fetch the application configuration " , ok)
        end
      end

      -- Read the response
      local config_response = helpers.read_socket_data(config_socket, config)
      if config_response ~= nil then
        
        local ok_config, err_config = config_socket:setkeepalive(config:get("keepalive"))
        if not ok_config then
          if debug then
            ngx_log(ngx_log_ERR, "[moesif] failed to keepalive to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err_config)
          end
          local close_ok, close_err = config_socket:close()
          if not close_ok then
              if debug then
                  ngx_log(ngx_log_ERR,"[moesif] Failed to manually close socket connection ", close_err)
              end
          else
              if debug then
                  ngx_log(ngx.DEBUG,"[moesif] success closing socket connection manually ")
              end
          end
        else
          if debug then
            ngx_log(ngx.DEBUG, "[moesif] success keep-alive", ok_config)
          end
        end

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

      else
        ngx_log(ngx.DEBUG, "[moesif] application config is nil ")
      end
      
      config:set("is_config_fetched", true)
      return config_response
  end
end

-- Get App Config function
function get_config(premature, config, debug)
  if premature then
    return
  end

  local ok, err = pcall(get_config_internal, config, debug)
  if not ok then
    if debug then
      ngx_log(ngx_log_ERR, "[moesif] failed to get config internal ", err)
    end
  else 
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] get config internal success " , ok)
    end
  end

  local sok, serr = ngx_timer_at(60, get_config, config, debug)
  if not sok then
    if debug then
      ngx_log(ngx_log_ERR, "[moesif] Error when scheduling the get config : ", serr)
    end
  else
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] success when scheduling the get config ")
    end
  end

end

-- Send Events Batch
local function send_events_batch(premature, config, user_agent_string, debug)
  local prv_events = sent_event
  local start_time = socket.gettime()*1000
  if premature then
    return
  end

  local send_events_socket = ngx.socket.tcp()
  local global_socket_timeout = 1000
  send_events_socket:settimeout(global_socket_timeout)

  local batch_events = {}

  -- Getting the configuration
  -- configuration = config_hashes
  local local_queue = queue_hashes
  queue_hashes = {}
  repeat
      if #local_queue > 0 and ((socket.gettime()*1000 - start_time) <= config_hashes:get("max_callback_time_spent")) then
        ngx_log(ngx.DEBUG, "[moesif] Sending events to Moesif")
        
        local start_con_time = socket.gettime()*1000
        local sock, parsed_url = connect.get_connection(config, config:get("api_endpoint"), "/v1/events/batch", send_events_socket)
        local end_con_time = socket.gettime()*1000
        if debug then
          ngx_log(ngx.DEBUG, "[moesif] get connection took time - ".. tostring(end_con_time - start_con_time).." for pid - ".. ngx.worker.pid())
        end

        if type(send_events_socket) == "table" and next(send_events_socket) ~= nil then
          
          local counter = 0
          repeat
            local event = table.remove(local_queue)
            counter = counter + 1
            table.insert(batch_events, event)
            if (#batch_events == config:get("batch_size")) then
              local start_pay_time = socket.gettime()*1000
              if pcall(send_payload, send_events_socket, parsed_url, batch_events, config, user_agent_string, debug) then 
                sent_event = sent_event + #batch_events
               end
              local end_pay_time = socket.gettime()*1000
               if debug then
                ngx_log(ngx.DEBUG, "[moesif] send payload with event count - " .. tostring(#batch_events) .. " took time - ".. tostring(end_pay_time - start_pay_time).." for pid - ".. ngx.worker.pid())
               end
               batch_events = {}
            else if(#local_queue ==0 and #batch_events > 0) then
                local start_pay1_time = socket.gettime()*1000
                if pcall(send_payload, send_events_socket, parsed_url, batch_events, config, user_agent_string, debug) then 
                  sent_event = sent_event + #batch_events
                end
                local end_pay1_time = socket.gettime()*1000
                if debug then
                  ngx_log(ngx.DEBUG, "[moesif] send payload with event count - " .. tostring(#batch_events) .. " took time - ".. tostring(end_pay1_time - start_pay1_time).." for pid - ".. ngx.worker.pid())
                end
                batch_events = {}
              end
            end
          until counter == config:get("batch_size") or next(local_queue) == nil
  
          if #local_queue > 0 then
            has_events = true
          else
            has_events = false
          end
  
          local ok, err = send_events_socket:setkeepalive()
          if not ok then
            if debug then
              ngx_log(ngx_log_ERR, "[moesif] failed to keepalive to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .. ": ", err)
            end
            local close_ok, close_err = send_events_socket:close()
            if not close_ok then
              if debug then
                ngx_log(ngx_log_ERR,"[moesif] Failed to manually close socket connection ", close_err)
              end
            else
              if debug then
                ngx_log(ngx.DEBUG,"[moesif] success closing socket connection manually ")
              end
            end
           else
            if debug then
              ngx_log(ngx.DEBUG, "[moesif] success keep-alive", ok)
            end
          end
        else 
          if debug then 
            ngx_log(ngx.DEBUG, "[moesif] Failure to create socket connection for sending event to Moesif ")
          end
        end
        if debug then 
          ngx_log(ngx.DEBUG, "[moesif] Received Event - "..tostring(rec_event).." and Sent Event - "..tostring(sent_event).." for pid - ".. ngx.worker.pid())
        end
      else
        has_events = false
        if #local_queue <= 0 then 
          ngx_log(ngx.DEBUG, "[moesif] Queue is empty, no events to send ")
        else
          ngx_log(ngx.DEBUG, "[moesif] Max callback time exceeds, skip sending events now ")
        end
      end
  until has_events == false

  if not has_events then
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] No events to read from the queue")
    end
  end

  -- Manually garbage collect every alternate cycle
  gc = gc + 1 
  if gc == 8 then 
    collectgarbage()
    gc = 0
  end
  
  -- Periodic health check
  health_check = health_check + 1
  if health_check == 150 then
    if rec_event ~= 0 then
      local event_perc = sent_event / rec_event
      ngx_log(ngx.DEBUG, "[moesif] heartbeat - "..tostring(event_perc).." in pid - ".. ngx.worker.pid())
    end
    health_check = 0
  end
  
  local endtime = socket.gettime()*1000
  
  -- Event queue size
  local length = 0
  if queue_hashes ~= nil then 
    length = #queue_hashes
  end
  ngx_log(ngx.DEBUG, "[moesif] send events batch took time - ".. tostring(endtime - start_time) .. " and sent event delta - " .. tostring(sent_event - prv_events).." for pid - ".. ngx.worker.pid().. " with queue size - ".. tostring(length))

end

-- Log to a Http end point.
local function log(config, message, debug)

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
      ngx_log(ngx.DEBUG, "[moesif] Event added to the queue")
    end
    message["weight"] = (sampling_rate == 0 and 1 or math.floor(100 / sampling_rate))
    
    rec_event = rec_event + 1
    table.insert(queue_hashes, message)
  else
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] Skipped Event", " due to sampling percentage: " .. tostring(sampling_rate) .. " and random number: " .. tostring(random_percentage))
    end
  end
end

-- Run the job
function runJob(premature, config, user_agent_string, debug)
  if not premature then
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] Calling the send_events_batch function from the scheduled job - ")
    end
    send_events_batch(false, config, user_agent_string, debug)
    
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] Calling the scheduleJobIfNeeded function to check if needed to schedule the job - ")
    end
    scheduleJobIfNeeded(config, config:get("batch_max_time"), user_agent_string, debug)
  end
end

-- Schedule Events batch job
function scheduleJobIfNeeded(config, batch_max_time, user_agent_string, debug)
  if queue_scheduled_time == nil then 
    queue_scheduled_time = os.time{year=1970, month=1, day=1, hour=0}
  end
  if (os.time() >= (queue_scheduled_time + batch_max_time)) then
    
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] Batch Job is not scheduled, scheduling the job  - ")
    end

    -- Updating the queue scheduled time
    queue_scheduled_time = os.time()

    local scheduleJobOk, scheduleJobErr = ngx.timer.at(config:get("batch_max_time"), runJob, config, user_agent_string, debug)
    if not scheduleJobOk then
      ngx_log(ngx_log_ERR, "[moesif] Error when scheduling the job:  ", scheduleJobErr)
    else
      if debug then
        ngx_log(ngx.DEBUG, "[moesif] Batch Job is scheduled successfully ")
      end
    end
  else
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] Batch Job is already scheduled  - ")
    end
  end
end

function _M.execute(config, message, user_agent_string, debug)
  -- Get Application Id
  local application_id = config:get("application_id")

  if message["user_id"] ~= nil then 
    config:set("user_id", message["user_id"])
  else 
    config:set("user_id", nil)
  end

  -- Execute
  if next(config_hashes) == nil then
    if config:get("user_sample_rate") == nil then
      config:set("user_sample_rate", nil)
    end
    if config:get("is_config_fetched") == nil then
      if debug then
        ngx_log(ngx.DEBUG, "[moesif] Moesif Config is not fetched, calling the function to fetch configuration - ")
      end

      local ok, err = ngx.timer.at(0, get_config, config, debug)
      if not ok then
        if debug then
          ngx_log(ngx_log_ERR, "[moesif] failed to get application config, setting the sample_rate to default ", err)
        end
      else
        if debug then
          ngx_log(ngx.DEBUG, "[moesif] successfully fetched the application configuration" , ok)
        end
      end
    end
    if config:get("sample_rate") == nil then
      config:set("sample_rate", 100)
    end
    if config:get("ETag") == nil then
      config:set("ETag", nil)
    end
    config_hashes = config
  end

  log(config, message, debug)

  if debug then
    ngx_log(ngx.DEBUG, "[moesif] last_batch_scheduled_time before scheduleding the job - ", tostring(config:get("queue_scheduled_time")))
  end

  scheduleJobIfNeeded(config, 5 * config:get("batch_max_time"), user_agent_string, debug)

end

return _M
