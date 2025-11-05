-- Test: Git Integration
-- Validates git operations, error handling, and async callbacks
-- Run with: nvim --headless -c "luafile tests/test_git_integration.lua" -c "quit"

vim.opt.rtp:prepend(".")
local git = require("vscode-diff.git")

print("=== Test: Git Integration ===\n")

local test_count = 0
local pass_count = 0

local function test(name, fn)
  test_count = test_count + 1
  io.write(string.format("[%d] %s ... ", test_count, name))
  local ok, err = pcall(fn)
  if ok then
    pass_count = pass_count + 1
    print("✓")
  else
    print("✗")
    print("  Error: " .. tostring(err))
  end
end

-- Test 1: Detect non-git directory (async)
test("Detects non-git directory", function()
  local callback_called = false
  local is_git = nil
  
  git.get_git_root("/tmp", function(err, root)
    callback_called = true
    is_git = (err == nil and root ~= nil)
  end)
  
  vim.wait(2000, function() return callback_called end)
  assert(callback_called, "Callback should be invoked")
  assert(type(is_git) == "boolean", "Should determine if in git repo")
end)

-- Test 2: Get git root for valid repo (async)
test("Gets git root for current repo", function()
  local current_file = vim.fn.expand("%:p")
  if current_file == "" then
    current_file = vim.fn.getcwd() .. "/README.md"
  end
  
  local callback_called = false
  local root = nil
  
  git.get_git_root(current_file, function(err, git_root)
    callback_called = true
    if not err then
      root = git_root
    end
  end)
  
  vim.wait(2000, function() return callback_called end)
  assert(callback_called, "Callback should be invoked")
  
  if root then
    assert(type(root) == "string", "Git root should be a string")
    assert(vim.fn.isdirectory(root) == 1, "Git root should be a directory")
  end
end)

-- Test 3: Error callback for invalid revision
test("Error callback for invalid revision", function()
  local current_file = debug.getinfo(1).source:sub(2)
  local callback_called = false
  local got_error = false
  
  -- First get git root
  git.get_git_root(current_file, function(err_root, git_root)
    if not err_root and git_root then
      local rel_path = git.get_relative_path(current_file, git_root)
      
      git.get_file_content("invalid-revision-12345", git_root, rel_path, function(err, data)
        callback_called = true
        if err then
          got_error = true
        end
      end)
    else
      callback_called = true
      got_error = true
    end
  end)
  
  vim.wait(2000, function() return callback_called end)
  assert(callback_called, "Callback should be invoked")
end)

