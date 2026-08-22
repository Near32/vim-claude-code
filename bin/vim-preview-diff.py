#!/usr/bin/env python3
"""
vim-preview-diff.py — PreToolUse hook for Claude Code
Intercepts Edit/Write/MultiEdit, computes the proposed file content, drops a
trigger in a user-global dir (~/.claude/vim-diff) that every Vim instance
polls, then BLOCKS until Vim writes back a decision file and answers the
permission request itself (allow/deny). Falls back to "ask" on timeout or if
no Vim picks it up — so it works with any Vim/Claude session arrangement.
"""
import sys
import json
import os
import time
import subprocess

GLOBAL_DIR = os.path.expanduser("~/.claude/vim-diff")
DECISION_TIMEOUT = 570  # hook entry sets timeout: 600

def apply_edit(content, old_string, new_string, replace_all=False):
    if not old_string:
        return content
    if replace_all:
        return content.replace(old_string, new_string)
    return content.replace(old_string, new_string, 1)

def has_clientserver():
    """Whether this `vim` binary was built with +clientserver at all -- without
    it, `--serverlist`/`--remote-expr` aren't recognized flags, so an empty
    server list means nothing about whether a Vim is actually running."""
    try:
        out = subprocess.check_output(["vim", "--version"],
                stderr=subprocess.DEVNULL).decode("utf-8")
        return "+clientserver" in out
    except Exception:
        return False

def running_vim_servers():
    try:
        return subprocess.check_output(["vim", "--serverlist"],
                stderr=subprocess.DEVNULL).decode("utf-8").split()
    except Exception:
        return []

def notify_all_vims(servers):
    for s in servers:
        try:
            subprocess.run(["vim", "--servername", s, "--remote-expr",
                    "claude_code#diff#handle_trigger()"],
                    stderr=subprocess.DEVNULL, timeout=5)
        except Exception:
            pass

def vim_ancestor_pid():
    """PID of the Vim hosting this Claude session, or None.

    Claude Code runs inside Vim's terminal, so that Vim is an ancestor of this
    hook process. Recording it lets the trigger be claimed by the Vim it
    actually belongs to, instead of whichever Vim's poll timer fires first —
    every Vim with the plugin loaded watches the same user-global directory.

    Uses `ps` rather than /proc so it works on macOS as well as Linux. Returns
    None when Claude runs outside Vim, which restores the previous
    first-come-first-served behaviour.
    """
    pid = os.getpid()
    for _ in range(12):  # ponytail: bounded walk, no cycle detection needed
        try:
            out = subprocess.check_output(["ps", "-o", "ppid=", "-p", str(pid)],
                    stderr=subprocess.DEVNULL).decode().strip()
            if not out or out == "0":
                return None
            pid = int(out)
            comm = subprocess.check_output(["ps", "-o", "comm=", "-p", str(pid)],
                    stderr=subprocess.DEVNULL).decode().strip()
        except Exception:
            return None
        if os.path.basename(comm) in ("vim", "gvim", "mvim", "vim.basic", "vim.gtk3"):
            return pid
    return None

