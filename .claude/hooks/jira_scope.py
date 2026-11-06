#!/usr/bin/env python3
"""PreToolUse guard for Atlassian MCP calls (harness §7.2).

Allows a call only when every Atlassian site in it is myweather.atlassian.net
and every Jira issue or project it names belongs to project MW.

Exit codes follow Claude Code hooks: 0 allows, 2 blocks and shows stderr to
the model. An internal error allows the call with a warning (exit 1), so a bug
in the guard cannot stop the pipeline.
"""
import json
import re
import sys
from urllib.parse import urlparse

CLOUD_ID = "7d0914d2-a05e-48d3-a0e5-46fe9e3870b9"
SITE_HOST = "myweather.atlassian.net"
PROJECT_KEY = "MW"
PROJECT_ID = "10000"

TOP_LEVEL_OR = re.compile(r"\bOR\b|\|\|", re.IGNORECASE)
ISSUE_KEY = re.compile(r"^MW-\d+$")
ANY_ISSUE_KEY = re.compile(r"\b([A-Z][A-Z0-9_]*)-\d+\b")
JQL_PROJECT = re.compile(
    r"\bproject\s*(not\s+in|is\s+not|in|is|!=|=|~)\s*(\([^)]*\)|\"[^\"]*\"|'[^']*'|[\w-]+)",
    re.IGNORECASE,
)

# Field names that carry a Jira issue reference.
ISSUE_FIELDS = {
    "issueidorkey", "issuekey", "issuekeys", "issueid", "issueids",
    "rankbeforeissue", "rankafterissue", "parentkey", "parentissuekey",
    "epickey", "sourceissuekey", "targetissuekey",
}
# Field names that carry a Jira project reference.
PROJECT_FIELDS = {"projectkey", "projectidorkey", "projectid", "projectkeys"}
# Objects whose "key" is an issue key: fields.parent, issue links.
ISSUE_OBJECTS = {"parent", "issue", "inwardissue", "outwardissue", "epic"}


class Violation(Exception):
    pass


def site_ok(value):
    v = str(value).strip().lower()
    if v == CLOUD_ID:
        return True
    host = urlparse(v).hostname if "://" in v else v.split("/")[0]
    return host == SITE_HOST


def check_issue_ref(field, value):
    v = str(value).strip()
    if "://" in v:
        parsed = urlparse(v)
        if parsed.hostname != SITE_HOST:
            raise Violation(f"{field}: URL outside {SITE_HOST}: {v}")
        v = parsed.path.rstrip("/").rsplit("/", 1)[-1]
    if not ISSUE_KEY.match(v):
        raise Violation(
            f"{field}={value!r}: only MW-n issue keys are allowed "
            "(numeric ids are refused too, use the key)"
        )


def check_project_ref(field, value):
    v = str(value).strip()
    if v not in (PROJECT_KEY, PROJECT_ID):
        raise Violation(f"{field}={value!r}: only project {PROJECT_KEY} is allowed")


def top_level(jql):
    """JQL with quoted strings and parenthesized groups removed."""
    text = re.sub(r"\"[^\"]*\"|'[^']*'", '""', jql)
    out, depth = [], 0
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(depth - 1, 0)
        elif depth == 0:
            out.append(ch)
    return "".join(out)


def check_jql(jql):
    keys = ANY_ISSUE_KEY.findall(jql)
    foreign = sorted({k for k in keys if k != PROJECT_KEY})
    if foreign:
        raise Violation(f"jql names issues outside {PROJECT_KEY}: {', '.join(foreign)}")
    if TOP_LEVEL_OR.search(top_level(jql)):
        raise Violation("jql: top-level OR can widen the query beyond MW; put OR inside parentheses after 'project = MW AND'")
    clauses = JQL_PROJECT.findall(jql)
    for op, operand in clauses:
        op = " ".join(op.lower().split())
        names = [n.strip().strip("\"'") for n in operand.strip("()").split(",")]
        if op not in ("=", "in") or any(n.upper() not in (PROJECT_KEY, PROJECT_ID) for n in names):
            raise Violation(f"jql project clause must be 'project = {PROJECT_KEY}': {op} {operand}")
    if not clauses and not keys:
        raise Violation(f"jql must be limited to project {PROJECT_KEY} (add 'project = {PROJECT_KEY}')")


def walk(node, parent_key=""):
    if isinstance(node, dict):
        for key, value in node.items():
            name = key.lower()
            if name == "cloudid":
                if not site_ok(value):
                    raise Violation(f"cloudId={value!r}: only {CLOUD_ID} ({SITE_HOST}) is allowed")
            elif name == "jql" and isinstance(value, str):
                check_jql(value)
            elif name in ISSUE_FIELDS:
                for item in value if isinstance(value, list) else [value]:
                    check_issue_ref(key, item)
            elif name in PROJECT_FIELDS:
                for item in value if isinstance(value, list) else [value]:
                    check_project_ref(key, item)
            elif name in ("key", "id") and parent_key.lower() == "project":
                check_project_ref(f"project.{key}", value)
            elif name == "key" and parent_key.lower() in ISSUE_OBJECTS:
                check_issue_ref(f"{parent_key}.key", value)
            elif name == "project" and isinstance(value, str):
                check_project_ref(key, value)
            else:
                walk(value, key)
    elif isinstance(node, list):
        for item in node:
            walk(item, parent_key)


def main():
    try:
        event = json.load(sys.stdin)
        walk(event.get("tool_input") or {})
    except Violation as err:
        print(f"Blocked by .claude/hooks/jira_scope.py (harness §7.2): {err}", file=sys.stderr)
        return 2
    except Exception as err:  # noqa: BLE001 — never stop the pipeline on a guard bug
        print(f"jira_scope.py internal error, call allowed: {err!r}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
