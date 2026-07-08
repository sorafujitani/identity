-- typescript-language-serverはtypescript本体を同梱しないため、
-- workspaceにtypescriptが無いproject (bun + tsgo等) ではinitializeが失敗する。
-- globalのtypescriptから解決したlibをfallbackとして渡す。

-- tsserver自身の解決規則に合わせ、root_dirから上方向に探す
-- (hoisted monorepoではroot_dirの祖先にtypescriptが居る)
local function has_workspace_typescript(root_dir)
  local dir = root_dir
  while dir do
    if vim.uv.fs_stat(vim.fs.joinpath(dir, 'node_modules', 'typescript', 'lib', 'tsserver.js')) then
      return true
    end
    local parent = vim.fs.dirname(dir)
    if parent == dir then
      break
    end
    dir = parent
  end
  return false
end

local function tsserver_lib_of(bin_path)
  local real = bin_path and vim.uv.fs_realpath(bin_path)
  if not real then
    return nil
  end
  -- symlink型install (brew, npm -g) は .../typescript/bin/tsc に解決される
  local lib = vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(real), '..', 'lib'))
  if vim.uv.fs_stat(vim.fs.joinpath(lib, 'tsserver.js')) then
    return lib
  end
  return nil
end

-- shim型 (mise/asdf/volta) はrealpathがtypescript/binを指さないため、npm globalも当たる
local function npm_global_tsserver_lib()
  local out = vim.fn.systemlist({ 'npm', 'root', '-g' })
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == '' then
    return nil
  end
  local lib = vim.fs.joinpath(vim.trim(out[1]), 'typescript', 'lib')
  if vim.uv.fs_stat(vim.fs.joinpath(lib, 'tsserver.js')) then
    return lib
  end
  return nil
end

---@type vim.lsp.Config
return {
  cmd = { 'typescript-language-server', '--stdio' },
  filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' },
  root_markers = { 'tsconfig.json', 'jsconfig.json', 'package.json' },
  workspace_required = true,
  before_init = function(params, config)
    if has_workspace_typescript(config.root_dir) then
      return
    end
    local lib = tsserver_lib_of(vim.fn.exepath('tsc')) or npm_global_tsserver_lib()
    if not lib then
      vim.notify(
        'ts_ls: typescript not found in workspace or globally (install: brew install typescript)',
        vim.log.levels.WARN
      )
      return
    end
    params.initializationOptions = vim.tbl_deep_extend('force', params.initializationOptions or {}, {
      tsserver = { path = lib },
    })
  end,
}
