local moesif_ser = require "moesif_ser"
local log = require "log"
local helpers = require "helpers"

-- Global config
local config = helpers.set_default_config_value(ngx.shared.moesif_conf)

-- User Agent String
local user_agent_string = "lua-resty-moesif/1.3.12"

-- Log Event
if helpers.isempty(config:get("application_id")) then
  ngx.log(ngx.ERR, "[moesif] Please provide the Moesif Application Id");
else
  local logEvent = ngx.var.moesif_log_event
  if (logEvent == nil or logEvent == '') or (string.lower(logEvent) == "true") then
    local message = moesif_ser.prepare_message(config)

    if next(message) ~= nil then
      -- Execute/Log message
      log.execute(config, message, user_agent_string, config:get("debug"))
    end
  end
end
