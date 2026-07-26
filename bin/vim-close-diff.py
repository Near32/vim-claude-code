#!/usr/bin/env python3
"""
vim-close-diff.py — PostToolUse hook for Claude Code
Vim closes its own preview when a decision is made; this is belt-and-braces:
tell every Vim to close any leftover preview and sweep stale session files.
"""
import sys
import os
import time
import subprocess

GLOBAL_DIR = os.path.expanduser("~/.claude/vim-diff")

def main():
    try:
        sys.stdin.read()
    except Exception:
        pass

    try:
        servers = subprocess.check_output(["vim", "--serverlist"],
                stderr=subprocess.DEVNULL).decode("utf-8").split()
        for s in servers:
            subprocess.run(["vim", "--servername", s, "--remote-expr",
                    "claude_code#diff#close()"], stderr=subprocess.DEVNULL, timeout=5)
    except Exception:
        pass

    # Sweep session files older than an hour (crashed/timed-out sessions)
    try:
        cutoff = time.time() - 3600
        for name in os.listdir(GLOBAL_DIR):
            p = os.path.join(GLOBAL_DIR, name)
            if os.path.getmtime(p) < cutoff:
                os.remove(p)
    except OSError:
        pass

    sys.exit(0)

if __name__ == "__main__":
    main()
