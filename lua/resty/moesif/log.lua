local cjson = require "cjson"
local socket = require "socket"
local HTTPS = "https"
local string_format = string.format
local configuration = nil
local config_hashes = {}
local queue_hashes = {}
local queue_scheduled_time
local moesif_events = "moesif_events_"
local has_events = false
-- local compress = require "lib_deflate"
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
local merge_config = 0
local _M = {}
local moesif_prepare_payload = require "moesifapi.lua.prepare_payload"
local moesif_http_conn = require "moesifapi.lua.http_connection"
local moesif_client = require "moesifapi.lua.moesif_client"

-- Send Payload
local function send_payload(sock, parsed_url, batch_events, config, user_agent_string, debug)
  local application_id = config.application_id
  local timer_start = os.date('%Y-%m-%dT%H:%M:%SZ', queue_scheduled_time)
  local timer_delay_in_seconds = (os.time() - queue_scheduled_time) / 1000

  local payload = moesif_prepare_payload.generate_post_payload(config, parsed_url, batch_events, application_id, user_agent_string, debug, timer_start, timer_delay_in_seconds)

  -- Create http client
  local httpc = moesif_client.get_http_connection(config)

  local start_req_time = socket.gettime()*1000
  -- Perform the POST request
  local res, err = moesif_http_conn.post_request(httpc, config, "/v1/events/batch", payload, false) -- isCompressed
  local end_req_time = socket.gettime()*1000
  if config.debug then
    ngx_log(ngx.DEBUG, "[moesif] USING COMMON FUNCTION Send HTTP request took time - ".. tostring(end_req_time - start_req_time).." for pid - ".. ngx.worker.pid())
  end

  -- local ok, err = sock:send(moesif_prepare_payload.generate_post_payload(config, parsed_url, batch_events, application_id, user_agent_string, debug, timer_start, timer_delay_in_seconds) .. "\r\n")
  if not res then
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] USING COMMON FUNCTION failed to send data to " .. parsed_url.host .. ":" .. tostring(parsed_url.port) .." for pid - ".. ngx.worker.pid() .. " with status: ", tostring(res.status))
    end
  else
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] USING COMMON FUNCTION Events sent successfully for pid - ".. ngx.worker.pid() , ok)
    end
  end
end

-- Get App Config function
local function get_config(premature, config, debug)
  if premature then
    return
  end

  local ok, err = pcall(moesif_client.get_config_internal, config, debug)
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
      ngx_log(ngx_log_ERR, "[moesif] Error when scheduling the get config for pid - ".. ngx.worker.pid() .. " is: ", serr)
    end
  else
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] success when scheduling the get config for pid - ".. ngx.worker.pid())
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
  local local_queue = queue_hashes
  queue_hashes = {}
  repeat
      if #local_queue > 0 and ((socket.gettime()*1000 - start_time) <= config_hashes.max_callback_time_spent) then
        ngx_log(ngx.DEBUG, "[moesif] CUSTOM Sending events to Moesif for pid - ".. ngx.worker.pid())

        local start_con_time = socket.gettime()*1000
        local sock, parsed_url = connect.get_connection(config, config.api_endpoint, "/v1/events/batch", send_events_socket)
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
            if (#batch_events == config.batch_size) then
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
          until counter == config.batch_size or next(local_queue) == nil
  
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
            ngx_log(ngx.DEBUG, "[moesif] Failure to create socket connection for sending event to Moesif for pid - ".. ngx.worker.pid())
          end
        end
        if debug then 
          ngx_log(ngx.DEBUG, "[moesif] Received Event - "..tostring(rec_event).." and Sent Event - "..tostring(sent_event).." for pid - ".. ngx.worker.pid())
        end
      else
        has_events = false
        if #local_queue <= 0 then 
          ngx_log(ngx.DEBUG, "[moesif]  CUSTOM  Queue is empty, no events to send for pid - ".. ngx.worker.pid())
        else
          ngx_log(ngx.DEBUG, "[moesif] Max callback time exceeds, skip sending events now for pid - ".. ngx.worker.pid())
        end
      end
  until has_events == false

  if not has_events then
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] No events to read from the queue for pid - ".. ngx.worker.pid())
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
  ngx_log(ngx.DEBUG, "[moesif] CUSTOM send events batch took time - ".. tostring(endtime - start_time) .. " and sent event delta - " .. tostring(sent_event - prv_events).." for pid - ".. ngx.worker.pid().. " with queue size - ".. tostring(length))

end

