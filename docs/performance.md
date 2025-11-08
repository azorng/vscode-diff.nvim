# Performance & Timeout Control

This plugin provides high-quality character-level diff highlighting similar to VSCode. To ensure fast response times even with large files, it includes an intelligent timeout mechanism that automatically balances speed and detail.

## How It Works

### Two-Phase Diff Computation

The diff algorithm works in two phases:

1. **Line-level diff** (~30% of time)
   - Fast comparison of entire lines
   - Always completes quickly
   - Produces the basic line-by-line change structure

2. **Character-level refinement** (~70% of time)
   - Detailed analysis within each changed line
   - Highlights specific character changes (like VSCode)
   - This is where timeout control matters

### Intelligent Timeout

The timeout applies to the **entire diff computation**. When a timeout occurs:

- Line-level diff always completes (it's fast)
- Character refinement runs as long as time allows
- Slow regions automatically fall back to line-level highlighting
- Fast regions get full character detail

**Result**: You get the best quality possible within your time budget.

## Why This Matters

### The Problem

Some code changes are expensive to analyze at the character level:
- Large blocks of inserted/deleted code (hundreds of lines)
- Highly complex refactorings with minimal common content
- Files with very long lines

These cases can take 1-2 seconds for character analysis, while most changes complete in milliseconds.

### The Solution

With timeout control:
- **99% of changes** get full character highlighting (fast cases)
- **1% of changes** fall back to line-level highlighting (slow cases)
- **Total time** stays predictable and fast

## Performance Comparison

Typical large file diff (1150 → 2352 lines):

| Timeout | Time | Character Detail | vs Git |
|---------|------|------------------|--------|
| 5000ms (default) | 1.2s | 100% | 12x slower, full detail |
| 1000ms (fast) | 0.6s | 99% | 6x slower, nearly full |
| 100ms (ultra-fast) | 0.2s | ~20% | 2x slower, some detail |
| Git diff | 0.1s | 0% | Baseline |

**Recommended: 1000ms** - 2× faster with 99% quality retained.

## Configuration

### Default (Quality Priority)

```lua
require("vscode-diff").setup({
  diff = {
    max_computation_time_ms = 5000,  -- 5 seconds (VSCode default)
  }
})
```

**Use when**: You want maximum detail and don't mind occasional 1-2 second waits on huge diffs.

### Fast Mode (Speed Priority)

```lua
require("vscode-diff").setup({
  diff = {
    max_computation_time_ms = 1000,  -- 1 second
  }
})
```

**Use when**: You want fast response times with minimal quality loss (99% detail retained).

**Recommended for**: Most users, especially those with large codebases.

### Ultra-Fast Mode (Git-Like Speed)

```lua
require("vscode-diff").setup({
  diff = {
    max_computation_time_ms = 100,  -- 100ms
  }
})
```

**Use when**: You work with extremely large files and prefer speed over character detail.

**Result**: Similar to Git diff but still better (some character highlighting on fast regions).



## Key Benefits

### 1. Never Worse Than Git Diff

Even at the shortest timeout (100ms), you get:
- ✓ All line-level changes (same as Git)
- ✓ Some character-level detail (bonus)
- ✓ Only 2× slower than Git

### 2. Automatic Optimization

The timeout **naturally filters out expensive operations**:
- Small changes complete instantly (< 50ms)
- Normal changes complete quickly (< 200ms)
- Pathological cases hit timeout and fall back gracefully

No manual configuration needed - it just works.

### 3. Predictable Performance

You set the maximum wait time, and the plugin respects it:
- 1000ms timeout → guaranteed response in ~1 second
- No surprises, no hangs

### 4. Best-Effort Quality

The plugin always tries to give you full detail but gracefully degrades when time runs out:
- Most regions: full character highlighting ✓
- Slow regions: line-level highlighting (still useful)
- Never fails, never hangs

## When to Adjust Timeout

### Increase Timeout (→ 5000ms or higher) if:
- You rarely diff large files
- You want maximum detail even on complex changes
- You don't mind occasional 1-2 second waits

### Decrease Timeout (→ 1000ms or lower) if:
- You frequently diff large files
- You prioritize speed over perfection
- You're on a slower machine

### Keep Default (5000ms) if:
- You want VSCode-like behavior
- Balanced approach works for you

## Technical Details

### What Gets Optimized

The timeout primarily affects **character-level refinement**:
- Massive code insertions/deletions (15+ KB)
- Highly divergent line changes
- Files with very long lines (1000+ chars)

### What Stays Fast

These operations complete quickly regardless of timeout:
- Line-level diff (always fast)
- Small character changes (complete in milliseconds)
- Similar line changes (low algorithmic complexity)



## Recommendations

**For most users**:
```lua
max_computation_time_ms = 1000  -- Fast, 99% quality
```

**For power users with large files**:
```lua
max_computation_time_ms = 500  -- Very fast, 95% quality
```

**For detail-oriented users**:
```lua
max_computation_time_ms = 5000  -- Default, 100% quality
```

## Summary

The timeout mechanism ensures your diff view is **always responsive** while providing **the best quality possible** within your time budget. It's a smart trade-off that:

- Keeps fast cases fast (no overhead)
- Makes slow cases acceptable (graceful degradation)
- Never makes things worse (always better than Git diff)
- Gives you control (one simple parameter)

This design means you get **VSCode-quality diffs** with **predictable performance** - the best of both worlds.
