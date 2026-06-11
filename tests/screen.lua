-- Real-rendering regression test for bug 1 (stale statuscolumn cache on
-- mode change). Runs a nested interactive nvim in a :terminal and reads the
-- rendered screen, so per-line statuscolumn caching is actually exercised.
local repo = vim.fn.getcwd()
vim.opt.runtimepath:prepend(repo)

vim.fn.writefile({
  "vim.opt.runtimepath:prepend('" .. repo .. "')",
  "vim.opt.swapfile = false",
  "require('comfy-line-numbers').setup({})",
}, '/tmp/nested_init.lua')

-- Sample file: text lines + a blank region (user repro: enter insert on blank)
local sample = {}
for i = 1, 14 do
  if i >= 6 and i <= 8 then
    sample[i] = ''
  else
    sample[i] = ('text%d'):format(i)
  end
end
vim.fn.writefile(sample, '/tmp/sample.txt')

vim.o.lines = 25
vim.o.columns = 60

local term_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(term_buf)
local chan = vim.fn.termopen({ 'nvim', '--clean', '-u', '/tmp/nested_init.lua', '/tmp/sample.txt' })

local fails = {}

-- Read gutter token of each rendered screen row that shows a sample line.
local function gutters()
  local rows = vim.api.nvim_buf_get_lines(term_buf, 0, 14, false)
  local out = {}
  for i, row in ipairs(rows) do
    out[i] = (row:match('^%s*(%S+)') or '?')
  end
  return out
end

local function expect_gutters(desc, want)
  local got = gutters()
  for i = 1, 14 do
    if got[i] ~= want[i] then
      fails[#fails + 1] = ('%s row %d: got %q want %q'):format(desc, i, got[i], want[i])
    end
  end
end

local function absolute()
  local w = {}
  for i = 1, 14 do w[i] = tostring(i) end
  return w
end

-- Expected normal-mode gutter with cursor on line `cur`
local labels = require('comfy-line-numbers').config.labels
local function relative(cur)
  local w = {}
  for i = 1, 14 do
    local rel = math.abs(i - cur)
    w[i] = rel == 0 and tostring(cur) or labels[rel]
  end
  return w
end

local steps = {
  { 800, function() expect_gutters('startup (cursor line 1)', relative(1)) end },
  -- move cursor to blank line 7
  { 100, function() vim.fn.chansend(chan, '6j') end },
  { 300, function() expect_gutters('normal cursor blank line 7', relative(7)) end },
  -- THE BUG: enter insert on blank line -> every line must show absolute
  { 100, function() vim.fn.chansend(chan, 'i') end },
  { 400, function() expect_gutters('insert entered on blank line', absolute()) end },
  -- leave insert -> back to relative
  { 100, function() vim.fn.chansend(chan, vim.api.nvim_replace_termcodes('<Esc>', true, false, true)) end },
  { 400, function() expect_gutters('back to normal', relative(7)) end },
  -- also: Ctrl-C exit path (InsertLeave does NOT fire for <C-c>)
  { 100, function() vim.fn.chansend(chan, 'i') end },
  { 400, function() vim.fn.chansend(chan, vim.api.nvim_replace_termcodes('<C-c>', true, false, true)) end },
  { 400, function() expect_gutters('after Ctrl-C leave', relative(7)) end },
  {
    100,
    function()
      if #fails == 0 then
        io.stderr:write('TERM TEST OK\n')
      else
        io.stderr:write('TERM TEST FAIL:\n' .. table.concat(fails, '\n') .. '\n')
      end
      vim.cmd('qa!')
    end,
  },
}

local function run(i)
  local s = steps[i]
  if not s then return end
  vim.defer_fn(function()
    local ok, err = pcall(s[2])
    if not ok then
      io.stderr:write('STEP ERROR ' .. i .. ': ' .. tostring(err) .. '\n')
      vim.cmd('qa!')
    end
    run(i + 1)
  end, s[1])
end
run(1)
