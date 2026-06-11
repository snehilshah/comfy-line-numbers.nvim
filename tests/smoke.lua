vim.opt.runtimepath:prepend(vim.fn.getcwd())
require('comfy-line-numbers').setup({ hide_in_insert_mode = false })

local lines = {}
for i = 1, 30 do lines[i] = ('line %d'):format(i) end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.api.nvim_win_set_cursor(0, { 10, 0 })

local function eval_col(lnum)
  return vim.trim(vim.api.nvim_eval_statusline(vim.wo.statuscolumn, {
    use_statuscol_lnum = lnum,
  }).str)
end

local fails = {}
local function expect(desc, got, want)
  if got ~= want then
    fails[#fails + 1] = ('%s: got %q want %q'):format(desc, got, want)
  end
end

-- Steps run on the main loop 50ms apart so nvim_input keys get processed
-- between them (feedkeys 'x!' deadlocks in --headless).
local steps = {
  function()
    expect('normal cursor line', eval_col(10), '10')
    expect('normal relnum 1', eval_col(11), '1')
    expect('normal relnum 5', eval_col(15), '5')
    expect('normal relnum 6', eval_col(16), '11')
    expect('normal 5 above cursor', eval_col(5), '5')
    expect('normal 9 above cursor', eval_col(1), '14')
    vim.api.nvim_input('i')
  end,
  function()
    expect('mode is insert', vim.api.nvim_get_mode().mode, 'i')
    for _, l in ipairs({ 1, 5, 10, 11, 20, 30 }) do
      expect('insert line ' .. l, eval_col(l), tostring(l))
    end
    vim.api.nvim_input('<Esc>')
  end,
  function()
    expect('mode back to normal', vim.api.nvim_get_mode().mode, 'n')
    require('comfy-line-numbers').config.hide_in_insert_mode = true
    vim.api.nvim_input('i')
  end,
  function()
    expect('hidden insert line 10', eval_col(10), '')
    expect('hidden insert line 20', eval_col(20), '')
    vim.api.nvim_input('<Esc>')
  end,
  function()
    expect('back to normal relnum 1', eval_col(11), '1')
    vim.api.nvim_win_set_cursor(0, { 10, 0 })
    vim.api.nvim_input('11j')
  end,
  function()
    expect('11j moves to line 16', tostring(vim.api.nvim_win_get_cursor(0)[1]), '16')
    vim.cmd('new')
    vim.bo.buftype = 'nofile'
    vim.api.nvim_exec_autocmds('BufWinEnter', {})
    expect('nofile statuscolumn empty', vim.wo.statuscolumn, '')
    vim.cmd('close')
  end,
  function()
    if #fails == 0 then
      io.stderr:write('SMOKE OK\n')
    else
      io.stderr:write('SMOKE FAIL:\n' .. table.concat(fails, '\n') .. '\n')
    end
    vim.cmd('qa!')
  end,
}

local function run(i)
  if not steps[i] then return end
  vim.defer_fn(function()
    local ok, err = pcall(steps[i])
    if not ok then
      io.stderr:write('STEP ERROR ' .. i .. ': ' .. tostring(err) .. '\n')
      vim.cmd('qa!')
    end
    run(i + 1)
  end, 50)
end
run(1)
