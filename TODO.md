# TODO

Design changes and known bugs, surfaced while building and live-testing tutor
mode (2026-08-09). Ordered roughly by how much they hurt in practice.

## Bugs

### 1. Trigger routing: any Vim can claim any patch

`~/.claude/vim-diff` is user-global and *every* Vim with the plugin loaded polls
it once a second. `s:check_trigger()` claims by deleting the file, so whichever
timer fires first wins — regardless of repo, cwd, or which Claude session the
patch belongs to. Hit live: a 37-day-old Vim swallowed a patch meant for the
active session, silently, with no error anywhere.

`g:claude_code_diff_match_repo_root = 1` narrows this to the Vim's own repo but
does not solve it — two Vims in the same tree still race. The trigger filename
already carries the Claude `session_id`; pinning a Vim to the session whose
terminal it hosts (via `terminal_bridge#get_buf()`) would make routing exact.

### 2. `apply_edited()` / `accept()` do not create parent directories

`writefile()` fails with `E482: Can't create file` when the target's directory
does not exist. Claude's own `Write` creates parents, so this only bites in
tutor mode where Vim performs the write. Fix: `mkdir(fnamemodify(target, ':h'), 'p')`
before both `writefile()` calls. Needs a Vader case for a target in a
not-yet-existing directory.

### 3. Tutor mode leaks its temp files

The `--no-wait` branch in `vim-preview-diff.py` returns before the cleanup loop
that deletes `orig` / `proposed` / `trigger`. Blocking mode cleans up after its
wait; tutor mode never does, so `~/.claude/vim-diff` grows without bound. The
hourly sweeper in `vim-close-diff.py` only catches files older than an hour, and
only when that hook runs at all.

### 4. Duplicate `PostToolUse` entries accumulate on every install

`install_hooks()` de-dupes both hook lists with the marker `'vim-preview-diff'`,
but the PostToolUse command is `vim-close-diff.py`, which does not contain that
string. Every install appends another Post entry and removes none. Same marker
mismatch makes `uninstall_hooks()` leave Post entries behind. The Vader tests
assert only on `PreToolUse`, which is why this was missed.

### 5. `s:check_trigger()` swallows errors from `show()`

The `try` wraps the whole claim-and-show sequence, and the `catch` reports
`failed to parse diff trigger` for *any* exception — including ones thrown well
after parsing succeeded. The trigger is already deleted by then, so there is no
retry and no accurate diagnosis. Narrow the `try` to `json_decode`, or report
the two failure modes distinctly.

## Design changes

### 6 & 7 — DROPPED (2026-08-13). Vim already does this: `gt` / `gT`

Both items existed to get the review UI and the Claude terminal in front of the
user at the same time. Switching tab pages with `gt`/`gT` covers it with no code
at all, so neither the layout change nor the config toggle is worth carrying.
The terminal already announces that a patch is waiting, which is the only cue
item 7 was going to provide.

Kept below only as a record of what was considered, in case the tab-switching
workflow ever proves insufficient.

### ~~6. Diff layout: config-toggle to keep the Claude terminal visible~~

`show()` does `tabnew` + `rightbelow vsplit`, so the review UI takes over a new
tab page and the terminal disappears. Two options considered:

- **A — splits in the current tab.** More invasive: `close()` (`tabclose` plus
  index arithmetic), `is_open()` (`s:diff_tab`), the `windo setlocal …` line
  (would clobber the terminal and any other window in the tab) and `wincmd =`
  all assume the diff owns its tab. Layout gets cramped at three columns.
- **B — show the terminal buffer inside the diff tab.** A terminal buffer can
  be displayed in several windows at once, so `botright vertical sbuffer <bufnr>`
  after the diff windows are built gives patch + live terminal together for
  roughly three lines, with `close()`/`is_open()` untouched. Must be added
  *after* `windo` and `wincmd =` so those do not apply to it.

Preferred: B. Open question: apply to preview mode too, or gate on `s:no_wait`?
In preview mode Claude is blocked, so the visible terminal shows a frozen prompt.
Kevin: Do not apply in preview mode, it is useless, since the terminal if frozen.

### 7. Make an arriving diff visible

Triggers are claimed from a timer callback. When the user is in Terminal-Job
mode the new tab page is created without the view moving to it, so a patch can
open and go unnoticed. Consider a `redraw`, or explicitly surfacing the tab.

## Tests

### 8. Side-effecting paths are under-covered

Every bug above lives in the real-filesystem / real-Vim / real-hook round trip.
The Vader suite covers pure logic (`prompt_start`, install flag plumbing) well
and side effects poorly — its install tests always `mkdir` their own target, so
bug 2 was unreachable. Wanted: cases for a missing parent directory, repeated
installs (asserting `PostToolUse` length), and cleanup after a `--no-wait` run.

## Docs

### 9. Documentation for tutor mode

- `doc/claude_code.txt` — `:Claude tutor` subcommands, `ga`/`gm`/`gr` semantics
  in non-blocking mode, the new `tutoring` provenance category.
- `README.md` — tutor mode section; note that `preview` and `tutor` share one
  hook slot, so installing one replaces the other.
- `doc/AGENT_INSTRUCTIONS.md` — the deny-is-expected protocol, so agents do not
  retry the write or route around it.
- `CHANGELOG.md` — the tutor mode entry.
