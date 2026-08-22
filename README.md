# vim-claude-code

[![CI](https://github.com/rishi-opensource/vim-claude-code/actions/workflows/ci.yml/badge.svg)](https://github.com/rishi-opensource/vim-claude-code/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-1.4.1-blue.svg)](CHANGELOG.md)

**AI-powered coding, inside Vim. No context switching.**

`vim-claude-code` brings [Claude Code](https://docs.anthropic.com/en/docs/claude-code) directly into your editor. Fix bugs, write tests, review diffs, generate commits, and refactor code — all without leaving Vim.

One keypress opens Claude in a split panel. Another hides it. Your session persists across toggles. Claude edits your files; your buffers reload automatically. You stay in flow.

## Why vim-claude-code?

Most AI coding tools pull you out of your editor — into a browser, a chat window, or a separate terminal. `vim-claude-code` keeps everything inside Vim:

- **No copy-pasting** — commands automatically capture your visual selection or current function
- **No tab switching** — Claude runs in a managed split, toggled with a single key
- **No blind edits** — every file change Claude proposes shows up as a reviewable diff before anything is written to disk
- **No workflow interruption** — buffers reload automatically when Claude modifies files

## Demos

![vim-claude-code highlight reel](assets/00-highlight-reel.gif)

> Toggle, fix bugs, generate tests, explain code, git workflows, diff preview, terminal zoom, and more — all from within Vim.
> See [DEMO.md](doc/DEMO.md) for individual feature walkthroughs.

## Features at a Glance

### Stay in Flow
- **One-key toggle** — `<C-\>` opens and hides Claude. Session persists across toggles.
- **Terminal Zoom** — Maximize Claude to full-screen with `<C-w>z`, tmux-style. Restore your split instantly.
- **Auto file refresh** — Buffers reload when Claude edits your files. No manual `:e` needed.
- **Multiple layouts** — Right split (default), bottom, top, left, floating popup, or dedicated tab.

### Context-Aware Commands
- **Selection-aware** — Commands use your visual selection when active, otherwise detect the current function automatically.
- **22 sub-commands** — Explain, fix, refactor, test, document, commit, review, rename, optimize, debug, and more. All tab-completable.
- **Git-aware** — Claude starts at your repo root. Separate sessions per repository.

### Review Before Claude Writes
- **Diff preview** — Every file edit Claude proposes opens a side-by-side diff tab. Review what changes, then accept or reject. You stay in control.

### Full Git Workflow
- **Commit messages** — Generated from your staged diff, with conventional commit support.
- **Code review** — Claude reviews your current diff with configurable strictness and security checks.
- **PR descriptions** — Generated from your branch changes without leaving the editor.

## Requirements

- Vim 8+ compiled with `+terminal`
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and in `$PATH`
- Optional: `+popupwin` for floating window mode
- Optional: `python3` for diff preview (`:Claude preview`)
  - Note: In Windows, there is a default python3 that redirects to the Windows Store.
    Run `Claude doctor` to check if you have a valid python3 installation.
    If you have Python 3, but your installation uses python.exe as the executable, create a python3 symlink.

## Installation

> **Stable release — v1.4.1**
> Pin to the latest stable release using the examples below, or omit the tag to always track `main`.

### [vim-plug](https://github.com/junegunn/vim-plug)
```vim
" Always track latest
Plug 'rishi-opensource/vim-claude-code'

" Pin to stable release
Plug 'rishi-opensource/vim-claude-code', { 'tag': 'v1.4.1' }
```

### [Vundle](https://github.com/VundleVim/Vundle.vim)
```vim
Plugin 'rishi-opensource/vim-claude-code'
```
> Vundle does not support tag pinning. To pin manually after install:
> ```sh
> cd ~/.vim/bundle/vim-claude-code && git checkout v1.4.1
> ```

### [pathogen](https://github.com/tpope/vim-pathogen)
```sh
git clone --branch v1.4.1 https://github.com/rishi-opensource/vim-claude-code.git ~/.vim/bundle/vim-claude-code
```

### Native packages (Vim 8+)
```sh
mkdir -p ~/.vim/pack/plugins/start
git clone --branch v1.4.1 https://github.com/rishi-opensource/vim-claude-code.git ~/.vim/pack/plugins/start/vim-claude-code
```

## Quick Start

**1. Open Claude:**
```vim
:Claude
" or press <C-\>
```

**2. Run a health check:**
```vim
:Claude doctor
```
This reports `[OK]` / `[FAIL]` for every dependency and tells you exactly what to fix.

**3. Explore commands with tab completion:**
```vim
:Claude <Tab>
```

The Claude session persists — toggling with `<C-\>` hides and restores the same session.

## Commands

### Terminal

*Open, hide, and manage the Claude terminal session.*

| Command | Description |
|---|---|
| `:Claude` | Toggle the Claude Code terminal |
| `:Claude continue` | Toggle with `--continue` (resume last conversation) |
| `:Claude resume` | Toggle with `--resume` (interactive conversation picker) |
| `:Claude verbose` | Toggle with `--verbose` (detailed logging) |

### Code Intelligence

*Commands work on your visual selection when active, or auto-detect the current function.*

| Command | Flags | Description |
|---|---|---|
| `:Claude explain` | `--brief`, `--detailed` | Explain selected code or current function |
| `:Claude fix` | `--apply`, `--safe` | Fix bugs and correctness issues |
| `:Claude refactor` | `--extract`, `--simplify`, `--optimize`, `--rename` | Refactor code |
| `:Claude test` | `--framework {name}`, `--edge-cases` | Generate unit tests |
| `:Claude doc` | `--inline`, `--markdown` | Generate documentation |

### Git Workflow

*From staged diff to commit message to PR description — without opening a browser.*

| Command | Flags | Description |
|---|---|---|
| `:Claude commit` | `--conventional`, `--amend` | Generate commit message from staged diff |
| `:Claude review` | `--strict`, `--security` | Code review on current diff |
| `:Claude pr` | | Generate PR description |

### Architecture & Planning

*Think through larger problems with Claude before writing code.*

| Command | Description |
|---|---|
| `:Claude plan` | Generate an implementation plan for the current file |
| `:Claude analyze` | Analyze for complexity, performance, and security issues |

### Workflow Utilities

*Direct in-editor actions — apply suggestions, debug errors, rename symbols, or zoom the terminal.*

| Command | Description |
|---|---|
| `:Claude rename` | Suggest better variable/function names |
| `:Claude optimize` | Optimize code for performance |
| `:Claude debug` | Analyze the error on the current line |
| `:Claude apply` | Apply Claude's last suggestion to the file (prompts for confirmation) |
| `:Claude zoom` | Toggle full-screen (zoom) mode for the Claude terminal |

### Meta

| Command | Description |
|---|---|
| `:Claude chat` | Send a free-form message with current file context |
| `:Claude context` | Preview what context will be sent to Claude |
| `:Claude model [name]` | Switch model (`sonnet`, `opus`, `haiku`) |

### Utility

| Command | Description |
|---|---|
| `:Claude version` | Show plugin version, Vim version, Claude CLI version, and terminal support |
| `:Claude doctor` | Health check: verifies Claude CLI, Git, terminal support, and Vim version |

## Reviewing Claude's Edits — Diff Preview

![diff preview demo](assets/16-diff-preview.gif)

When Claude proposes changes to a file, a **side-by-side diff tab opens automatically** before anything is written to disk:

```
  [current file]    │    [proposed changes]
```

Review exactly what Claude wants to change, then use these keys in the diff tab:

| Key | Action |
|---|---|
| `ga` | Accept — send `y` to Claude, apply the change |
| `gr` | Reject — send `n` to Claude, discard the change |
| `q` | Close the diff tab without responding |

**Enable diff preview for your project:**
```vim
:Claude preview install
```

This registers Claude Code hooks in `.claude/settings.local.json`. To auto-enable on every Vim startup:
```vim
let g:claude_code_diff_preview = 1
```

**Multiple repos, one shared trigger directory:** all Vim instances poll the same
`~/.claude/vim-diff` directory. By default (`g:claude_code_diff_match_repo_root = 0`),
any idle Vim claims the next trigger regardless of which repo it's for — the right
choice if you only ever have one Vim open at a time, since it also means a Vim opened
in one repo will still catch edits to files elsewhere (e.g. dotfiles, a plugin
you're also iterating on). If you routinely run several Vim sessions across
different repos at once and want each to only handle its own repo's edits, opt in:
```vim
let g:claude_code_diff_match_repo_root = 1
```

**Diff preview commands:**

| Command | Description |
|---|---|
| `:Claude preview install` | Register diff preview hooks in `.claude/settings.local.json` |
| `:Claude preview uninstall` | Remove diff preview hooks |
| `:Claude preview close` | Manually close an open diff tab |
| `:Claude preview status` | Show diff preview status and dependency checks |

Requires `python3`. Uses Vim `+clientserver` for instant diffs when available, falls back to polling.

## Learn Instead of Delegating — Tutor Mode

```vim
:Claude tutor install
```

Claude stops implementing and starts teaching. It lists the concepts a feature actually requires, you write questions into the patch, it answers them, sets exercises, marks your answers — and when you say you're ready, it hands back scaffolding with the gaps left for you to fill.

The whole conversation happens **through the patch**. Claude proposes, you edit its proposal to reply, and your edits come back as a diff it reads. The tracking file lives at `AI_POLICY/tutoring/LEARNING.md` — one per repository, append-only, so the repo keeps a record of what was learned while working on it.

**The terminal stays live.** Unlike diff preview, the tutor hook does not block: Claude's turn ends as soon as the patch opens, so you can ask follow-up questions or request hints while you work on it. The review UI opens in its own tab page — `gt` / `gT` to switch back and forth.

| Command | Description |
|---|---|
| `:Claude tutor install` | Register the tutor hook and link the tutor skill |
| `:Claude tutor uninstall` | Remove the hooks and stop polling |
| `:Claude tutor close` | Manually close an open diff tab |
| `:Claude tutor status` | Show status and dependency checks |

> **Note:** tutor and preview share one hook slot — installing either replaces the other.

In the diff tab, `gm` is the one to remember: it applies *your* edited version and sends Claude a diff of what you changed. That is how you ask questions and submit answers. `ga` accepts unmodified, `gr` rejects, `q` dismisses silently. Edits applied this way are recorded under `AI_POLICY/provenance/` with the category `tutoring`.

### v2 (default) — pre-generated curriculum

`:Claude tutor install` links `skills/tutor-v2` by default. Instead of teaching one concept at a time as you go, v2 builds the whole curriculum for a feature up front, before you read a single line of it:

1. **A workflow-shaped dependency graph** — a mermaid DAG whose nodes are things you can *do* ("push a repo public with CI wired up"), not bare topics, with prerequisite and enabling edges between them.
2. **A probe** — `AskUserQuestion` calibrates you against the DAG (already-done / partial / not-started, plus today's bandwidth) before anything is written.
3. **Parallel curriculum generation** — one subagent per DAG node drafts its teaching content, an exercise, and a cheatsheet, then a global critique and verification pass checks every exercise traces back to something actually taught (and vice versa) before any of it is shown to you.
4. **Delivery** — the already-verified content lands as the same patch-review round trip described above, one node at a time.

The design is inspired by [Eero Alvar's "How I Use AI to Learn Things"](https://youtu.be/kzcI5F4tGiU) and its reference implementation, [Alvarmethod](https://github.com/vasanthsreeram/Alvarmethod) — this README only summarizes the mechanics that actually ship here; see `skills/tutor-v2/SKILL.md` in this repo for the full, authoritative workflow (phases, file layout, the `.scratch/` drafting mechanism, and the rules an agent follows).

**Falling back to v1** — the original, reactive, single-file teaching loop is still fully present and selectable:
```vim
let g:claude_code_tutor_version = 'v1'
```
Set this before `:Claude tutor install` (or `:Claude tutor uninstall` then reinstall if tutor mode is already active) to link the original `skills/tutor` skill instead.

## Full-Screen Focus — Terminal Zoom

![zoom demo](assets/17-terminal-zoom.gif)

Working through a complex problem? Press `<C-w>z` inside the Claude terminal to **maximize it full-screen** — just like tmux's zoom. Press again to restore your split layout.

This is especially useful when Claude is generating a long response and you want to read it without distractions.

```vim
" Customize the zoom key
let g:claude_code_map_zoom = '<C-w>z'
```

## Keymaps

### Default keymaps

| Mode | Key | Action |
|---|---|---|
| Normal | `<C-\>` | Toggle Claude Code terminal |
| Normal | `<Leader>cC` | Toggle with `--continue` |
| Normal | `<Leader>cV` | Toggle with `--verbose` |
| Terminal | `<C-\>` | Hide Claude Code terminal |
| Terminal | `<C-w>z` | **Zoom Toggle**: Maximize or restore terminal |
| Terminal | `<C-v>` | **Paste**: Paste system clipboard content |
| Terminal | `<C-h/j/k/l>` | Navigate to adjacent window |

### Extended keymaps (`g:claude_code_map_extended_prefix` + key)

| Key | Command | Key | Command |
|---|---|---|---|
| `<Leader>ce` | explain | `<Leader>cG` | commit |
| `<Leader>cf` | fix | `<Leader>cR` | review |
| `<Leader>cr` | refactor | `<Leader>cp` | pr |
| `<Leader>ct` | test | `<Leader>cP` | plan |
| `<Leader>cd` | doc | `<Leader>ca` | analyze |
| `<Leader>cn` | rename | `<Leader>cD` | debug |
| `<Leader>co` | optimize | `<Leader>cA` | apply |
| `<Leader>cc` | chat | `<Leader>cx` | context |
| `<Leader>cm` | model | | |

Visual mode: `<Leader>c` + `e/f/r/t/d/n/o` operate on the selection.

To disable all default keymaps:
```vim
let g:claude_code_map_keys = 0
let g:claude_code_map_extended_keys = 0
```

## Window Layouts

Set `g:claude_code_position` to match your preferred workflow:

| Value | Layout |
|---|---|
| `'right'` | Vertical split on the right (default) |
| `'bottom'` | Horizontal split at the bottom |
| `'top'` | Horizontal split at the top |
| `'left'` | Vertical split on the left |
| `'float'` | Floating popup (requires `+popupwin`) |
| `'tab'` | Dedicated tab page |

```vim
" Bottom split at 30%
let g:claude_code_position   = 'bottom'
let g:claude_code_split_ratio = 0.3

" Floating popup
let g:claude_code_position    = 'float'
let g:claude_code_float_width  = 0.85
let g:claude_code_float_height = 0.85
let g:claude_code_float_border = 'double'
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `g:claude_code_command` | `'claude'` | CLI executable |
| `g:claude_code_position` | `'right'` | Window layout |
| `g:claude_code_split_ratio` | `0.4` | Terminal size (0.0–1.0) |
| `g:claude_code_enter_insert` | `1` | Auto-enter Terminal mode on focus |
| `g:claude_code_hide_numbers` | `1` | Hide line numbers in terminal |
| `g:claude_code_hide_signcolumn` | `1` | Hide sign column in terminal |
| `g:claude_code_use_git_root` | `1` | Start Claude at git root |
| `g:claude_code_multi_instance` | `1` | Separate session per git repo |
| `g:claude_code_map_keys` | `1` | Register default toggle keymaps |
| `g:claude_code_map_extended_keys` | `1` | Register `<Leader>c*` keymaps |
| `g:claude_code_map_toggle` | `'<C-\>'` | Toggle key |
| `g:claude_code_map_zoom` | `'<C-w>z'` | Zoom key |
| `g:claude_code_map_paste` | `'<C-v>'` | Paste key |
| `g:claude_code_map_continue` | `'<Leader>cC'` | Continue key |
| `g:claude_code_map_verbose` | `'<Leader>cV'` | Verbose key |
| `g:claude_code_map_extended_prefix` | `'<Leader>c'` | Prefix for all extended keymaps |
| `g:claude_code_refresh_enable` | `1` | Auto-reload changed buffers |
| `g:claude_code_refresh_interval` | `1000` | Polling interval (ms) |
| `g:claude_code_refresh_notify` | `1` | Notify on buffer reload |
| `g:claude_code_float_width` | `0.8` | Popup width fraction |
| `g:claude_code_float_height` | `0.8` | Popup height fraction |
| `g:claude_code_float_border` | `'rounded'` | Border style |
| `g:claude_code_model` | `''` | Claude model override |
| `g:claude_code_debug` | `0` | Enable debug logging to message area |
| `g:claude_code_diff_preview` | `0` | Auto-start diff preview polling on Vim startup |
| `g:claude_code_diff_match_repo_root` | `0` | Restrict this Vim to triggers under its own repo/cwd (for running several Vims at once) |
| `g:claude_code_tutor_version` | `'v2'` | Which tutor skill `:Claude tutor install` links — `'v2'` (pre-generated curriculum, default) or `'v1'` (original reactive teaching loop) |
| `g:claude_code_bracketed_paste` | `1` | Enable bracketed paste mode support |
| `g:claude_code_terminal_start_delay` | `300` | Delay (ms) before attaching to Claude terminal |

Buffer-local `b:claude_code_*` overrides take precedence over `g:` variables.

## Troubleshooting

**Run the health check first:**
```vim
:Claude doctor
```
This reports `[OK]` / `[FAIL]` for each dependency and tells you exactly what to fix.

---

**E117: Unknown function** — Run `:helptags ALL` then restart Vim. Ensure the plugin directory is on your `runtimepath`.

**Terminal does not open** — Verify `vim --version | grep +terminal`. The plugin requires Vim compiled with `+terminal`.

**Claude not found** — Ensure `claude` is in `$PATH`: `which claude`.

**File changes not detected** — Check `g:claude_code_refresh_enable` is `1` and that `autoread` is not globally disabled in your vimrc.

**Debug logging** — Enable verbose output to diagnose issues:
```vim
let g:claude_code_debug = 1
```
All internal events (dispatch, terminal launch, git calls, refresh) will be printed to the message area.

For full in-editor documentation, run `:help claude-code`.

## License

MIT — see [LICENSE](LICENSE).

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for full details. This project uses [semantic-release](https://github.com/semantic-release/semantic-release) for automated versioning. See [doc/RELEASING.md](doc/RELEASING.md) for details.
