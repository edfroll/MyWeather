#!/usr/bin/env python3
"""Tests for the PreToolUse guards. Run: python3 .claude/hooks/tests/test_hooks.py

Feeds hook JSON to each script the way Claude Code does and checks the exit code
(0 allows, 2 blocks). Standard library only; works on Linux and macOS.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HOOKS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JIRA = os.path.join(HOOKS, "jira_scope.py")
COMMIT = os.path.join(HOOKS, "commit_guard.py")
CLOUD = "7d0914d2-a05e-48d3-a0e5-46fe9e3870b9"
GOOD = "edvard.froll@gmail.com"

# The guards must not depend on the caller's git identity.
GIT_ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


def run(script, tool_name, tool_input, cwd=None, env=None):
    event = {"hook_event_name": "PreToolUse", "tool_name": tool_name,
             "tool_input": tool_input, "cwd": cwd or os.getcwd()}
    proc = subprocess.run([sys.executable, script], input=json.dumps(event),
                          capture_output=True, text=True, env=env or GIT_ENV)
    return proc.returncode, proc.stderr


class JiraScope(unittest.TestCase):
    def assertAllowed(self, tool, inp):
        code, err = run(JIRA, tool, inp)
        self.assertEqual(code, 0, err)

    def assertBlocked(self, tool, inp):
        code, err = run(JIRA, tool, inp)
        self.assertEqual(code, 2, f"not blocked: {inp}")
        self.assertIn("Blocked", err)

    def test_mw_issue_passes(self):
        for prefix in ("mcp__Atlassian_MCP__", "mcp__claude_ai_Atlassian_MCP__"):
            self.assertAllowed(prefix + "getJiraIssue", {"cloudId": CLOUD, "issueIdOrKey": "MW-10"})

    def test_site_host_and_url_pass(self):
        self.assertAllowed("mcp__Atlassian_MCP__getJiraIssue",
                           {"cloudId": "myweather.atlassian.net", "issueIdOrKey": "MW-1"})
        self.assertAllowed("mcp__Atlassian_MCP__getJiraIssue",
                           {"cloudId": CLOUD, "issueIdOrKey": "https://myweather.atlassian.net/browse/MW-3"})

    def test_calls_without_site_pass(self):
        self.assertAllowed("mcp__Atlassian_MCP__getAccessibleAtlassianResources", {})
        self.assertAllowed("mcp__Atlassian_MCP__atlassianUserInfo", {})

    def test_foreign_cloud_blocked(self):
        self.assertBlocked("mcp__Atlassian_MCP__getJiraIssue",
                           {"cloudId": "11111111-2222-3333-4444-555555555555", "issueIdOrKey": "MW-10"})
        self.assertBlocked("mcp__Atlassian_MCP__getJiraIssue",
                           {"cloudId": "othersite.atlassian.net", "issueIdOrKey": "MW-10"})
        self.assertBlocked("mcp__Atlassian_MCP__executeRead",
                           {"name": "x", "cloudId": "https://evil.atlassian.net", "inputs": {}})

    def test_foreign_key_blocked(self):
        self.assertBlocked("mcp__Atlassian_MCP__getJiraIssue", {"cloudId": CLOUD, "issueIdOrKey": "ABC-1"})
        self.assertBlocked("mcp__Atlassian_MCP__getJiraIssue", {"cloudId": CLOUD, "issueIdOrKey": "10009"})
        self.assertBlocked("mcp__claude_ai_Atlassian_MCP__addOrEditJiraIssueComment",
                           {"cloudId": CLOUD, "issueIdOrKey": "OPS-7", "commentBody": "hi"})
        self.assertBlocked("mcp__Atlassian_MCP__getJiraIssue",
                           {"cloudId": CLOUD, "issueIdOrKey": "https://other.atlassian.net/browse/MW-1"})

    def test_nested_inputs_checked(self):
        self.assertBlocked("mcp__Atlassian_MCP__executeWrite",
                           {"name": "x", "cloudId": CLOUD, "inputs": {"issueIdOrKey": "ABC-2"}})
        self.assertAllowed("mcp__Atlassian_MCP__executeWrite",
                           {"name": "x", "cloudId": CLOUD, "inputs": {"issueIdOrKey": "MW-2"}})

    def test_create_and_edit(self):
        self.assertAllowed("mcp__Atlassian_MCP__createJiraIssue",
                           {"cloudId": CLOUD, "projectKey": "MW", "issueTypeName": "Chore", "summary": "UTF-8 fix"})
        self.assertBlocked("mcp__Atlassian_MCP__createJiraIssue",
                           {"cloudId": CLOUD, "projectKey": "OPS", "issueTypeName": "Task", "summary": "x"})
        self.assertAllowed("mcp__Atlassian_MCP__editJiraIssue",
                           {"cloudId": CLOUD, "issueIdOrKey": "MW-10",
                            "fields": {"parent": {"key": "MW-1"}, "labels": ["a"]}, "rankAfterIssue": "MW-9"})
        self.assertBlocked("mcp__Atlassian_MCP__editJiraIssue",
                           {"cloudId": CLOUD, "issueIdOrKey": "MW-10", "fields": {"parent": {"key": "ABC-1"}}})
        self.assertBlocked("mcp__Atlassian_MCP__editJiraIssue",
                           {"cloudId": CLOUD, "issueIdOrKey": "MW-10", "rankBeforeIssue": "ABC-3"})
        self.assertBlocked("mcp__Atlassian_MCP__createJiraIssue",
                           {"cloudId": CLOUD, "fields": {"project": {"id": "10001"}}})
        self.assertAllowed("mcp__Atlassian_MCP__createJiraIssue",
                           {"cloudId": CLOUD, "fields": {"project": {"id": "10000"}}})

    def test_jql(self):
        tool = "mcp__Atlassian_MCP__searchJiraIssuesUsingJql"
        for jql in ("project = MW AND statusCategory != Done ORDER BY rank",
                    'project in ("MW") AND sprint in openSprints()',
                    "key = MW-10", "parent = MW-1 ORDER BY created DESC"):
            self.assertAllowed(tool, {"cloudId": CLOUD, "jql": jql})
        self.assertAllowed(tool, {"cloudId": CLOUD,
                                  "jql": 'project = MW AND (status = "To Do" OR assignee = currentUser()) ORDER BY rank'})
        for jql in ("statusCategory != Done", "project = OPS", "project in (MW, OPS)",
                    "project != MW", "project = MW OR key = ABC-1",
                    "project = MW OR assignee = currentUser()", "project = MW AND project is not EMPTY",
                    "project = MW || status = Done",
                    "(project = MW OR assignee = currentUser())",
                    "((project = MW) OR (status = Done)) ORDER BY rank"):
            self.assertBlocked(tool, {"cloudId": CLOUD, "jql": jql})

    def test_bad_input_does_not_block(self):
        proc = subprocess.run([sys.executable, JIRA], input="not json", capture_output=True, text=True)
        self.assertEqual(proc.returncode, 1)


class CommitGuard(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = self.tmp.name
        subprocess.run(["git", "init", "-q", self.repo], check=True, env=GIT_ENV)
        self.set_email(GOOD)

    def tearDown(self):
        self.tmp.cleanup()

    def set_email(self, email):
        subprocess.run(["git", "-C", self.repo, "config", "user.name", "Edward"], check=True, env=GIT_ENV)
        subprocess.run(["git", "-C", self.repo, "config", "user.email", email], check=True, env=GIT_ENV)

    def bash(self, command, env=None):
        return run(COMMIT, "Bash", {"command": command}, cwd=self.repo, env=env)

    def test_good_commit_passes(self):
        self.assertEqual(self.bash('git commit -m "MW-10: add hooks"')[0], 0)
        heredoc = "git add . && git commit -q -F - <<'EOF'\nMW-10: add hooks\n\nBody.\nEOF"
        self.assertEqual(self.bash(heredoc)[0], 0)

    def test_other_commands_pass(self):
        self.set_email("someone@example.com")
        for cmd in ("git status", "git log --author=x", "echo git commit", "grep -rn 'commit' ."):
            self.assertEqual(self.bash(cmd)[0], 0, cmd)

    def test_wrong_config_author_blocked(self):
        self.set_email("noreply@anthropic.com")
        code, err = self.bash('git commit -m "MW-10: x"')
        self.assertEqual(code, 2)
        self.assertIn("author", err)

    def test_author_overrides(self):
        self.assertEqual(self.bash('git commit --author="Claude <noreply@anthropic.com>" -m x')[0], 2)
        self.assertEqual(self.bash("GIT_AUTHOR_EMAIL=bot@example.com git commit -m x")[0], 2)
        self.assertEqual(self.bash("git -c user.email=bot@example.com commit -m x")[0], 2)
        self.assertEqual(self.bash(f'git commit --author "Edward <{GOOD}>" -m x')[0], 0)
        env = dict(GIT_ENV, GIT_AUTHOR_EMAIL="bot@example.com")
        self.assertEqual(self.bash("git commit -m x", env=env)[0], 2)

    def test_trailers_blocked(self):
        bad = [
            "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>",
            "co-authored-by: claude <noreply@anthropic.com>",
            "Claude-Session: https://claude.ai/code/session_015pg",
            "🤖 Generated with [Claude Code](https://claude.com/claude-code)",
            "Generated by Claude Code",
        ]
        for line in bad:
            cmd = f"git commit -F - <<'EOF'\nMW-10: x\n\n{line}\nEOF"
            code, err = self.bash(cmd)
            self.assertEqual(code, 2, line)
            self.assertIn("attribution", err)

    def test_other_command_forms(self):
        trailer = "Co-Authored-By: Claude <noreply@anthropic.com>"
        for cmd in (f'env FOO=1 git commit -m x -m "{trailer}"',
                    f'command git commit -m x -m "{trailer}"',
                    f'/usr/bin/git commit -m x -m "{trailer}"',
                    f"bash -c 'git commit -m x -m \"{trailer}\"'",
                    f'git merge --no-ff -m "{trailer}" topic'):
            self.assertEqual(self.bash(cmd)[0], 2, cmd)
        self.set_email("bot@example.com")
        for cmd in ("env FOO=1 git commit -m x", "/usr/bin/git commit -m x", "bash -c 'git commit -m x'"):
            self.assertEqual(self.bash(cmd)[0], 2, cmd)

    def test_amend_checks_original_author(self):
        def commit(email):
            subprocess.run(["git", "-C", self.repo, "-c", f"user.email={email}", "commit", "-q",
                            "--allow-empty", "-m", "x"], check=True, env=GIT_ENV)
        commit("bot@example.com")
        self.assertEqual(self.bash("git commit --amend --no-edit")[0], 2)
        self.assertEqual(self.bash("git commit --amend --no-edit --reset-author")[0], 0)
        commit(GOOD)
        self.assertEqual(self.bash("git commit --amend --no-edit")[0], 0)

    def test_message_file_checked(self):
        with open(os.path.join(self.repo, "msg.txt"), "w") as fh:
            fh.write("MW-10: x\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n")
        self.assertEqual(self.bash("git commit -F msg.txt")[0], 2)

    def test_github_mcp(self):
        tool = "mcp__github__push_files"
        self.assertEqual(run(COMMIT, tool, {"message": "MW-10: x"})[0], 0)
        self.assertEqual(run(COMMIT, tool, {"message": "x\n\nCo-Authored-By: Claude <noreply@anthropic.com>"})[0], 2)
        self.assertEqual(run(COMMIT, "mcp__github__merge_pull_request",
                             {"commit_title": "MW-10: x (#19)", "commit_message": "Generated with Claude Code"})[0], 2)


if __name__ == "__main__":
    unittest.main(verbosity=1)
