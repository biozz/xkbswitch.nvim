-- Run from the repository with isolated XDG_DATA_HOME; never touches live config.
vim.opt.rtp:prepend(vim.fn.getcwd())
local function check(value, message) assert(value, message) end
local actual_system = vim.system
local actual_libcall = vim.fn.libcall
local actual_systemlist = vim.fn.systemlist
local notifications = {}
vim.notify = function(message) table.insert(notifications, message) end
local calls = {}
local current = "ru"
vim.fn.libcall = function(lib, symbol, value)
  check(lib ~= nil, "libcall before library resolution")
  table.insert(calls, { lib, symbol, value })
  if symbol == "Xkb_Switch_getXkbLayout" then return current end
  current = value
  return ""
end
local switch = require("xkbswitch")
check(#calls == 0, "require must not call a library")
vim.fn.systemlist = function(args)
  check(args[2] == "-l", "layout discovery arguments")
  return { "com.apple.keylayout.ABC", "ru" }
end
switch.setup({ xkb_switch_lib = "/test/library.dylib" })
check(switch.status == "ready", switch.error)
check(#vim.api.nvim_get_autocmds({ group = "XkbSwitch" }) == 5, "autocmd registration")
vim.api.nvim_exec_autocmds("InsertLeave", {})
check(current == "com.apple.keylayout.ABC", "InsertLeave switches to English")
vim.api.nvim_exec_autocmds("CmdlineLeave", {})
vim.api.nvim_exec_autocmds("InsertEnter", {})
check(current == "ru", "command line must preserve saved insert layout")
current = "com.apple.keylayout.ABC"
vim.api.nvim_exec_autocmds("FocusGained", {})
vim.api.nvim_exec_autocmds("InsertEnter", {})
check(current == "com.apple.keylayout.ABC", "focus gain must respect externally selected English")
switch.setup({ xkb_switch_lib = "/test/library.dylib" })
check(#vim.api.nvim_get_autocmds({ group = "XkbSwitch" }) == 5, "setup must be idempotent")
vim.fn.libcall = actual_libcall
vim.fn.systemlist = actual_systemlist

local install = require("xkbswitch.install")
local root = install.paths().root
check(root:find("xkbswitch%-test"), "Use isolated XDG_DATA_HOME containing xkbswitch-test")
local mode, downloads = "good", 0
vim.system = function(args, opts, callback)
  if args[1] ~= "curl" then return actual_system(args, opts, callback) end
  downloads = downloads + 1
  local destination = args[#args - 1]
  local name = args[#args]:match("/([^/]+)$")
  if mode == "offline" then
    vim.schedule(function() callback({ code = 6, stderr = "simulated offline" }) end)
  else
    if mode == "bad checksum" and name == "SHA256SUMS" then
      vim.fn.writefile({ string.rep("0", 64) .. "  input-source-switcher-macos-universal.tar.gz" }, destination)
    else
      check(vim.uv.fs_copyfile("dist/" .. name, destination), "copy release fixture")
    end
    vim.schedule(function() callback({ code = 0, stdout = "", stderr = "" }) end)
  end
  return { kill = function() end }
end
local function ensure()
  local done, error_message = false, nil
  install.ensure(function(err) error_message, done = err, true end)
  check(vim.wait(10000, function() return done end), "installer timed out")
  return error_message
end
mode = "offline"
check(ensure():find("offline"), "offline error is reported")
check(not install.ready(), "failed download must not publish a package")
mode = "bad checksum"
check(ensure():find("checksum mismatch"), "bad checksum is rejected")
check(not install.ready(), "checksum failure must not publish a package")
mode = "good"
-- A killed process can leave an incomplete staging directory. It must never be
-- treated as a usable installation or block the next process.
local interrupted = root .. ".tmp-interrupted"
vim.fn.mkdir(interrupted, "p")
vim.fn.writefile({ "partial download" }, interrupted .. "/archive.part")
local callbacks = 0
install.ensure(function(err) check(not err, err); callbacks = callbacks + 1 end)
install.ensure(function(err) check(not err, err); callbacks = callbacks + 1 end)
check(vim.wait(10000, function() return callbacks == 2 end), "concurrent callbacks finish")
check(install.ready(), "fresh installation succeeds")
local count = downloads
mode = "offline"
check(not ensure(), "offline cache reuse succeeds")
check(downloads == count, "warm start must not access network")
vim.fn.delete(interrupted, "rf")
check(#vim.fn.glob(root .. ".tmp-*", false, true) == 0, "temporary downloads cleaned")

-- Verify the actual packaged CLI and dylib, without changing the user's layout.
local package = install.paths()
local result = actual_system({ package.bin, "-l" }, { text = true }):wait()
check(result.code == 0 and result.stdout:find("com.apple.keylayout.", 1, true), "packaged CLI discovers layouts")
check(actual_libcall(package.lib, "Xkb_Switch_getXkbLayout", "") ~= "", "packaged library reads current layout")
switch.setup({ auto_install = true })
check(switch.status == "ready", switch.error)
check(switch.library == package.lib, "setup uses managed dependency over system library")
check(downloads == count, "setup reuses package offline")
vim.system = actual_system
print("PASS: initialization, layout restore, idempotency, offline failure, checksum rejection, concurrent install, cached startup, real CLI/dylib")
