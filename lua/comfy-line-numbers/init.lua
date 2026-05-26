-- comfy-line-numbers: home-row labels for relative line numbers.
-- Stability notes:
--   * statuscolumn is set per window (vim.wo[win]) so other plugins / windows
--     can keep their own statuscolumn without being clobbered.
--   * a single augroup owns all autocmds; updates are debounced through a
--     single uv timer to avoid redraw storms on cursor/insert events.
--   * keymaps are guarded so enable/disable are idempotent.

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
    hide_in_insert_mode = false,
    right_padding = 1,
  },
}

-- Marker token written into statuscolumn so we can recognize windows we own.
-- Layout: fold column (%C), signs (%s), then right-aligned line label.
-- Baking %C into the template avoids race conditions with external prepend
-- autocmds that would otherwise stack arrows on every event.
-- Trailing space matches the original GitHub template (small gap between
-- the label and buffer text).
local OUR_STATUSCOL = '%C%s%=%{v:virtnum > 0 ? "" : v:lua.get_label(v:lnum, v:relnum)} '

-- Debounce timer for redraws/statuscolumn updates.
local _redraw_timer
local _update_timer

local function is_insert_mode()
  local mode = vim.api.nvim_get_mode().mode
  return mode == 'i' or mode == 'ic' or mode == 'ix'
end

local function should_hide_numbers(filetype, buftype)
  if vim.tbl_contains(M.config.hidden_file_types, filetype)
      or vim.tbl_contains(M.config.hidden_buffer_types, buftype) then
    return true
  end
  if M.config.hide_in_insert_mode and is_insert_mode() then
    return true
  end
  return false
end

-- Defined on the global namespace to be used in the statuscolumn template.
_G.get_label = function(absnum, relnum)
  if not enabled then
    return absnum
  end

  -- All branches use a 2-char left-aligned format. Short values get a trailing
  -- space, longer ones (e.g. 3-char labels "155") render at natural width.
  -- This matches the original gutter width before the numberwidth refactor.
  if is_insert_mode() or not vim.wo.relativenumber then
    return string.format('%-2d', absnum)
  end

  if relnum == 0 then
    return string.format('%-2d', vim.fn.line('.'))
  elseif relnum > 0 and relnum <= #M.config.labels then
    return string.format('%-2s', M.config.labels[relnum])
  else
    return string.format('%-2d', absnum)
  end
end

--- Apply or clear the comfy statuscolumn on a single window.
--- @param win number window handle
local function apply_window(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local buftype = vim.bo[buf].buftype
  local filetype = vim.bo[buf].filetype

  if should_hide_numbers(filetype, buftype) then
    -- Only clear if WE set this window's statuscolumn (avoid stomping other plugins).
    if vim.wo[win].statuscolumn == OUR_STATUSCOL or vim.wo[win].statuscolumn:find('v:lua%.get_label', 1) then
      vim.wo[win].statuscolumn = ''
    end
    return
  end

  -- Don't override numberwidth: inherit global (typically 1). The label
  -- function below produces naturally-padded strings, and statuscolumn auto-
  -- sizes to the rendered content. Forcing a min width here added wasted
  -- space on the left of the gutter without any benefit.
  vim.wo[win].statuscolumn = OUR_STATUSCOL
end

local function update_status_column()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    apply_window(win)
  end
end

local function schedule_update()
  if _update_timer then
    _update_timer:stop()
    _update_timer:close()
    _update_timer = nil
  end
  _update_timer = vim.uv.new_timer()
  if not _update_timer then
    update_status_column()
    return
  end
  _update_timer:start(20, 0, vim.schedule_wrap(function()
    if _update_timer then
      _update_timer:stop()
      _update_timer:close()
      _update_timer = nil
    end
    update_status_column()
  end))
end

local function schedule_redraw()
  if _redraw_timer then
    _redraw_timer:stop()
    _redraw_timer:close()
    _redraw_timer = nil
  end
  _redraw_timer = vim.uv.new_timer()
  if not _redraw_timer then
    vim.cmd('redraw')
    return
  end
  _redraw_timer:start(30, 0, vim.schedule_wrap(function()
    if _redraw_timer then
      _redraw_timer:stop()
      _redraw_timer:close()
      _redraw_timer = nil
    end
    pcall(vim.cmd, 'redraw')
  end))
end

-- Expose for numbertoggle.lua
_G.update_status_column = update_status_column

function M.enable_line_numbers()
  if enabled then
    return
  end

  for index, label in ipairs(M.config.labels) do
    -- pcall: tolerate the unlikely case that a previous instance left bindings around
    pcall(vim.keymap.set, { 'n', 'v', 'o' }, label .. M.config.up_key, index .. 'k', { noremap = true })
    pcall(vim.keymap.set, { 'n', 'v', 'o' }, label .. M.config.down_key, index .. 'j', { noremap = true })
  end

  enabled = true
  update_status_column()
end

function M.disable_line_numbers()
  if not enabled then
    return
  end

  for _, label in ipairs(M.config.labels) do
    pcall(vim.keymap.del, { 'n', 'v', 'o' }, label .. M.config.up_key)
    pcall(vim.keymap.del, { 'n', 'v', 'o' }, label .. M.config.down_key)
  end

  enabled = false
  update_status_column()
end

local function create_auto_commands()
  local group = vim.api.nvim_create_augroup('ComfyLineNumbers', { clear = true })

  vim.api.nvim_create_autocmd(
    { 'WinNew', 'BufWinEnter', 'BufEnter', 'TermOpen', 'FileType' },
    {
      group = group,
      pattern = '*',
      callback = schedule_update,
    }
  )

  vim.api.nvim_create_autocmd({ 'InsertEnter', 'InsertLeave', 'ModeChanged' }, {
    group = group,
    pattern = '*',
    callback = function()
      if M.config.hide_in_insert_mode then
        -- statuscolumn template includes mode-aware branches, but force a redraw
        -- so the screen reflects the new mode immediately.
        schedule_redraw()
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'VimResized' }, {
    group = group,
    pattern = '*',
    callback = schedule_update,
  })
end

function M.setup(config)
  M.config = vim.tbl_deep_extend('force', M.config, config or {})

  local padding = string.rep(' ', M.config.right_padding or 1)
  OUR_STATUSCOL = '%C%s%=%{v:virtnum > 0 ? "" : v:lua.get_label(v:lnum, v:relnum)}' .. padding

  vim.api.nvim_create_user_command(
    'ComfyLineNumbers',
    function(args)
      if args.args == 'enable' then
        M.enable_line_numbers()
      elseif args.args == 'disable' then
        M.disable_line_numbers()
      elseif args.args == 'toggle' then
        if enabled then
          M.disable_line_numbers()
        else
          M.enable_line_numbers()
        end
      else
        vim.notify('ComfyLineNumbers: expected enable|disable|toggle', vim.log.levels.WARN)
      end
    end,
    { nargs = 1 }
  )

  vim.opt.relativenumber = true
  create_auto_commands()
  M.enable_line_numbers()
end

return M
