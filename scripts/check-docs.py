#!/usr/bin/env python3
"""Stop doc sprawl: word budgets, AI-artifact filenames, duplicate paragraphs.

Usage: check-docs.py [path...]   (no paths: every tracked *.md / *.md.jinja2)

Existing violations go in .doc-sprawl-skip at the repo root, one
repo-relative path per line; `#` comments and blank lines are ignored.
"""

import os
import re
import subprocess
import sys

FENCE = re.compile(r"^(```|~~~)[ \t]*([^\n]*)\n.*?^\1[^\n]*$", re.MULTILINE | re.DOTALL)
COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
WORD = re.compile(r"[A-Za-z0-9][\w'.-]*")
PROSE_FENCES = {"", "text", "txt", "md", "markdown", "plain"}
DATED = re.compile(r"(^|/)([^/]*[-_])?[0-9]{4}-[0-9]{2}([-_.][^/]*)?$")
ARTIFACT_NAMES = {
    "plan", "plans", "summary", "notes", "todo",
    "progress", "implementation", "scratch", "memory",
}
MIN_PARAGRAPH = 25


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def stem(path):
    name = os.path.basename(path).lower()
    for suffix in (".md.jinja2", ".md"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name


def word_count(text):
    text = COMMENT.sub("", text)
    text = FENCE.sub(lambda m: m.group(0) if m.group(2).strip() in PROSE_FENCES else "", text)
    return len(WORD.findall(text))


def paragraphs(text):
    out = set()
    for block in re.split(r"\n[ \t]*\n", FENCE.sub("", text)):
        para = " ".join(block.split())
        if len(WORD.findall(para)) >= MIN_PARAGRAPH:
            out.add(para)
    return out


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def main(argv):
    os.chdir(git("rev-parse", "--show-toplevel").strip())
    tracked = [p for p in git("ls-files", "-z").split("\0") if p]
    skip = set()
    findings = []
    if os.path.isfile(".doc-sprawl-skip"):
        for raw in read(".doc-sprawl-skip").splitlines():
            entry = raw.strip()
            if entry and not entry.startswith("#"):
                skip.add(entry)
        tracked_set = set(tracked)
        findings += [
            f".doc-sprawl-skip: stale: {p} is not tracked" for p in sorted(skip - tracked_set)
        ]

    def wanted(p):
        return (
            p.endswith((".md", ".md.jinja2"))
            and os.path.basename(p) != "CHANGELOG.md"
            and not p.startswith(".beads/")
            and p not in skip
            and os.path.isfile(p)
            and not os.path.islink(p)
        )

    every = [p for p in tracked if wanted(p)]
    checked = [p for p in (os.path.normpath(a) for a in argv) if wanted(p)] if argv else every

    paras = {p: paragraphs(read(p)) for p in set(every) | set(checked)}
    for path in checked:
        limit = 500 if os.path.basename(path) in ("README.md", "README.md.jinja2") else 1200
        n = word_count(read(path))
        if n > limit:
            findings.append(f"{path}: budget: {n}/{limit} words")
        if DATED.search(path) or stem(path) in ARTIFACT_NAMES:
            findings.append(
                f"{path}: artifact: AI-artifact filename; move it into a bead"
                " (bd create / bd note / bd remember)"
            )
        for other in every:
            if other != path and paras[path] & paras[other]:
                findings.append(f"{path}: duplicate: shares a paragraph with {other}")

    for f in findings:
        print(f"doc-sprawl: {f}", file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
