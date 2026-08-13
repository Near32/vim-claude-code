# Vim-Claude-Code Agent Instructions

This document provides context and rules for AI agents (like Antigravity) working on the `vim-claude-code` project. Please review these instructions before making any architectural or codebase changes.

## 1. Core Technology Stack
- **Language**: Written strictly in **Legacy Vimscript (Vim 8+)**. Do *not* use Vim9 script syntax.
- **Dependencies**: The plugin relies on the `+terminal` feature built into Vim 8+. Do not introduce external UI frameworks, browser APIs, or Neovim-only features (e.g., Lua APIs or Neovim floating windows), as native Vim 8 compatibility is the primary goal.
- **External CLI**: Interacts with the Anthropic `claude` CLI. Assume it is available in the user's `$PATH`.

## 2. Architecture & File Structure
The project follows a standard, clean Vim plugin structure utilizing the `autoload` pattern for lazy loading:

- **`plugin/claude_code.vim`**: This is the entry point. Keep it minimal. It should solely define the global `:Claude` command (which acts as a dispatcher) and the default keymaps.
- **`autoload/claude_code/`**: All core logic lives here, split into modular files:
  - `commands.vim`, `git_commands.vim`, `arch_commands.vim`, `workflow_commands.vim`, `meta_commands.vim`: Handlers for various `:Claude <subcommand>` invocations.
  - `terminal.vim`, `terminal_bridge.vim`: Manage the Vim `+terminal` lifecycle, window splits, and sending prompts to the Claude CLI.
  - `config.vim`: Defines defaults and getters/setters for configuration variables.
  - `util.vim`: Shared helpers for text selection, context extraction, and error handling.
- **`test/`**: Uses the Vader test framework (`test_dispatch.vader`). Always add or update tests here when modifying command dispatching or core utility logic.

## 3. Coding Conventions

### Command Dispatching
- The plugin exposes a **single unified command**: `:Claude <subcommand>`.
- Never create new top-level commands (e.g., do not create `:ClaudeExplain`). Instead, add an `explain` subcommand to the dispatcher in `plugin/claude_code.vim` and route it to an autoload function like `claude_code#commands#explain()`.

### Variables & Configuration
- **Global Config**: Prefix all global configuration variables with `g:claude_code_` (e.g., `g:claude_code_position`).
- **Buffer Overrides**: Respect buffer-local overrides prefixed with `b:claude_code_`. The code should check `b:` before falling back to `g:`.
- **Internal Variables**: Prefix script-local variables with `s:` and plugin-internal global state variables carefully to avoid polluting the global namespace.

### Keymaps
- The default extended keymap prefix is `<Leader>c`.
- Provide `<Plug>` mappings for all actions so users can easily remap them without conflicts.
- Always check config flags (like `g:claude_code_map_keys` and `g:claude_code_map_extended_keys`) before mapping keys.

## 4. Workflows & Features
- **Health Checks**: If adding a new system dependency or configuration requirement, update the `:Claude doctor` subcommand logic (usually in `meta_commands.vim`) so the tool can self-diagnose user issues.
- **Context Awareness**: Commands should be aware of both normal mode (acting on the whole file or current function) and visual mode (acting on the user's text selection).

## 5. The Diff Hooks — Two Protocols

`bin/vim-preview-diff.py` is a `PreToolUse` hook registered by `:Claude preview install` or `:Claude tutor install`. Both write to the same slot in `.claude/settings.local.json`, so only one is ever active. It intercepts `Edit|Write|MultiEdit`, computes the proposed content, and drops a trigger in the user-global `~/.claude/vim-diff/`, which every Vim polls once a second.

The two modes differ in *who owns the write*, and that difference drives most of the non-obvious code:

| | preview (default) | tutor (`--no-wait`) |
|---|---|---|
| Hook behaviour | blocks up to 570s awaiting a decision file | answers `deny` and exits immediately |
| Who writes the file | Claude, after `allow` | Vim, in `apply_edited()` / `accept()` |
| Temp file cleanup | the hook, after its wait loop | Vim, in `close()` |
| How Vim replies | writes the decision file | types into the terminal via `terminal_bridge#send()` |

**If you are an agent whose edit was denied with a tutor-mode message: that is not an error.** The patch is open in the user's Vim for review. Do not retry the edit, and do not route around it with `bash`, `cat > file`, or a second tool call. Say the patch is open, then stop. The user may ask questions while it sits open; Vim reports back what they applied, including a diff of any edits they made to your proposal.

### Invariants worth preserving

- **Never delete a trigger you are not claiming.** `s:check_trigger()` uses delete-on-claim as its lock, and skips triggers belonging to another Vim (`vim_pid`) with `continue`. Deleting there loses the patch entirely.
- **Never delete an unparseable trigger.** The hook writes the JSON non-atomically; a half-written file parses as garbage for an instant and recovers on the next poll.
- **Cleanup follows the last reader.** `record_provenance()` and `build_patch()` read `s:proposed_file`, and both run *before* `close()`. The `user-edits-*.diff` files are read by Claude after `close()`, so they can only be swept by age — done in the `PreToolUse` hook, since `PostToolUse` never fires after a `deny`.
- **`show()` calls `close()` first**, so at that moment the script-local state still describes the *previous* trigger. Anything you add that touches that state must account for it.


