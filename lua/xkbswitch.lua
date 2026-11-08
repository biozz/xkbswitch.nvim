local M = { events_get_focus = { "FocusGained", "CmdlineLeave" }, status = "not configured" }
local uv = vim.uv or vim.loop
local generation = 0
local options = {}

local function system_library()
  local darwin = uv.os_uname().sysname == "Darwin"
  local paths = darwin and {
    "/opt/homebrew/lib/libInputSourceSwitcher.dylib",
    "/usr/local/lib/libInputSourceSwitcher.dylib", "/usr/lib/libInputSourceSwitcher.dylib",
  } or { "/usr/local/lib64/libg3kbswitch.so", "/usr/local/lib/libg3kbswitch.so" }
  for _, path in ipairs(paths) do
    if vim.fn.filereadable(path) == 1 then return path end
  end
  if not darwin and vim.fn.executable("xkb-switch") == 1 and vim.fn.executable("ldd") == 1 then
    for _, line in ipairs(vim.fn.systemlist({ "ldd", vim.fn.exepath("xkb-switch") })) do
      if line:match("libxkbswitch%.so") then return line:match("=>%s+(/%S+)") end
    end
  end
end

local function english_layout(layouts)
  for _, layout in ipairs(layouts) do
    if layout == "com.apple.keylayout.ABC" or layout == "com.apple.keylayout.US" or layout:match("^us") then
      return layout
    end
  end
end

local function warn(message)
  M.status = "unavailable"
  M.error = message
  vim.notify("xkbswitch: " .. message .. ". Run :checkhealth xkbswitch or :XkbSwitchInstall to retry.", vim.log.levels.WARN)
end

local function activate(opts, lib, bin, token)
  if token ~= generation then return end
  local ok, err = pcall(function()
    local layouts = opts.user_layouts
    if not layouts then
      layouts = vim.fn.systemlist({ bin, "-l" })
      if vim.v.shell_error ~= 0 then error("Cannot list layouts using " .. bin) end
    end
    local normal_layout = opts.normal_layout or english_layout(layouts)
    if not normal_layout then error("No English layout found; set normal_layout or user_layouts") end
    local function get() return vim.fn.libcall(lib, "Xkb_Switch_getXkbLayout", "") end
    local function set(layout) vim.fn.libcall(lib, "Xkb_Switch_setXkbLayout", layout) end
    local saved = get()
    if saved == "" then error("The library returned an empty current layout") end
    local group = vim.api.nvim_create_augroup("XkbSwitch", { clear = true })
    local function event(events, fn)
      vim.api.nvim_create_autocmd(events, { group = group, callback = function(ev)
        if token ~= generation then return end
        local success, reason = pcall(fn, ev)
        if not success then
          vim.api.nvim_clear_autocmds({ group = group })
          warn(tostring(reason))
        end
      end })
    end
    local function normal_mode()
      local mode = vim.api.nvim_get_mode().mode
      return mode:sub(1, 1) == "n" or mode == "v" or mode == "V" or mode == "\22"
    end
    event("InsertLeave", function() saved = get(); set(normal_layout) end)
    event(opts.events_get_focus or M.events_get_focus, function(ev)
      -- CmdlineLeave commonly sees the English layout we selected ourselves.
      -- Do not overwrite the previously saved insert layout in that case.
      local current = get()
      if ev.event ~= "CmdlineLeave" or current ~= normal_layout then saved = current end
      if normal_mode() then set(normal_layout) end
    end)
    event({ "FocusLost", "InsertEnter" }, function() set(saved) end)
    M.library, M.binary, M.status, M.error = lib, bin, "ready", nil
  end)
  if not ok then warn(tostring(err)) end
end

function M.setup(opts)
  options = vim.deepcopy(opts or {})
  generation = generation + 1
  local token = generation
  vim.api.nvim_create_augroup("XkbSwitch", { clear = true })
  M.library, M.binary, M.error = nil, nil, nil
  vim.api.nvim_create_user_command("XkbSwitchInstall", function()
    local retry = vim.tbl_extend("force", options, { auto_install = true })
    M.setup(retry)
  end, { desc = "Install the pinned macOS dependency and retry xkbswitch setup", force = true })
  if options.xkb_switch_lib then
    local lib = options.xkb_switch_lib
    local bin = options.switcher_command or (lib:match("dylib$") and "issw" or lib:match("g3kb") and "g3kb-switch" or "xkb-switch")
    activate(options, lib, bin, token)
  elseif uv.os_uname().sysname == "Darwin" and options.auto_install ~= false then
    M.status = "installing"
    require("xkbswitch.install").ensure(function(err, paths)
      if token ~= generation then return end
      if err then warn(err); return end
      activate(options, paths.lib, paths.bin, token)
    end)
  else
    local lib = system_library()
    if not lib then warn("No layout-switching library found"); return end
    activate(options, lib, options.switcher_command or (lib:match("dylib$") and "issw" or lib:match("g3kb") and "g3kb-switch" or "xkb-switch"), token)
  end
end

return M
