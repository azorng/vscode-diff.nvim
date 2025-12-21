-- Backward compatibility shim
-- This file provides compatibility for code using the old 'vscode-diff.render' path
-- Now that we've renamed render/ to ui/, we redirect old requires to the new location

return require('vscode-diff.ui')
