---@type vim.lsp.Config
return {
  cmd = { 'rust-analyzer' },
  filetypes = { 'rust' },
  root_markers = { 'Cargo.toml', 'rust-project.json' },
  settings = {
    ['rust-analyzer'] = {
      checkOnSave = true,
      check = {
        command = 'check',
      },
      cargo = {
        allFeatures = false,
      },
      completion = {
        callable = {
          snippets = 'none',
        },
      },
    },
  },
}
