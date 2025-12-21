-- Render module facade
local M = {}

local highlights = require('vscode-diff.ui.highlights')
local view = require('vscode-diff.ui.view')
local core = require('vscode-diff.ui.core')
local lifecycle = require('vscode-diff.ui.lifecycle')

-- Public functions
M.setup_highlights = highlights.setup
M.create_diff_view = view.create
M.update_diff_view = view.update
M.render_diff = core.render_diff

-- Initialize lifecycle management
lifecycle.setup()

return M