def project_root(cwd):
    try:
        return subprocess.check_output(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        return cwd  # ponytail: not a git repo, treat cwd itself as the boundary

def sweep_stale(max_age=3600):
    """Remove leftovers older than an hour.

    vim-close-diff.py does this too, but it is a PostToolUse hook and tutor
    mode answers 'deny', so the tool never runs and that hook never fires.
    Age-based is the only option for the user-edits-*.diff files: their path is
    handed to Claude, which reads them after Vim has closed the diff, so no
    close-time cleanup can own them.
    """
    try:
        cutoff = time.time() - max_age
        for name in os.listdir(GLOBAL_DIR):
            p = os.path.join(GLOBAL_DIR, name)
            try:
                if os.path.getmtime(p) < cutoff:
                    os.remove(p)
            except OSError:
                pass
    except OSError:
        pass

def main():
    try:
        data = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    sweep_stale()

    no_wait = "--no-wait" in sys.argv
    tool_name = data.get("tool_name")
    if tool_name not in ("Edit", "Write", "MultiEdit"):
        sys.exit(0)

    servers = running_vim_servers()
    if has_clientserver() and not servers:
        # clientserver works on this vim and genuinely found nothing --
        # trust it, no Vim is running to pick this up.
        sys.exit(0)
    # No clientserver support: `servers` is always [] regardless of whether
    # a Vim is actually running, so fall through to the trigger-file/polling
    # path below (pre-dfe7ea6 behaviour) instead of skipping blind.

    cwd = data.get("cwd", os.getcwd())
    tool_input = data.get("tool_input", {})
    file_path = tool_input.get("file_path", "")
    if not file_path:
        sys.exit(0)

    # Never review: (a) anything outside the project entirely, (b) anything
    # under a .scratch/ directory inside it -- the same "tooling state, not
    # real content" convention as .git/.cache. Scratch dirs let subagents draft
    # durable, resumable, git-visible state without triggering patch review.
    abs_path = os.path.abspath(file_path)
    root = project_root(cwd)
    if not abs_path.startswith(root + os.sep) or "/.scratch/" in abs_path:
        sys.exit(0)

    os.makedirs(GLOBAL_DIR, exist_ok=True)
    # Per-session+call prefix so concurrent Claude sessions never collide
    sid = f'{data.get("session_id", "nosession")}-{os.getpid()}'
    prefix = os.path.join(GLOBAL_DIR, sid)
    orig_file = f"{prefix}-original"
    prop_file = f"{prefix}-proposed"
    trigger_file = f"{prefix}-trigger.json"
    decision_file = f"{prefix}-decision.json"

    try:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        content = ""

    with open(orig_file, "w", encoding="utf-8") as f:
        f.write(content)

    proposed = content
    if tool_name == "Edit":
        proposed = apply_edit(content, tool_input.get("old_string", ""),
                tool_input.get("new_string", ""), tool_input.get("replace_all", False))
    elif tool_name == "Write":
        proposed = tool_input.get("content", "")
    elif tool_name == "MultiEdit":
        for edit in tool_input.get("edits", []):
            old = edit.get("old_string", "")
            new = edit.get("new_string", "")
            proposed = new + proposed if not old else proposed.replace(old, new, 1)

    with open(prop_file, "w", encoding="utf-8") as f:
        f.write(proposed)

    # Heuristic category suggestion for the provenance prompt (PTAPP §7.2-7.4/8)
    def suggest_category(tool, orig, prop):
        import re
        words = lambda s: re.findall(r"[a-zA-Z]+", s.lower())
        if tool == "Write" or abs(len(prop) - len(orig)) > 400:
            return "8.1-8.2-OUT-OF-SCOPE? — large/new content, likely reject"
        old_w, new_w = words(orig), words(prop)
        if sorted(old_w) == sorted(new_w):
            return "7.2-correction — punctuation/format only, words unchanged"
        if len(set(old_w) ^ set(new_w)) <= 3:
            return "7.2-correction — small word-level fix"
        return "7.3.X-identified-issue — wording changed, ensure fix is your own (pick the specific 7.3.X)"

    display_name = file_path[len(cwd)+1:] if file_path.startswith(cwd) else file_path
    with open(trigger_file, "w", encoding="utf-8") as f:
        json.dump({
            "orig": orig_file,
            "proposed": prop_file,
            "display_name": display_name,
            "file_path": file_path,
            "cwd": cwd,
            "decision_file": decision_file,
            "transcript": data.get("transcript_path", ""),
            "suggested_category": suggest_category(tool_name, content, proposed),
            "no_wait": no_wait,
            # The Vim that hosts this Claude session, so only that Vim claims
            # this trigger. Absent/0 when Claude runs outside Vim.
            "vim_pid": vim_ancestor_pid() or 0,
        }, f)

    notify_all_vims(servers)

    # Tutor mode (--no-wait): don't block. Deny immediately and hand the write
    # to Vim, which applies the (edited) patch itself and messages the terminal
    # back. Claude's turn ends, so the user keeps the terminal for questions
    # while they edit the patch.
    if no_wait:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "Tutor mode: your patch for " + display_name + " is open in the user's "
                "Vim for review and editing. Do NOT retry this edit or write the file "
                "another way. Tell the user the patch is open, then stop and wait — they "
                "may ask you questions meanwhile, and Vim will report back what they "
                "applied."),
        }}))
        return

    # Block until a Vim writes the decision, then answer the permission
    # request directly — no keystroke injection, works from any terminal.
    decision = None
    deadline = time.time() + DECISION_TIMEOUT
    while time.time() < deadline:
        if os.path.exists(decision_file):
            try:
                with open(decision_file, "r", encoding="utf-8") as f:
                    decision = json.load(f)
            except Exception:
                pass
            break
        # ponytail: 0.2s poll; inotify if this ever measurably matters
        time.sleep(0.2)

    for p in (orig_file, prop_file, trigger_file, decision_file):
        try:
            os.remove(p)
        except OSError:
            pass

    if decision and decision.get("decision") in ("allow", "deny"):
        out = {
            "permissionDecision": decision["decision"],
            "permissionDecisionReason": decision.get("reason", "Decided in Vim diff preview."),
        }
    else:
        out = {
            "permissionDecision": "ask",
            "permissionDecisionReason": "Vim diff preview: no decision (timeout or dismissed) — please confirm here.",
        }
    out["hookEventName"] = "PreToolUse"
    print(json.dumps({"hookSpecificOutput": out}))

if __name__ == "__main__":
    main()
