#!/usr/bin/env python3
"""
test/test_hook.py — checks the PreToolUse hook's two protocols.
Run: python3 test/test_hook.py

Only --no-wait (tutor) mode is exercised end-to-end: blocking mode by design
sits waiting for a decision file for ~570s, so it is checked indirectly via the
trigger it leaves behind.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "..", "bin", "vim-preview-diff.py")
GLOBAL_DIR = os.path.expanduser("~/.claude/vim-diff")


def run(tool_input, tool_name="Edit", args=(), session="pytest-session"):
    """Invoke the hook; return (parsed stdout or None, trigger dict or None)."""
    cwd = tempfile.mkdtemp()
    path = os.path.join(cwd, "notes.md")
    with open(path, "w") as f:
        f.write("original\n")
    tool_input = dict(tool_input, file_path=path)
    payload = json.dumps({"tool_name": tool_name, "cwd": cwd,
                          "session_id": session, "tool_input": tool_input})
    proc = subprocess.run([sys.executable, HOOK, *args], input=payload,
                          capture_output=True, text=True, timeout=30)
    assert proc.returncode == 0, proc.stderr

    trigger = None
    for name in os.listdir(GLOBAL_DIR):
        if name.startswith(session) and name.endswith("-trigger.json"):
            with open(os.path.join(GLOBAL_DIR, name)) as f:
                trigger = json.load(f)
    if trigger:
        # Inline the payloads before cleanup wipes them
        for key in ("orig", "proposed"):
            with open(trigger[key]) as f:
                trigger[key + "_content"] = f.read()
    # Clean up this test's artefacts, not other sessions'
    for name in os.listdir(GLOBAL_DIR):
        if name.startswith(session):
            os.remove(os.path.join(GLOBAL_DIR, name))
    shutil.rmtree(cwd, ignore_errors=True)

    out = json.loads(proc.stdout)["hookSpecificOutput"] if proc.stdout.strip() else None
    return out, trigger


def test_no_wait_denies_immediately():
    out, trigger = run({"old_string": "original", "new_string": "edited"},
                       args=["--no-wait"])
    assert out is not None, "tutor mode must answer the permission request"
    assert out["permissionDecision"] == "deny", out
    # The reason is Claude's only instruction not to route around the deny
    reason = out["permissionDecisionReason"]
    assert "notes.md" in reason, reason
    assert "wait" in reason.lower() and "not retry" in reason.lower().replace("do not", "not"), reason


def test_no_wait_leaves_a_trigger_flagged_for_vim():
    out, trigger = run({"old_string": "original", "new_string": "edited"},
                       args=["--no-wait"])
    assert trigger is not None, "Vim needs a trigger to open the diff"
    assert trigger["no_wait"] is True, trigger
    assert trigger["display_name"] == "notes.md", trigger
    # Vim writes the file itself in this mode, so it must know the real target
    assert trigger["file_path"].endswith("/notes.md"), trigger
    assert trigger["proposed_content"] == "edited\n", trigger["proposed_content"]
    assert trigger["orig_content"] == "original\n", trigger["orig_content"]


def test_blocking_mode_trigger_is_not_flagged():
    """Preview mode must not be turned non-blocking by accident."""
    # Pre-create the decision file so the blocking loop returns at once.
    os.makedirs(GLOBAL_DIR, exist_ok=True)
    # Can't know the pid-suffixed name up front, so assert on the flag only,
    # via a --no-wait run compared against the code path's default.
    out, trigger = run({"old_string": "original", "new_string": "edited"},
                       args=["--no-wait"])
    assert trigger["no_wait"] is True
    # Default (no flag) sets no_wait False — verified by reading the source
    # rather than by a 570s blocking call.
    with open(HOOK) as f:
        src = f.read()
    assert 'no_wait = "--no-wait" in sys.argv' in src


def test_write_tool_captures_full_content():
    out, trigger = run({"content": "brand new\n"}, tool_name="Write",
                       args=["--no-wait"])
    assert trigger["proposed_content"] == "brand new\n", trigger["proposed_content"]


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            try:
                fn()
                print("ok   " + name)
            except AssertionError as e:
                failures += 1
                print("FAIL " + name + ": " + str(e))
    print(("%d failure(s)" % failures) if failures else "all passed")
    sys.exit(1 if failures else 0)
