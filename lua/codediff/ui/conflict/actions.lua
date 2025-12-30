-- Conflict resolution actions (accept incoming/current/both, discard)
local M = {}

local lifecycle = require('codediff.ui.lifecycle')
local auto_refresh = require('codediff.ui.auto_refresh')

-- Will be injected by init.lua
local tracking = nil
local signs = nil
M._set_tracking_module = function(t) tracking = t end
M._set_signs_module = function(s) signs = s end

--- Apply text to result buffer at the conflict's range
--- @param result_bufnr number Result buffer
--- @param block table Conflict block with base_range and optional extmark_id
--- @param lines table Lines to insert
--- @param base_lines table Original BASE content (for fallback)
local function apply_to_result(result_bufnr, block, lines, base_lines)
  local start_row, end_row
  
  -- Method 1: Try using extmarks (robust against edits)
  if block.extmark_id then
    local mark = vim.api.nvim_buf_get_extmark_by_id(result_bufnr, tracking.tracking_ns, block.extmark_id, { details = true })
    if mark and #mark >= 3 then
      start_row = mark[1]
      end_row = mark[3].end_row
    end
  end
  
  -- Method 2: Fallback to content search or original range
  if not start_row then
    local base_range = block.base_range
    -- We need to find where this base_range maps to in the current result buffer
    -- The result buffer starts as BASE, so initially base_range maps 1:1
    -- After edits, we need to track the offset
  
    -- For simplicity, we'll re-apply based on content matching
    -- Find the base content in the result buffer
    local base_content = {}
    for i = base_range.start_line, base_range.end_line - 1 do
      table.insert(base_content, base_lines[i] or "")
    end
  
    local result_lines = vim.api.nvim_buf_get_lines(result_bufnr, 0, -1, false)
  
    -- Search for the base content in result buffer
    -- This is a simple approach; VSCode uses more sophisticated tracking
    local found_start = nil
    for i = 1, #result_lines - #base_content + 1 do
      local match = true
      for j = 1, #base_content do
        if result_lines[i + j - 1] ~= base_content[j] then
          match = false
          break
        end
      end
      if match then
        found_start = i
        break
      end
    end
  
    if found_start then
      start_row = found_start - 1
      end_row = found_start - 1 + #base_content
    else
      -- Fallback: try to find by approximate position
      -- Use base_range directly (works if no prior edits)
      start_row = math.min(base_range.start_line - 1, #result_lines)
      end_row = math.min(base_range.end_line - 1, #result_lines)
    end
  end
  
  if start_row and end_row then
    vim.api.nvim_buf_set_lines(result_bufnr, start_row, end_row, false, lines)
  end
end

--- Accept incoming (left/input1) side for the conflict under cursor
--- @param tabpage number
--- @return boolean success
function M.accept_incoming(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session then
    vim.notify("[codediff] No active session", vim.log.levels.WARN)
    return false
  end

  if not session.conflict_blocks or #session.conflict_blocks == 0 then
    vim.notify("[codediff] No conflicts in this session", vim.log.levels.WARN)
    return false
  end

  -- Determine which buffer cursor is in and find the conflict
  local current_buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local side = nil

  if current_buf == session.original_bufnr then
    side = "left"
  elseif current_buf == session.modified_bufnr then
    side = "right"
  else
    vim.notify("[codediff] Cursor not in diff buffer", vim.log.levels.WARN)
    return false
  end

  local block = tracking.find_conflict_at_cursor(session, cursor_line, side, false)
  if not block then
    vim.notify("[codediff] No active conflict at cursor position", vim.log.levels.INFO)
    return false
  end

  -- Get incoming (left) content
  local incoming_lines = tracking.get_lines_for_range(session.original_bufnr, block.output1_range.start_line, block.output1_range.end_line)

  -- Apply to result
  local result_bufnr = session.result_bufnr
  local base_lines = session.result_base_lines
  if not result_bufnr or not base_lines then
    vim.notify("[codediff] No result buffer or base lines", vim.log.levels.ERROR)
    return false
  end

  apply_to_result(result_bufnr, block, incoming_lines, base_lines)
  signs.refresh_all_conflict_signs(session)
  auto_refresh.refresh_result_now(result_bufnr)
  return true
end

--- Accept current (right/input2) side for the conflict under cursor
--- @param tabpage number
--- @return boolean success
function M.accept_current(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session then
    vim.notify("[codediff] No active session", vim.log.levels.WARN)
    return false
  end

  if not session.conflict_blocks or #session.conflict_blocks == 0 then
    vim.notify("[codediff] No conflicts in this session", vim.log.levels.WARN)
    return false
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local side = nil

  if current_buf == session.original_bufnr then
    side = "left"
  elseif current_buf == session.modified_bufnr then
    side = "right"
  else
    vim.notify("[codediff] Cursor not in diff buffer", vim.log.levels.WARN)
    return false
  end

  local block = tracking.find_conflict_at_cursor(session, cursor_line, side, false)
  if not block then
    vim.notify("[codediff] No active conflict at cursor position", vim.log.levels.INFO)
    return false
  end

  -- Get current (right) content
  local current_lines = tracking.get_lines_for_range(session.modified_bufnr, block.output2_range.start_line, block.output2_range.end_line)

  local result_bufnr = session.result_bufnr
  local base_lines = session.result_base_lines
  if not result_bufnr or not base_lines then
    vim.notify("[codediff] No result buffer or base lines", vim.log.levels.ERROR)
    return false
  end

  apply_to_result(result_bufnr, block, current_lines, base_lines)
  signs.refresh_all_conflict_signs(session)
  auto_refresh.refresh_result_now(result_bufnr)
  return true
end

--- Compare two positions (line, col) - returns true if a < b
--- @param a_line number
--- @param a_col number
--- @param b_line number
--- @param b_col number
--- @return boolean
local function position_less_than(a_line, a_col, b_line, b_col)
  if a_line ~= b_line then
    return a_line < b_line
  end
  return a_col < b_col
end

--- Compare two positions - returns true if a <= b
--- @param a_line number
--- @param a_col number
--- @param b_line number
--- @param b_col number
--- @return boolean
local function position_less_or_equal(a_line, a_col, b_line, b_col)
  if a_line ~= b_line then
    return a_line < b_line
  end
  return a_col <= b_col
end

--- Try to smart combine inputs like VSCode does
--- This interleaves character-level edits sorted by their position in base
--- Returns nil if edits overlap and cannot be combined
--- @param block table Conflict block with inner1, inner2
--- @param base_lines table Base file lines
--- @param input1_lines table Input1 (left/incoming) lines
--- @param input2_lines table Input2 (right/current) lines
--- @param first_input number 1 or 2 - which input takes priority on ties
--- @return table|nil Combined lines, or nil if cannot be combined
local function smart_combine_inputs(block, base_lines, input1_lines, input2_lines, first_input)
  local inner1 = block.inner1 or {}
  local inner2 = block.inner2 or {}
  
  -- If either side has no inner changes, we can't do smart combination
  -- (means entire block was replaced, not fine-grained edits)
  if #inner1 == 0 or #inner2 == 0 then
    return nil
  end
  
  -- Collect all range edits with their source
  local combined_edits = {}
  
  for _, inner in ipairs(inner1) do
    table.insert(combined_edits, { inner = inner, input = 1 })
  end
  for _, inner in ipairs(inner2) do
    table.insert(combined_edits, { inner = inner, input = 2 })
  end
  
  -- Sort by position in base (original range), with first_input taking priority on ties
  table.sort(combined_edits, function(a, b)
    local a_start_line = a.inner.original.start_line
    local a_start_col = a.inner.original.start_col
    local b_start_line = b.inner.original.start_line
    local b_start_col = b.inner.original.start_col
    
    if a_start_line ~= b_start_line then
      return a_start_line < b_start_line
    end
    if a_start_col ~= b_start_col then
      return a_start_col < b_start_col
    end
    -- Tie-breaker: first_input comes first
    local a_priority = (a.input == first_input) and 1 or 2
    local b_priority = (b.input == first_input) and 1 or 2
    return a_priority < b_priority
  end)
  
  -- Build the result by applying edits in order
  -- Track current position in base
  local base_range = block.base_range
  local result_text = ""
  
  -- Start position: line before base_range if exists, otherwise start of base_range
  local starts_line_before = base_range.start_line > 1
  local current_line, current_col
  if starts_line_before then
    current_line = base_range.start_line - 1
    current_col = #(base_lines[current_line] or "") + 1  -- End of previous line (after last char)
  else
    current_line = base_range.start_line
    current_col = 1
  end
  
  -- Helper to get text from base between two positions
  local function get_base_text(from_line, from_col, to_line, to_col)
    if from_line > #base_lines then
      return ""
    end
    
    local text = ""
    for line = from_line, math.min(to_line, #base_lines) do
      local line_text = base_lines[line] or ""
      local start_c = (line == from_line) and from_col or 1
      local end_c = (line == to_line) and (to_col - 1) or #line_text
      
      if start_c <= #line_text then
        text = text .. line_text:sub(start_c, math.max(start_c - 1, end_c))
      end
      
      -- Add newline between lines (not after last)
      if line < to_line then
        text = text .. "\n"
      end
    end
    return text
  end
  
  -- Helper to get text from input for a modified range
  local function get_input_text(input_num, range)
    local lines = (input_num == 1) and input1_lines or input2_lines
    local text = ""
    
    for line = range.start_line, range.end_line do
      local line_text = lines[line - ((input_num == 1) and block.output1_range.start_line or block.output2_range.start_line) + 1] or ""
      local start_c = (line == range.start_line) and range.start_col or 1
      local end_c = (line == range.end_line) and (range.end_col - 1) or #line_text
      
      if start_c <= #line_text + 1 then
        text = text .. line_text:sub(start_c, math.max(start_c - 1, end_c))
      end
      
      -- Add newline between lines
      if line < range.end_line then
        text = text .. "\n"
      end
    end
    return text
  end
  
  for _, edit in ipairs(combined_edits) do
    local inner = edit.inner
    local orig = inner.original
    local modif = inner.modified
    
    -- Check if this edit overlaps with current position (would mean edits conflict)
    if not position_less_or_equal(current_line, current_col, orig.start_line, orig.start_col) then
      -- Edits overlap, cannot combine
      return nil
    end
    
    -- Add base text from current position to start of this edit
    local base_text = get_base_text(current_line, current_col, orig.start_line, orig.start_col)
    result_text = result_text .. base_text
    
    -- Add the replacement text from the input
    local replacement = get_input_text(edit.input, modif)
    result_text = result_text .. replacement
    
    -- Update current position to end of this edit's original range
    current_line = orig.end_line
    current_col = orig.end_col
  end
  
  -- Add remaining base text after last edit
  local ends_line_after = base_range.end_line <= #base_lines
  local end_line, end_col
  if ends_line_after then
    end_line = base_range.end_line
    end_col = 1
  else
    end_line = base_range.end_line - 1
    end_col = #(base_lines[end_line] or "") + 1
  end
  
  local remaining = get_base_text(current_line, current_col, end_line, end_col)
  result_text = result_text .. remaining
  
  -- Split result into lines
  local result_lines = {}
  for line in (result_text .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(result_lines, line)
  end
  
  -- Trim leading/trailing based on whether we started before/ended after
  if starts_line_before and #result_lines > 0 then
    if result_lines[1] ~= "" then
      return nil  -- First line should be empty if we started before
    end
    table.remove(result_lines, 1)
  end
  if ends_line_after and #result_lines > 0 then
    if result_lines[#result_lines] ~= "" then
      return nil  -- Last line should be empty if we end after
    end
    table.remove(result_lines)
  end
  
  return result_lines
end

--- Dumb combine: just concatenate input1 then input2 (fallback)
--- @param input1_lines table
--- @param input2_lines table
--- @param first_input number 1 or 2
--- @return table Combined lines
local function dumb_combine_inputs(input1_lines, input2_lines, first_input)
  local combined = {}
  local first_lines = (first_input == 1) and input1_lines or input2_lines
  local second_lines = (first_input == 1) and input2_lines or input1_lines
  
  for _, line in ipairs(first_lines) do
    table.insert(combined, line)
  end
  for _, line in ipairs(second_lines) do
    table.insert(combined, line)
  end
  
  return combined
end

--- Accept both sides (smart combination like VSCode) for the conflict under cursor
--- @param tabpage number
--- @return boolean success
function M.accept_both(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session then
    vim.notify("[codediff] No active session", vim.log.levels.WARN)
    return false
  end

  if not session.conflict_blocks or #session.conflict_blocks == 0 then
    vim.notify("[codediff] No conflicts in this session", vim.log.levels.WARN)
    return false
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local side = nil

  if current_buf == session.original_bufnr then
    side = "left"
  elseif current_buf == session.modified_bufnr then
    side = "right"
  else
    vim.notify("[codediff] Cursor not in diff buffer", vim.log.levels.WARN)
    return false
  end

  local block = tracking.find_conflict_at_cursor(session, cursor_line, side, false)
  if not block then
    vim.notify("[codediff] No active conflict at cursor position", vim.log.levels.INFO)
    return false
  end

  -- Get both contents
  local incoming_lines = tracking.get_lines_for_range(session.original_bufnr, block.output1_range.start_line, block.output1_range.end_line)
  local current_lines = tracking.get_lines_for_range(session.modified_bufnr, block.output2_range.start_line, block.output2_range.end_line)
  
  local result_bufnr = session.result_bufnr
  local base_lines = session.result_base_lines
  if not result_bufnr or not base_lines then
    vim.notify("[codediff] No result buffer or base lines", vim.log.levels.ERROR)
    return false
  end

  -- Try smart combination first (like VSCode's "Accept Combination")
  local combined = smart_combine_inputs(block, base_lines, incoming_lines, current_lines, 1)
  
  if not combined then
    -- Fallback to dumb combination (concatenate)
    combined = dumb_combine_inputs(block, incoming_lines, current_lines, 1)
  end

  apply_to_result(result_bufnr, block, combined, base_lines)
  signs.refresh_all_conflict_signs(session)
  auto_refresh.refresh_result_now(result_bufnr)
  return true
end

--- Discard both sides (reset to base) for the conflict under cursor
--- @param tabpage number
--- @return boolean success
function M.discard(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session then
    vim.notify("[codediff] No active session", vim.log.levels.WARN)
    return false
  end

  if not session.conflict_blocks or #session.conflict_blocks == 0 then
    vim.notify("[codediff] No conflicts in this session", vim.log.levels.WARN)
    return false
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local side = nil

  if current_buf == session.original_bufnr then
    side = "left"
  elseif current_buf == session.modified_bufnr then
    side = "right"
  else
    vim.notify("[codediff] Cursor not in diff buffer", vim.log.levels.WARN)
    return false
  end

  local block = tracking.find_conflict_at_cursor(session, cursor_line, side, true) -- Allow resolved
  if not block then
    vim.notify("[codediff] No conflict at cursor position", vim.log.levels.INFO)
    return false
  end

  -- Get base content for this range
  local base_lines = session.result_base_lines
  if not base_lines then
    vim.notify("[codediff] No base lines available", vim.log.levels.ERROR)
    return false
  end

  local base_content = {}
  for i = block.base_range.start_line, block.base_range.end_line - 1 do
    table.insert(base_content, base_lines[i] or "")
  end

  local result_bufnr = session.result_bufnr
  if not result_bufnr then
    vim.notify("[codediff] No result buffer", vim.log.levels.ERROR)
    return false
  end

  apply_to_result(result_bufnr, block, base_content, base_lines)
  signs.refresh_all_conflict_signs(session)
  auto_refresh.refresh_result_now(result_bufnr)
  return true
end

return M
