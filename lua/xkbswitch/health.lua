local M = {}
function M.check()
  local health = vim.health
  local switch = require("xkbswitch")
  local install = require("xkbswitch.install")
  health.start("xkbswitch")
  health.info("State: " .. switch.status)
  health.info("Managed dependency: " .. install.version .. " at " .. install.paths().root)
  if switch.status == "ready" then
    health.ok("Library: " .. switch.library)
    health.info("Layout discovery command: " .. switch.binary)
  elseif switch.error then health.error(switch.error)
  else health.warn("Setup has not completed") end
  for _, name in ipairs({ "curl", "tar", "shasum" }) do
    if vim.fn.executable(name) == 1 then health.ok(name .. " available")
    else health.warn(name .. " missing (required for automatic macOS installation)") end
  end
end
return M