-- Log to a Http end point.
local function log(config, message, debug)

  -- Sampling Events
  local random_percentage = math.random() * 100
  local user_sampling_rate = nil
  local company_sampling_rate = nil
  local regex_sampling_rate = nil
  local sampling_rate = 100

  if config.sample_rate == nil then
    config.sample_rate = 100
  end

  -- calculate user level sample rate
  if type(config.user_sample_rate) == "table" and next(config.user_sample_rate) ~= nil and message["user_id"] ~= nil and config.user_sample_rate[message["user_id"]] ~= nil then
    user_sampling_rate = config.user_sample_rate[message["user_id"]]
  end

  -- calculate company level sample rate
  if type(config.company_sample_rate) == "table" and next(config.company_sample_rate) ~= nil and message["company_id"] ~= nil and config.company_sample_rate[message["company_id"]] ~= nil then
    company_sampling_rate = config.company_sample_rate[message["company_id"]]
  end

  -- calculate regex sample rate
  if type(config.regex_config) == "table" and next(config.regex_config) ~= nil then
    local config_mapping = helpers.prepare_config_mapping(message)
    local ok, sample_rate, block_rule = pcall(helpers.fetch_sample_rate_block_request_on_regex_match, config.regex_config, config_mapping)
    if ok then
      regex_sampling_rate = sample_rate
    end
  end

  -- sampling rate will be the minimum of all specific sample rates if any of them are defined
  if user_sampling_rate ~= nil or company_sampling_rate  ~= nil or regex_sampling_rate  ~= nil then
    sampling_rate = math.min((user_sampling_rate or 100), (company_sampling_rate or 100), (regex_sampling_rate or 100))
  else
    -- no specific sample rates defined, use the global sampling rate
    sampling_rate = config.sample_rate
  end

  if sampling_rate >= random_percentage then
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] Event added to the queue for pid - ".. ngx.worker.pid())
    end
    message["weight"] = (sampling_rate == 0 and 1 or math.floor(100 / sampling_rate))
    
    rec_event = rec_event + 1
    table.insert(queue_hashes, message)
  else
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] Skipped Event", " due to sampling percentage: " .. tostring(sampling_rate) .. " and random number: " .. tostring(random_percentage) .." for pid - ".. ngx.worker.pid())
    end
  end
end

-- Run the job
local function runJob(premature, config, user_agent_string, debug)
  if not premature then
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] Calling the send_events_batch function from the scheduled job for pid - ".. ngx.worker.pid())
    end
    send_events_batch(false, config, user_agent_string, debug)
    
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] Calling the scheduleJobIfNeeded function to check if needed to schedule the job for pid - ".. ngx.worker.pid())
    end

    -- Updating the queue scheduled time
    queue_scheduled_time = os.time()

    local scheduleJobOk, scheduleJobErr = ngx.timer.at(config.batch_max_time, runJob, config, user_agent_string, debug)
    if not scheduleJobOk then
      ngx_log(ngx_log_ERR, "[moesif] Error when scheduling the job:  ", scheduleJobErr)
    else
      if debug then
        ngx_log(ngx.DEBUG, "[moesif] Batch Job is scheduled successfully for pid - ".. ngx.worker.pid())
      end
    end

  end
end

-- Schedule Events batch job
local function scheduleJobIfNeeded(config, batch_max_time, user_agent_string, debug)
  if queue_scheduled_time == nil then 
    queue_scheduled_time = os.time{year=1970, month=1, day=1, hour=0}
  end
  if (os.time() >= (queue_scheduled_time + batch_max_time)) then
    
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] Batch Job is not scheduled, scheduling the job for pid - ".. ngx.worker.pid())
    end

    -- Updating the queue scheduled time
    queue_scheduled_time = os.time()

    local scheduleJobOk, scheduleJobErr = ngx.timer.at(config.batch_max_time, runJob, config, user_agent_string, debug)
    if not scheduleJobOk then
      ngx_log(ngx_log_ERR, "[moesif] Error when scheduling the job:  ", scheduleJobErr)
    else
      if debug then
        ngx_log(ngx.DEBUG, "[moesif] Batch Job is scheduled successfully for pid - ".. ngx.worker.pid())
      end
    end
  else
    if debug then
      ngx_log(ngx.DEBUG, "[moesif] Batch Job is already scheduled for pid - ".. ngx.worker.pid())
    end
  end
end

local function mergeConfigs(config)
  -- Fetch all the keys from ngx shared dict
  -- Default to 1024 (https://github.com/openresty/lua-nginx-module#ngxshareddictget_keys)
  local configKeys = config:get_keys(1024)
  -- Iterate through the list of configKeys and merge into config_hashes
  for _, key in ipairs(configKeys) do
      config_hashes[key] = config:get(key)
  end
end

function _M.execute(config, message, user_agent_string, debug)
  -- Get Application Id
  local application_id = config:get("application_id")

  -- Execute
  if next(config_hashes) == nil then
    config_hashes["sample_rate"] = 100
    config_hashes["user_sample_rate"] = {}
    config_hashes["company_sample_rate"] = {}
    config_hashes["regex_config"] = {}
    config_hashes["ETag"] = nil
    config_hashes["user_rules"] = {}
    config_hashes["company_rules"] = {}

    -- Merge User-defined and moesif configs
    mergeConfigs(config)

    if config.is_config_fetched == nil then
      if debug then
        ngx_log(ngx.DEBUG, "[moesif] Moesif Config is not fetched, calling the function to fetch configuration - ")
      end

      local ok, err = ngx.timer.at(0, get_config, config_hashes, debug)
      if not ok then
        if debug then
          ngx_log(ngx_log_ERR, "[moesif] failed to get application config, setting the sample_rate to default ", err)
        end
      else
        if debug then
          ngx_log(ngx.DEBUG, "[moesif] successfully fetched the application configuration" , ok)
        end
      end
    -- ELSE IF config.config_last_fetch_time > 2 mins (basedon the current time)
    -- config.is_config_fetched = nil
    end
  end


  -- Merge user-defined and moesif configs as user-defined config could be change at any time
  merge_config = merge_config + 1
  if merge_config == 100 then
    mergeConfigs(config)
    merge_config = 0
  end

  -- Log event to moesif
  log(config_hashes, message, debug)

  if debug then
    ngx_log(ngx.DEBUG, "[moesif] last_batch_scheduled_time before scheduleding the job - ", tostring(config_hashes.queue_scheduled_time))
  end

  scheduleJobIfNeeded(config_hashes, 5 * config_hashes.batch_max_time, user_agent_string, debug)

end

return _M
