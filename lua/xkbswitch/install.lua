local M = {}
local uv = vim.uv or vim.loop
M.version = "native-v0.1.1"
local asset = "input-source-switcher-macos-universal.tar.gz"
local base = "https://github.com/biozz/xkbswitch.nvim/releases/download/" .. M.version .. "/"
local pending

function M.paths()
  local root = vim.fn.stdpath("data") .. "/xkbswitch/" .. M.version
  return { root = root, lib = root .. "/lib/libInputSourceSwitcher.dylib", bin = root .. "/bin/issw" }
end

function M.ready()
  local p = M.paths()
  return vim.fn.filereadable(p.lib) == 1 and vim.fn.executable(p.bin) == 1
end

function M.ensure(callback)
  if M.ready() then callback(nil, M.paths()); return end
  if pending then table.insert(pending, callback); return end
  if uv.os_uname().sysname ~= "Darwin" then callback("Automatic installation supports macOS only"); return end
  if not vim.system then callback("Automatic installation requires Neovim 0.10+"); return end
  for _, command in ipairs({ "curl", "tar", "shasum" }) do
    if vim.fn.executable(command) ~= 1 then callback("Missing executable: " .. command); return end
  end
  pending = { callback }
  local p = M.paths()
  local stage = p.root .. ".tmp-" .. uv.os_getpid() .. "-" .. uv.hrtime()
  local ok, err = pcall(vim.fn.mkdir, stage, "p")
  local function finish(message)
    vim.fn.delete(stage, "rf")
    local callbacks = pending
    pending = nil
    for _, cb in ipairs(callbacks) do cb(message, not message and p or nil) end
  end
  if not ok then finish(tostring(err)); return end
  local function run(args, next_step)
    local started, failure = pcall(vim.system, args, { text = true, timeout = 120000 }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          finish(args[1] .. " failed: " .. vim.trim(result.stderr or "") .. " (exit " .. result.code .. ")")
        else next_step(result.stdout) end
      end)
    end)
    if not started then finish(tostring(failure)) end
  end
  local function download(name, next_step)
    run({ "curl", "--fail", "--location", "--silent", "--show-error", "--proto", "=https",
      "--proto-redir", "=https", "--connect-timeout", "10", "--max-time", "60",
      "--output", stage .. "/" .. name, base .. name }, next_step)
  end
  download(asset, function()
    download("SHA256SUMS", function()
      local expected
      for _, line in ipairs(vim.fn.readfile(stage .. "/SHA256SUMS")) do
        local hash, name = line:match("^(%x+)%s+%*?(.+)$")
        if name == asset and #hash == 64 then expected = hash:lower() end
      end
      if not expected then finish("Release checksum is missing or invalid"); return end
      run({ "shasum", "-a", "256", stage .. "/" .. asset }, function(output)
        if output:match("^(%x+)") ~= expected then finish("Release checksum mismatch"); return end
        local unpacked = stage .. "/package"
        vim.fn.mkdir(unpacked, "p")
        run({ "tar", "-xzf", stage .. "/" .. asset, "-C", unpacked }, function()
          if vim.fn.filereadable(unpacked .. "/lib/libInputSourceSwitcher.dylib") ~= 1
            or vim.fn.executable(unpacked .. "/bin/issw") ~= 1 then
            finish("Release package is incomplete"); return
          end
          -- Same-filesystem rename publishes only a fully downloaded, verified package.
          -- Another Neovim may have completed its own installation in the meantime.
          if M.ready() then finish(); return end
          local renamed, reason = uv.fs_rename(unpacked, p.root)
          if not renamed and not M.ready() then finish("Cannot install package: " .. tostring(reason)); return end
          finish()
        end)
      end)
    end)
  end)
end

return M
