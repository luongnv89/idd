#!/usr/bin/env python3
"""Detect a repository's language, framework, test runner, and size.

`/init-gitissue` decides four things by looking at the filesystem: which marker
files exist, which dependency names appear in them, and how many files are
tracked. That is lookup, not reasoning — and doing it with an agent means
reading `package.json`, `pyproject.toml`, `go.mod` and friends into a context
window to answer a question a table already answers. This script runs the
table; the model keeps the part the table cannot do, which is deciding what to
write into `.gitissue.yml` when nothing in the table matched.

An unmatched field comes back `null` and is listed in `unresolved`, so the
caller knows exactly which fields to fall back to prose for. A `null` language
is a real answer ("no marker file is present"), not a failure — the script
never guesses to avoid an empty field.

Output on stdout, one JSON object:

    {"language": "TypeScript", "language_source": "package.json",
     "framework": "Next.js", "framework_source": "package.json",
     "test_runner": "Jest", "test_runner_source": "jest.config.js",
     "repo_size": "medium", "file_count": 412,
     "file_count_source": "git ls-files", "issue_templates": 3,
     "derived": {"auto_test": true, "test_timeout": 300,
                 "stale_threshold_days": 14},
     "unresolved": []}

`file_count_source` is reported rather than assumed. The count prefers
`git ls-files`; when git cannot answer, the script walks the tree instead and
*says so*, because a tracked-file count and a filesystem count are different
measurements and a caller reading one as the other would be misled.

No untrusted value is ever passed to this script: it reads the repository
itself. Dependency files are attacker-controlled on a fork or a pull request
branch, so their contents are matched as data and never interpolated anywhere.

Exit codes
  0  detected — including the all-`null` case, which is a real answer
  2  usage error
  3  invalid input — `--root` is not a directory, or `--rules` is not a JSON
     object of the documented shape (stderr: `✗ gi-stack-detect: …`). Stop.
  4  cannot complete — the repository could not be read at all (stderr:
     `⚠ gi-stack-detect: …`). Degrade to the prose detection tables.

Authored at src/shared/scripts/gi-stack-detect.py — do not edit installed
copies; edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys

# Directories excluded from the file count, per the init-gitissue spec.
EXCLUDED_DIRS = (
    ".git",
    "node_modules",
    "vendor",
    "__pycache__",
    ".venv",
    "venv",
    "dist",
    "build",
    ".next",
    "target",
)

# Marker file (or glob) → language, in priority order. The first match at the
# shallowest depth wins; `package.json` is refined to TypeScript below.
LANGUAGE_MARKERS = [
    ("package.json", "JavaScript"),
    ("requirements.txt", "Python"),
    ("pyproject.toml", "Python"),
    ("setup.py", "Python"),
    ("Pipfile", "Python"),
    ("go.mod", "Go"),
    ("Cargo.toml", "Rust"),
    ("pom.xml", "Java"),
    ("build.gradle", "Java"),
    ("build.gradle.kts", "Java"),
    ("Gemfile", "Ruby"),
    ("*.csproj", "C#"),
    ("*.sln", "C#"),
]

# Files whose text is searched for framework dependency names.
DEPENDENCY_FILES = (
    "package.json",
    "requirements.txt",
    "pyproject.toml",
    "Pipfile",
    "Gemfile",
    "go.mod",
    "Cargo.toml",
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
)

# Dependency name → framework. Order matters: the more specific package wins,
# so `next` is tested before `react`, which every Next.js project also carries.
FRAMEWORK_MARKERS = [
    ("next", "Next.js"),
    ("nuxt", "Nuxt.js"),
    ("@angular/core", "Angular"),
    ("angular", "Angular"),
    ("react-dom", "React"),
    ("react", "React"),
    ("vue", "Vue.js"),
    ("express", "Express"),
    ("fastify", "Fastify"),
    ("django", "Django"),
    ("fastapi", "FastAPI"),
    ("flask", "Flask"),
    ("railties", "Rails"),
    ("rails", "Rails"),
    ("spring-boot", "Spring"),
    ("spring-core", "Spring"),
    ("gin-gonic/gin", "Gin"),
    ("actix-web", "Actix"),
    ("Microsoft.AspNetCore", "ASP.NET"),
    ("ASP.NET", "ASP.NET"),
]

# (kind, pattern, test runner), tried in order — the more specific marker first.
#   `file`         a tracked path matching a glob exists
#   `content`      a substring appears inside a named file
#   `content-any`  a substring appears in any file matching a glob (bounded)
TEST_RUNNER_MARKERS = [
    ("file", "jest.config.*", "Jest"),
    ("content", "package.json::\"jest\"", "Jest"),
    ("file", "vitest.config.*", "Vitest"),
    ("content", "package.json::\"vitest\"", "Vitest"),
    ("file", ".mocharc.*", "Mocha"),
    ("content", "package.json::\"mocha\"", "Mocha"),
    ("file", "karma.conf.js", "Karma"),
    ("file", "pytest.ini", "pytest"),
    ("file", "conftest.py", "pytest"),
    ("content", "pyproject.toml::[tool.pytest", "pytest"),
    ("content", "setup.cfg::[tool:pytest", "pytest"),
    ("content-any", "test_*.py::import unittest", "unittest"),
    ("file", "*_test.go", "Go test"),
    ("content-any", "*.rs::#[cfg(test)]", "Cargo test"),
    ("file", "src/test/*", "JUnit"),
    ("content", "Gemfile::rspec", "RSpec"),
]

# How many files a `content-any` marker may open before giving up. A bound is
# the difference between a detection pass and an unbounded scan of a monorepo.
MAX_CONTENT_ANY_FILES = 40

SIZE_BANDS = [(100, "small"), (1000, "medium")]
TEST_TIMEOUTS = {"small": 60, "medium": 300, "large": 600}
STALE_THRESHOLDS = {"small": 7, "medium": 14, "large": 30}

# Bounds the content reads so a pathological repository cannot hang the scan.
MAX_READ_BYTES = 512 * 1024


class InvalidInput(Exception):
    """Caller-supplied arguments are unusable — exit 3."""


class Unavailable(Exception):
    """The repository could not be read — exit 4, caller degrades."""


def list_files(root: str) -> tuple[list[str], str]:
    """Repository-relative paths, and which method produced them.

    `git ls-files` is preferred because it already honours `.gitignore`. When
    git cannot answer, the tree is walked instead — and the returned source
    string says so, so the difference is visible in the output rather than
    silently folded into one number.
    """
    try:
        proc = subprocess.run(
            ["git", "-C", root, "ls-files", "-z"],
            capture_output=True,
            check=False,
        )
        if proc.returncode == 0:
            names = [
                os.fsdecode(chunk)
                for chunk in proc.stdout.split(b"\0")
                if chunk
            ]
            return names, "git ls-files"
    except (FileNotFoundError, OSError):
        pass

    names = []
    try:
        for base, dirs, files in os.walk(root):
            dirs[:] = sorted(d for d in dirs if d not in EXCLUDED_DIRS)
            for name in sorted(files):
                rel = os.path.relpath(os.path.join(base, name), root)
                names.append(rel.replace(os.sep, "/"))
    except OSError as exc:
        raise Unavailable(f"cannot walk {root} — {exc}") from exc
    if not names and not os.path.isdir(root):
        raise Unavailable(f"cannot read {root}")
    return names, "filesystem walk"


def read_file(root: str, rel: str) -> str:
    try:
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as handle:
            return handle.read(MAX_READ_BYTES)
    except OSError:
        return ""


def depth(path: str) -> int:
    return path.count("/")


def match_paths(files: list[str], pattern: str) -> list[str]:
    """Tracked paths matching a glob, at the repo root or anywhere below it."""
    hits = [f for f in files if fnmatch.fnmatch(f, pattern) or fnmatch.fnmatch(os.path.basename(f), pattern)]
    return sorted(hits, key=lambda f: (depth(f), f))


def detect_language(root: str, files: list[str], markers: list) -> tuple[str | None, str | None]:
    best: tuple[int, str, str] | None = None
    for pattern, language in markers:
        for hit in match_paths(files, pattern):
            candidate = (depth(hit), hit, language)
            if best is None or candidate[0] < best[0]:
                best = candidate
            break
    if best is None:
        return None, None
    _, source, language = best
    if language == "JavaScript" and "typescript" in read_file(root, source).lower():
        language = "TypeScript"
    return language, source


def detect_framework(root: str, files: list[str], markers: list) -> tuple[str | None, str | None]:
    texts: list[tuple[str, str]] = []
    for name in DEPENDENCY_FILES:
        for hit in match_paths(files, name)[:3]:
            texts.append((hit, read_file(root, hit)))
    for token, framework in markers:
        pattern = re.compile(r"(?<![\w./@-])" + re.escape(token) + r"(?![\w-])", re.IGNORECASE)
        for source, text in texts:
            if pattern.search(text):
                return framework, source
    return None, None


def detect_test_runner(root: str, files: list[str], markers: list) -> tuple[str | None, str | None]:
    for kind, pattern, runner in markers:
        if kind == "file":
            hits = match_paths(files, pattern)
            if hits:
                return runner, hits[0]
        elif kind in ("content", "content-any"):
            name, _, needle = pattern.partition("::")
            budget = 3 if kind == "content" else MAX_CONTENT_ANY_FILES
            for hit in match_paths(files, name)[:budget]:
                if needle and needle.lower() in read_file(root, hit).lower():
                    return runner, hit
        else:
            raise InvalidInput(f"unknown test-runner marker kind: {kind!r}")
    return None, None


def size_band(count: int) -> str:
    for limit, name in SIZE_BANDS:
        if count < limit:
            return name
    return "large"


def load_rules(path: str) -> dict:
    """Read a rules override file and validate its shape."""
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as exc:
        raise InvalidInput(f"cannot read --rules {path} — {exc}") from exc
    try:
        loaded = json.loads(text)
    except json.JSONDecodeError as exc:
        raise InvalidInput(f"--rules {path} is not valid JSON — {exc}") from exc
    if not isinstance(loaded, dict):
        raise InvalidInput(f"--rules {path} must hold a JSON object")
    for key, arity in (("language", 2), ("framework", 2), ("test_runner", 3)):
        rows = loaded.get(key)
        if rows is None:
            continue
        if not isinstance(rows, list) or any(
            not isinstance(row, list) or len(row) != arity or
            any(not isinstance(cell, str) for cell in row)
            for row in rows
        ):
            raise InvalidInput(
                f"--rules '{key}' must be an array of {arity}-string arrays"
            )
    return loaded


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-stack-detect.py",
        description=(
            "Detect a repository's language, framework, test runner, size, and "
            "issue templates. Prints one JSON object on stdout."
        ),
        epilog="Example: python3 gi-stack-detect.py --root .",
    )
    parser.add_argument("--root", default=".", metavar="DIR", help="repository root (default .)")
    parser.add_argument(
        "--rules",
        metavar="FILE",
        help=(
            "JSON overriding the built-in detection tables: "
            '{"language": [[glob, name]], "framework": [[dep, name]], '
            '"test_runner": [[kind, pattern, name]]}. Entries replace the '
            "matching built-in table outright"
        ),
    )
    args = parser.parse_args(argv)

    try:
        root = os.path.abspath(args.root)
        if not os.path.isdir(root):
            raise InvalidInput(f"--root is not a directory: {args.root}")
        rules = load_rules(args.rules) if args.rules else {}
        language_rules = [tuple(row) for row in rules.get("language", LANGUAGE_MARKERS)]
        framework_rules = [tuple(row) for row in rules.get("framework", FRAMEWORK_MARKERS)]
        runner_rules = [tuple(row) for row in rules.get("test_runner", TEST_RUNNER_MARKERS)]
        files, count_source = list_files(root)
        language, language_source = detect_language(root, files, language_rules)
        framework, framework_source = detect_framework(root, files, framework_rules)
        runner, runner_source = detect_test_runner(root, files, runner_rules)
    except InvalidInput as exc:
        sys.stderr.write(f"✗ gi-stack-detect: {exc}\n")
        return 3
    except Unavailable as exc:
        sys.stderr.write(f"⚠ gi-stack-detect: {exc}\n")
        return 4

    templates = [
        f for f in files
        if f.startswith(".github/ISSUE_TEMPLATE/") and f.count("/") == 2
    ]
    count = len(files)
    band = size_band(count)
    unresolved = [
        name
        for name, value in (
            ("language", language),
            ("framework", framework),
            ("test_runner", runner),
        )
        if value is None
    ]

    print(
        json.dumps(
            {
                "language": language,
                "language_source": language_source,
                "framework": framework,
                "framework_source": framework_source,
                "test_runner": runner,
                "test_runner_source": runner_source,
                "repo_size": band,
                "file_count": count,
                "file_count_source": count_source,
                "issue_templates": len(templates),
                "derived": {
                    "auto_test": runner is not None,
                    "test_timeout": TEST_TIMEOUTS[band],
                    "stale_threshold_days": STALE_THRESHOLDS[band],
                },
                "unresolved": unresolved,
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
