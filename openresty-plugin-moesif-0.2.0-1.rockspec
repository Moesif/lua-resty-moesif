package = "openresty-plugin-moesif"  -- TODO: rename, must match the info in the filename of this rockspec!
                                  -- as a convention; stick to the prefix: `kong-plugin-`
version = "0.2.0-1"               -- TODO: renumber, must match the info in the filename of this rockspec!
-- The version '0.2.0' is the source code version, the trailing '1' is the version of this rockspec.
-- whenever the source version changes, the rockspec should be reset to 1. The rockspec version is only
-- updated (incremented) when this file changes, but the source remains the same.

-- TODO: This is the name to set in the Kong configuration `custom_plugins` setting.
-- Here we extract it from the package name.
local pluginName = package:match("^openresty%-plugin%-(.+)$")  -- "moesif"

supported_platforms = {"linux", "macosx"}
source = {
  url = "git://github.com/Moesif/openresty-plugin-moesif",
  tag = "0.2.0"
}

description = {
  summary = "Moesif plugin for Openresty",
  homepage = "http://moesif.com",
  license = "MIT"
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["openresty.plugins.moesif.send_event"] = "openresty/plugins/moesif/send_event.lua",
    ["openresty.plugins.moesif.log"] = "openresty/plugins/moesif/log.lua",
    ["openresty.plugins.moesif.moesif_ser"] = "openresty/plugins/moesif/moesif_ser.lua",
    ["openresty.plugins.moesif.helpers"] = "openresty/plugins/moesif/helpers.lua",
    ["openresty.plugins.moesif.connection"] = "openresty/plugins/moesif/connection.lua",
    ["openresty.plugins.moesif.lib_deflate"] = "openresty/plugins/moesif/lib_deflate.lua",
    ["openresty.plugins.moesif.client_ip"] = "openresty/plugins/moesif/client_ip.lua",
    ["openresty.plugins.moesif.zzlib"] = "openresty/plugins/moesif/zzlib.lua"
  }
}