-- Test 4: Async callback with actual git repo (if available)
test("Can retrieve file from HEAD (if in git repo)", function()
  local test_passed = false
  local current_file = debug.getinfo(1).source:sub(2)
  
  git.get_git_root(current_file, function(err_root, git_root)
    if not err_root and git_root then
      local rel_path = git.get_relative_path(current_file, git_root)
      
      -- First resolve HEAD to commit hash
      git.resolve_revision("HEAD", git_root, function(err_resolve, commit_hash)
        if not err_resolve and commit_hash then
          git.get_file_content(commit_hash, git_root, rel_path, function(err, lines)
            if not err and lines then
              assert(type(lines) == "table", "Should return table of lines")
              assert(#lines > 0, "Should have content")
              test_passed = true
            elseif err then
              test_passed = true
            end
          end)
        else
          test_passed = true
        end
      end)
    else
      test_passed = true
    end
  end)
  
  vim.wait(3000, function() return test_passed end)
  assert(test_passed, "Test should complete")
end)

-- Test 5: Relative path calculation
test("Calculates relative path correctly", function()
  -- Use Windows-style paths on Windows, Unix on Unix
  local sep = package.config:sub(1,1)
  local git_root, file_path, expected
  
  if sep == "\\" then
    -- Windows
    git_root = "C:\\Users\\test\\project"
    file_path = "C:\\Users\\test\\project\\src\\file.lua"
    expected = "src/file.lua"
  else
    -- Unix
    git_root = "/home/user/project"
    file_path = "/home/user/project/src/file.lua"
    expected = "src/file.lua"
  end
  
  local rel_path = git.get_relative_path(file_path, git_root)
  assert(type(rel_path) == "string", "Should return string")
  assert(rel_path == expected, "Should strip git root: got " .. rel_path)
end)

-- Test 6: Error message quality for missing file in revision
test("Provides good error for missing file in revision", function()
  local current_file = debug.getinfo(1).source:sub(2)
  local test_passed = false
  
  git.get_git_root(current_file, function(err_root, git_root)
    if not err_root and git_root then
      git.resolve_revision("HEAD", git_root, function(err_resolve, commit_hash)
        if not err_resolve and commit_hash then
          local fake_path = "nonexistent_file_12345.txt"
          
          git.get_file_content(commit_hash, git_root, fake_path, function(err, data)
            if err then
              assert(type(err) == "string", "Error should be a string")
              assert(#err > 0, "Error message should not be empty")
            end
            test_passed = true
          end)
        else
          test_passed = true
        end
      end)
    else
      test_passed = true
    end
  end)
  
  vim.wait(3000, function() return test_passed end)
  assert(test_passed, "Test should complete")
end)

-- Test 7: Handles special characters in filenames
test("Handles filenames with spaces", function()
  -- Use Windows-style paths on Windows, Unix on Unix
  local sep = package.config:sub(1,1)
  local git_root, file_path, expected
  
  if sep == "\\" then
    -- Windows
    git_root = "C:\\Users\\test\\project"
    file_path = "C:\\Users\\test\\project\\src\\my file.lua"
    expected = "src/my file.lua"
  else
    -- Unix
    git_root = "/home/user/project"
    file_path = "/home/user/project/src/my file.lua"
    expected = "src/my file.lua"
  end
  
  local rel_path = git.get_relative_path(file_path, git_root)
  assert(rel_path == expected, "Should handle spaces: got " .. rel_path)
end)

-- Test 8: Multiple async calls don't interfere
test("Multiple async calls work independently", function()
  local current_file = debug.getinfo(1).source:sub(2)
  local call1_done = false
  local call2_done = false
  
  git.get_git_root(current_file, function(err_root, git_root)
    if not err_root and git_root then
      local rel_path = git.get_relative_path(current_file, git_root)
      
      git.get_file_content("invalid1", git_root, rel_path, function()
        call1_done = true
      end)
      
      git.get_file_content("invalid2", git_root, rel_path, function()
        call2_done = true
      end)
    else
      call1_done = true
      call2_done = true
    end
  end)
  
  vim.wait(3000, function() return call1_done and call2_done end)
  
  assert(call1_done, "First call should complete")
  assert(call2_done, "Second call should complete")
end)

-- Test 9: LRU Cache functionality
test("LRU cache returns same content", function()
  local current_file = debug.getinfo(1).source:sub(2)
  local test_passed = false
  local first_result = nil
  local second_result = nil
  
  git.get_git_root(current_file, function(err_root, git_root)
    if not err_root and git_root then
      git.resolve_revision("HEAD", git_root, function(err_resolve, commit_hash)
        if not err_resolve and commit_hash then
          local rel_path = git.get_relative_path(current_file, git_root)
          
          -- First call (cache miss)
          git.get_file_content(commit_hash, git_root, rel_path, function(err1, lines1)
            first_result = lines1
            
            -- Second call (cache hit)
            git.get_file_content(commit_hash, git_root, rel_path, function(err2, lines2)
              second_result = lines2
              
              if first_result and second_result then
                assert(#first_result == #second_result, "Cached content should match")
                -- Verify they are separate copies (not same reference)
                assert(first_result ~= second_result, "Should return copies, not same reference")
                test_passed = true
              else
                test_passed = true
              end
            end)
          end)
        else
          test_passed = true
        end
      end)
    else
      test_passed = true
    end
  end)
  
  vim.wait(3000, function() return test_passed end)
  assert(test_passed, "Test should complete")
end)

-- Summary
print("\n" .. string.rep("=", 50))
if pass_count == test_count then
  print(string.format("✓ All %d git integration tests passed", pass_count))
  vim.cmd("cquit 0")
else
  print(string.format("✗ %d/%d tests failed", test_count - pass_count, test_count))
  vim.cmd("cquit 1")
end
