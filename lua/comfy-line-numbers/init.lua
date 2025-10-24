-- this runs when the plugin in required
-- this will only run once as the module will be cached
-- clear the cache with the following command
-- `:lua package.loaded['plugin-template'] = nil`

local enabled = false

local DEFAULT_LABELS = {
  "1",
  "2",
  "3",
  "4",
  "5",
  "11",
  "12",
  "13",
  "14",
  "15",
  "21",
  "22",
  "23",
  "24",
  "25",
  "31",
  "32",
  "33",
  "34",
  "35",
  "41",
  "42",
  "43",
  "44",
  "45",
  "51",
  "52",
  "53",
  "54",
  "55",
  "111",
  "112",
  "113",
  "114",
  "115",
  "121",
  "122",
  "123",
  "124",
  "125",
  "131",
  "132",
  "133",
  "134",
  "135",
  "141",
  "142",
  "143",
  "144",
  "145",
  "151",
  "152",
  "153",
  "154",
  "155",
  "211",
  "212",
  "213",
  "214",
  "215",
  "221",
  "222",
  "223",
  "224",
  "225",
  "231",
  "232",
  "233",
  "234",
  "235",
  "241",
  "242",
  "243",
  "244",
  "245",
  "251",
  "252",
  "253",
  "254",
  "255",
}

local M = {
  config = {
    labels = DEFAULT_LABELS,
    up_key = 'k',
    down_key = 'j',
    hidden_file_types = { 'undotree' },
    hidden_buffer_types = { 'terminal', 'nofile' },
    hide_insert_mode = false
  }
}

local should_hide_numbers = function(filetype, buftype)
  return vim.tbl_contains(M.config.hidden_file_types, filetype) or
      vim.tbl_contains(M.config.hidden_buffer_types, buftype)
end

-- Defined on the global namespace to be used in Vimscript below.
_G.get_label = function(absnum, relnum)
  if not enabled then
    return absnum
  end

  if M.config.hide_in_insert_mode and vim.fn.mode() == 'i' then
    return absnum
  end

  if relnum == 0 then
    -- Pad current line number to match width
    return string.format("%-2d", vim.fn.line ".")
  elseif relnum > 0 and relnum <= #M.config.labels then
    -- Pad label to consistent width
    return string.format("%-2s", M.config.labels[relnum])
  else
    -- Pad absolute number to consistent width
    return string.format("%-2d", absnum)
  end
end

function update_status_column()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local buftype = vim.bo[buf].buftype
    local filetype = vim.bo[buf].filetype

    if should_hide_numbers(filetype, buftype) then
      vim.api.nvim_win_call(win, function()
        vim.opt.statuscolumn = ''
      end)
    else
      vim.api.nvim_win_call(win, function()
        vim.opt.statuscolumn = '%=%s%=%{v:lua.get_label(v:lnum, v:relnum)} '
      end)
    end
  end
end

function M.enable_line_numbers()
  if enabled then
    return
  end

  for index, label in ipairs(M.config.labels) do
    vim.keymap.set({ 'n', 'v', 'o' }, label .. M.config.up_key, index .. 'k', { noremap = true })
    vim.keymap.set({ 'n', 'v', 'o' }, label .. M.config.down_key, index .. 'j', { noremap = true })
  end

  enabled = true
  update_status_column()
end

function M.disable_line_numbers()
  if not enabled then
    return
  end

  for index, label in ipairs(M.config.labels) do
    vim.keymap.del({ 'n', 'v', 'o' }, label .. M.config.up_key)
    vim.keymap.del({ 'n', 'v', 'o' }, label .. M.config.down_key)
  end


  enabled = false
  update_status_column()
end

function create_auto_commands()
  local group = vim.api.nvim_create_augroup("ComfyLineNumbers", { clear = true })

  vim.api.nvim_create_autocmd({ "WinNew", "BufWinEnter", "BufEnter", "TermOpen", "InsertEnter", "InsertLeave" }, {
    group = group,
    pattern = "*",
    callback = update_status_column
  })
end

function M.setup(config)
  M.config = vim.tbl_deep_extend("force", M.config, config or {})

  vim.api.nvim_create_user_command(
    'ComfyLineNumbers',
    function(args)
      if args.args == "enable" then
        M.enable_line_numbers()
      elseif args.args == "disable" then
        M.disable_line_numbers()
      elseif args.args == "toggle" then
        if enabled then
          M.disable_line_numbers()
        else
          M.enable_line_numbers()
        end
      else
        print("Invalid argument.")
      end
    end,
    { nargs = 1 }
  )

  vim.opt.relativenumber = true
  create_auto_commands()
  M.enable_line_numbers()
end

return M
