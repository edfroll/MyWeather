#!/usr/bin/env python3
"""PreToolUse guard for commits (harness §7.2, CLAUDE.md «Коммиты и PR»).

Bash: a `git commit` must have author edvard.froll@gmail.com, and its message
must carry no AI attribution (Co-Authored-By: Claude, Claude-Session,
"Generated with/by Claude Code", claude.ai session links).
GitHub MCP: commits made through the API (push_files, create_or_update_file,
delete_file) and squash messages (merge_pull_request) get the same message check.

Exit codes follow Claude Code hooks: 0 allows, 2 blocks and shows stderr to
the model. An internal error allows the call with a warning (exit 1), so a bug
in the guard cannot stop the pipeline.
"""
import json
import os
import re
import shlex
import subprocess
import sys

AUTHOR_EMAIL = "edvard.froll@gmail.com"

ATTRIBUTION = [
    re.compile(r"co-authored-by:\s*claude", re.IGNORECASE),
    re.compile(r"co-authored-by:[^\n]*noreply@anthropic\.com", re.IGNORECASE),
    re.compile(r"claude-session:", re.IGNORECASE),
    re.compile(r"generated\s+(with|by)\s+\[?claude\s+code", re.IGNORECASE),
    re.compile(r"claude\.ai/code/session_", re.IGNORECASE),
]

# `git [global options] commit` as a command: after a separator or quote, optionally
# behind env assignments, `env`, `command`, or a path to git.
GIT_COMMIT = re.compile(
    r"(?:^|[;&|(\n\"'`]|\bthen|\bdo|\$\()\s*(?:(?:env|command)\s+)?(?:\w+=\S*\s+)*(?:\S*/)?git"
    r"((?:\s+(?:-[cC]\s+\S+|--[\w-]+(?:=\S+)?|-[a-zA-Z]))*)\s+commit(?:\s|$)"
)
# Any git command that writes a commit message; the message check covers all of them.
GIT_WRITES_MESSAGE = re.compile(r"\bgit\b[\s\S]*\b(commit|merge|cherry-pick|revert|tag|notes)\b")
EMAIL = re.compile(r"<([^>]*)>")


class Violation(Exception):
    pass


def check_message(text, where):
    for pattern in ATTRIBUTION:
        match = pattern.search(text)
        if match:
            raise Violation(
                f"{where} carries AI attribution ({match.group(0).strip()!r}); "
                "commits must not have Co-Authored-By/Claude-Session trailers or 'Generated with Claude Code'"
            )


def tokens_after(command, start):
    try:
        return shlex.split(command[start:], comments=False)
    except ValueError:
        return command[start:].split()


def check_bash(command, cwd):
    if GIT_WRITES_MESSAGE.search(command):
        # The whole command text holds -m strings and heredoc bodies.
        check_message(command, "commit message")
    matches = list(GIT_COMMIT.finditer(command))
    for match in matches:
        git_opts = tokens_after(match.group(1), 0) if match.group(1) else []
        args = tokens_after(command, match.end())
        workdir = cwd
        for i, opt in enumerate(git_opts):
            if opt == "-C" and i + 1 < len(git_opts):
                workdir = os.path.join(workdir or ".", git_opts[i + 1])
        author = None
        msg_file = None
        amend = reset_author = False
        for i, arg in enumerate(args):
            if arg in ("&&", "||", ";", "|"):
                break
            if arg == "--amend":
                amend = True
            elif arg == "--reset-author":
                reset_author = True
            elif arg.startswith("--author="):
                author = arg.split("=", 1)[1]
            elif arg == "--author" and i + 1 < len(args):
                author = args[i + 1]
            elif arg.startswith("--file="):
                msg_file = arg.split("=", 1)[1]
            elif arg in ("-F", "--file") and i + 1 < len(args):
                msg_file = args[i + 1]
        if msg_file and msg_file != "-":
            path = os.path.join(workdir or ".", msg_file)
            if os.path.isfile(path):
                with open(path, encoding="utf-8", errors="replace") as fh:
                    check_message(fh.read(), f"commit message file {msg_file}")
        env_email = re.findall(r"\bGIT_AUTHOR_EMAIL=(\S+)", command[: match.end()])
        if amend and not reset_author and not author:
            email = amended_email(workdir)  # --amend keeps the original author
        else:
            email = effective_email(author, env_email[-1] if env_email else None, git_opts, workdir)
        if email is not None and email.strip("'\"").lower() != AUTHOR_EMAIL:
            raise Violation(
                f"commit author email is {email!r}; only {AUTHOR_EMAIL} is allowed "
                "(check `git var GIT_AUTHOR_IDENT`)"
            )


def amended_email(workdir):
    try:
        log = subprocess.run(["git", "log", "-1", "--format=%ae"],
                             cwd=workdir or None, capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    if log.returncode != 0:
        return None
    return log.stdout.strip() or None


def effective_email(author, env_email, git_opts, workdir):
    """Author email the commit would get: --author, then env, then git's own resolution."""
    if author:
        found = EMAIL.search(author)
        return found.group(1) if found else author
    if env_email:
        return env_email
    config = []
    for i, opt in enumerate(git_opts):
        if opt == "-c" and i + 1 < len(git_opts):
            config += ["-c", git_opts[i + 1]]
    try:
        ident = subprocess.run(
            ["git", *config, "var", "GIT_AUTHOR_IDENT"],
            cwd=workdir or None, capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if ident.returncode != 0:
        return None  # not a repo or no identity: git itself will refuse
    found = EMAIL.search(ident.stdout)
    return found.group(1) if found else None


def check_github(tool_name, tool_input):
    for field in ("message", "commit_message", "commit_title"):
        value = tool_input.get(field)
        if isinstance(value, str):
            check_message(value, f"{tool_name}.{field}")


def main():
    try:
        event = json.load(sys.stdin)
        tool_name = event.get("tool_name", "")
        tool_input = event.get("tool_input") or {}
        if tool_name == "Bash":
            check_bash(tool_input.get("command", ""), event.get("cwd"))
        else:
            check_github(tool_name, tool_input)
    except Violation as err:
        print(f"Blocked by .claude/hooks/commit_guard.py (harness §7.2): {err}", file=sys.stderr)
        return 2
    except Exception as err:  # noqa: BLE001 — never stop the pipeline on a guard bug
        print(f"commit_guard.py internal error, call allowed: {err!r}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
