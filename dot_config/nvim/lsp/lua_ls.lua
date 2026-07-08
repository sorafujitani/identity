---@type vim.lsp.Config
return {
  cmd = { 'lua-language-server' },
  filetypes = { 'lua' },
  root_markers = { '.luarc.json', '.luarc.jsonc', '.git' },
  settings = {
    Lua = {
      runtime = { version = 'LuaJIT' },
      diagnostics = {
        -- globals は .luarc.json 側で一元管理 (重複キーは .luarc.json が勝つため)
        unusedLocalExclude = { '_*' },
      },
      workspace = {
        checkThirdParty = false,
        library = {
          vim.env.VIMRUNTIME,
          vim.fn.stdpath('config') .. '/lua',
        },
        maxPreload = 1000,
        preloadFileSize = 500,
      },
      telemetry = { enable = false },
    },
  },
}
