local ok, vscode = pcall(require, 'vscode')
if not ok then
  return
end

local function setup_vscode_plugins()
  local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
  if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
    local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
    if vim.v.shell_error ~= 0 then
      vim.notify('Failed to bootstrap lazy.nvim for VSCode mode:\n' .. out, vim.log.levels.ERROR)
      return
    end
  end

  vim.opt.rtp:prepend(lazypath)

  local lazy_ok, lazy = pcall(require, 'lazy')
  if not lazy_ok then
    return
  end

  -- Keep VSCode mode minimal: only load textobject support needed for `viq`.
  lazy.setup {
    {
      'echasnovski/mini.nvim',
      config = function()
        require('mini.ai').setup()
        require('mini.surround').setup()
      end,
    },
    {
      'folke/flash.nvim',
      event = 'VeryLazy',
      opts = {},
      keys = {
        {
          's',
          mode = { 'n', 'x', 'o' },
          function()
            require('flash').jump()
          end,
          desc = 'Flash',
        },
        {
          'S',
          mode = { 'n', 'x', 'o' },
          function()
            require('flash').treesitter()
          end,
          desc = 'Flash Treesitter',
        },
        {
          'r',
          mode = 'o',
          function()
            require('flash').remote()
          end,
          desc = 'Remote Flash',
        },
        {
          'R',
          mode = { 'o', 'x' },
          function()
            require('flash').treesitter_search()
          end,
          desc = 'Treesitter Search',
        },
        {
          '<c-s>',
          mode = { 'c' },
          function()
            require('flash').toggle()
          end,
          desc = 'Toggle Flash Search',
        },
      },
    },
  }
end

setup_vscode_plugins()

local map = function(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { silent = true, noremap = true, desc = desc })
end

-- Keep common Neovim motions/operators, but route IDE actions to VSCode.
map('n', '<leader>sf', function()
  vscode.action 'workbench.action.quickOpen'
end, 'Search files')

map('n', '<leader>sg', function()
  vscode.action 'workbench.action.findInFiles'
end, 'Search text in files')

map('n', 'gd', function()
  vscode.action 'editor.action.revealDefinition'
end, 'Go to definition')

map('n', 'gr', function()
  vscode.action 'editor.action.referenceSearch.trigger'
end, 'Find references')

map('n', '<leader>rn', function()
  vscode.action 'editor.action.rename'
end, 'Rename symbol')

map({ 'n', 'x' }, '<leader>ca', function()
  vscode.action 'editor.action.codeAction'
end, 'Code action')

map('n', '<leader>f', function()
  vscode.action 'editor.action.formatDocument'
end, 'Format document')
