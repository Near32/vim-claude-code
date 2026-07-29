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

def main():
    try:
        data = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    tool_name = data.get("tool_name")
    if tool_name not in ("Edit", "Write", "MultiEdit"):
        sys.exit(0)

    servers = running_vim_servers()
    if not servers:
        sys.exit(0) 

    cwd = data.get("cwd", os.getcwd())
    tool_input = data.get("tool_input", {})
    file_path = tool_input.get("file_path", "")
    if not file_path:
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

    # Heuristic category suggestion for the provenance prompt (Appendix 10)
    def suggest_category(tool, orig, prop):
        import re
        words = lambda s: re.findall(r"[a-zA-Z]+", s.lower())
        if tool == "Write" or abs(len(prop) - len(orig)) > 400:
            return "4 (S28-29 OUT-OF-SCOPE?) — large/new content, likely reject"
        old_w, new_w = words(orig), words(prop)
        if sorted(old_w) == sorted(new_w):
            return "1 (S25-correction) — punctuation/format only, words unchanged"
        if len(set(old_w) ^ set(new_w)) <= 3:
            return "1 (S25-correction) — small word-level fix"
        return "2 (S26-identified-issue) — wording changed, ensure fix is your own"

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
        }, f)

    notify_all_vims(servers)

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
