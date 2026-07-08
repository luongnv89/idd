#!/usr/bin/env python3
"""Build script for IDD distribution.

Reads authored sources under src/ + top-level docs/ and emits the
distribution outputs:

  skills/         — committed install surface (updated by ./scripts/build.sh after verify)
  <out>/skills/   — flattened, harness-agnostic skills (default: dist/skills/)
  <out>/agents/   — standalone Claude Code subagent definitions

The build is byte-deterministic per refactor-plan-v10.md §4.1.
Implements the (A-fail, B-fail, C-1) ADR row from
docs/decisions/cross-skill-invocation.md — sibling-relative paths only.

Per issue #81 consolidation, runtime docs (config-schema.md,
idd-methodology.md, naming-conventions.md, sync-conventions.md,
github-projects-sync.md) live at the top-level docs/ alongside
human-only project docs (ARCHITECTURE.md, CHANGELOG.md, etc.). The
build's transitive-closure scan determines which docs each skill needs
and bundles only those into the dist outputs.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path
from typing import Iterable

# --- Constants ---------------------------------------------------------------

TEXT_EXTS = {".md", ".txt", ".yml", ".yaml", ".json", ".toml"}

# Authored source skill prompts intentionally avoid the canonical SKILL.md
# filename so repo-wide installers (asm) only discover the generated top-level
# skills/ install surface, not the unbundled src/ authoring tree.
SOURCE_SKILL_MD = "SKILL.source.md"
OUTPUT_SKILL_MD = "SKILL.md"

# Reference patterns. URL-aware: matches inside http(s):// URLs are excluded
# at the rewriting stage by URL-prefix detection.
SKILL_TOKEN_RE = re.compile(r"\{\{skill:([a-z][a-z0-9-]*)\}\}")
SHARED_AGENT_RE = re.compile(r"(?<![\w/])shared/agents/([a-z][a-z0-9-]+\.md)")
RUNTIME_DOC_RE = re.compile(r"(?<![\w/])docs/([a-z][a-z0-9-]+\.md)")
BARE_SKILL_PATH_RE = re.compile(r"(?<![\w/])skills/([a-z][a-z0-9-]+)/SKILL\.md")

URL_RE = re.compile(r"https?://[^\s<>'\"\)]+")

# Phase E: stale GitHub URL guard. Runtime docs live at top-level docs/ (issue
# #81 — single-tree consolidation). Match any IDD-repo URL referencing
# /src/docs/<file>.md — those are stale post-#81 and should be /docs/<file>.md.
STALE_DOC_URL_RE = re.compile(
    r"https://github\.com/luongnv89/idd/[^\s<>'\"\)]*?/src/docs/([a-z][a-z0-9-]+\.md)"
)

BANNER_TMPL = (
    "<!-- Generated from /{rel}. Do not edit. "
    "Edit source and run ./scripts/build.sh. -->\n"
)

AGENT_DESCRIPTIONS = {
    "code-reviewer": (
        "Review IDD code changes and PRs with confidence-based findings."
    ),
    "codebase-researcher": (
        "Research GitHub issues against a codebase without modifying files."
    ),
    "duplicate-detector": (
        "Detect duplicate GitHub issues before creating new structured issues."
    ),
    "implementer": (
        "Implement an approved issue plan with code changes and focused tests."
    ),
    "fixer": (
        "Apply targeted fixes for review, test, CI, AC, and traceability failures."
    ),
    "issue-relationship-scanner": (
        "Scan issues for dependencies, file overlap, and already-fixed signals."
    ),
    "synthesizer": (
        "Synthesize issue research into ranked implementation options."
    ),
    "ui-reviewer": (
        "Review UI/UX code changes and screenshots for accessibility and layout."
    ),
}


# --- Errors ------------------------------------------------------------------


class BuildError(RuntimeError):
    """Raised on every Phase E abort condition."""


def _abort(msg: str) -> None:
    print(f"✗ {msg}", file=sys.stderr)
    raise BuildError(msg)


# --- File helpers ------------------------------------------------------------


def _is_text_file(path: Path) -> bool:
    return path.suffix in TEXT_EXTS


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # newline='\n' forces LF; no platform-default translation.
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(content)


def _copy_binary(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)


def _sorted_iterdir(path: Path) -> list[Path]:
    return sorted(path.iterdir(), key=lambda p: p.name)


def _walk_files(root: Path) -> Iterable[Path]:
    """Yield every file under root, sorted lexicographically at each level."""
    if not root.exists():
        return
    for entry in _sorted_iterdir(root):
        if entry.is_dir():
            yield from _walk_files(entry)
        else:
            yield entry


# --- URL-aware scanning ------------------------------------------------------


def _strip_urls(text: str) -> str:
    """Replace URL substrings with spaces of equal length so URL-internal
    bare paths are not misread as logical references during scanning."""
    return URL_RE.sub(lambda m: " " * len(m.group(0)), text)


# --- Phase A — Inventory -----------------------------------------------------


def _discover_public_skills(src: Path) -> list[str]:
    skills_root = src / "skills"
    if not skills_root.is_dir():
        _abort(f"src/skills/ not found at {skills_root}")
    out = []
    for entry in _sorted_iterdir(skills_root):
        if not entry.is_dir():
            continue
        if not (entry / SOURCE_SKILL_MD).is_file():
            continue
        out.append(entry.name)
    return out


def _discover_distributed_deprecated(src: Path) -> list[str]:
    """Deprecated skills that opt in via 'distribute:' frontmatter. Returns
    skill names that should be built into both dist outputs."""
    root = src / "deprecated-skills"
    if not root.is_dir():
        return []
    out = []
    for entry in _sorted_iterdir(root):
        if not entry.is_dir():
            continue
        skill_md = entry / SOURCE_SKILL_MD
        if not skill_md.is_file():
            continue
        text = _read_text(skill_md)
        if re.search(r"^\s*distribute:\s*\S", text, re.MULTILINE):
            out.append(entry.name)
    return out


def _check_non_markdown_in(root: Path, label: str, *, recursive: bool = True) -> None:
    if not root.exists():
        return
    if recursive:
        candidates = list(_walk_files(root))
    else:
        candidates = [p for p in _sorted_iterdir(root) if p.is_file()]
    for f in candidates:
        if f.suffix != ".md":
            _abort(f"non-markdown file under {label}: {f.relative_to(root.parent)}")


# --- Phase B — Transitive closure -------------------------------------------


def _scan_logical_refs(text: str) -> tuple[set[str], set[str], set[str]]:
    """Return (skill_tokens, shared_agents, runtime_docs) from text, ignoring
    matches inside http(s):// URLs."""
    cleaned = _strip_urls(text)
    skills = set(SKILL_TOKEN_RE.findall(cleaned))
    agents = set(SHARED_AGENT_RE.findall(cleaned))
    docs = set(RUNTIME_DOC_RE.findall(cleaned))
    return skills, agents, docs


def _compute_closure(
    src: Path,
    skill_name: str,
    skill_root: Path,
) -> tuple[set[str], set[str]]:
    """Compute transitive closure of shared agents and docs reachable from
    a skill. DFS with cycle detection (warning, no abort) and diamond-safe
    visited tracking. Returns sorted-eligible (agent_names, doc_names)."""
    agents: set[str] = set()
    docs: set[str] = set()
    visited: set[str] = set()
    active: set[str] = set()

    def _resolve(kind: str, name: str) -> Path | None:
        if kind == "agent":
            p = src / "shared" / "agents" / name
        else:
            # Runtime docs live at top-level docs/ (issue #81 consolidation).
            p = src.parent / "docs" / name
        return p if p.is_file() else None

    def _visit(kind: str, name: str, path_chain: list[str]) -> None:
        key = f"{kind}:{name}"
        if key in active:
            chain = " -> ".join(path_chain + [key])
            print(f"⚠ cycle detected: {chain}", file=sys.stderr)
            return
        if key in visited:
            return
        resolved = _resolve(kind, name)
        if resolved is None:
            _abort(
                f"unresolved {kind} reference '{name}' "
                f"(reachable from skill '{skill_name}')"
            )
        active.add(key)
        if kind == "agent":
            agents.add(name)
        else:
            docs.add(name)
        text = _read_text(resolved)
        _, sub_agents, sub_docs = _scan_logical_refs(text)
        for a in sorted(sub_agents):
            _visit("agent", a, path_chain + [key])
        for d in sorted(sub_docs):
            _visit("doc", d, path_chain + [key])
        active.discard(key)
        visited.add(key)

    # Seed: scan every text file in the skill root.
    seed_agents: set[str] = set()
    seed_docs: set[str] = set()
    for f in _walk_files(skill_root):
        if not _is_text_file(f):
            continue
        text = _read_text(f)
        skills_in_file, a, d = _scan_logical_refs(text)
        seed_agents.update(a)
        seed_docs.update(d)
        # Any bare skills/<name>/SKILL.md path is illegal in source.
        if BARE_SKILL_PATH_RE.search(_strip_urls(text)):
            _abort(
                f"illegal bare 'skills/<name>/SKILL.md' reference in source: "
                f"{f.relative_to(src.parent)} (use {{{{skill:<name>}}}} token)"
            )

    for a in sorted(seed_agents):
        _visit("agent", a, [f"skill:{skill_name}"])
    for d in sorted(seed_docs):
        _visit("doc", d, [f"skill:{skill_name}"])

    return agents, docs


# --- Phase E — Stale URL guard -----------------------------------------------


def _check_stale_doc_urls(src: Path) -> None:
    """Abort if any IDD-repo /src/docs/<file>.md URL refers to a doc that lives
    under top-level docs/. Such URLs must use docs/<file>.md (issue #81
    single-tree consolidation)."""
    docs_dir = src.parent / "docs"
    runtime_docs = {p.name for p in docs_dir.glob("*.md")} if docs_dir.is_dir() else set()
    if not runtime_docs:
        return
    for f in _walk_files(src):
        if not _is_text_file(f):
            continue
        text = _read_text(f)
        for m in STALE_DOC_URL_RE.finditer(text):
            file_name = m.group(1)
            if file_name in runtime_docs:
                _abort(
                    f"stale GitHub URL in {f.relative_to(src.parent)}: {m.group(0)} "
                    f"(should reference docs/{file_name} — see issue #81)"
                )


def _check_init_template_urls(src: Path) -> None:
    """Phase E init-template build-time check: scan
    src/skills/init-gitissue/templates/gitissue-template.yml for stale URLs.
    After issue #81 consolidation, runtime docs live at top-level docs/."""
    template = src / "skills" / "init-gitissue" / "templates" / "gitissue-template.yml"
    if not template.is_file():
        return
    text = _read_text(template)
    docs_dir = src.parent / "docs"
    runtime_docs = {p.name for p in docs_dir.glob("*.md")} if docs_dir.is_dir() else set()
    for m in STALE_DOC_URL_RE.finditer(text):
        file_name = m.group(1)
        if file_name in runtime_docs:
            _abort(
                f"init-gitissue template has stale doc URL: {m.group(0)} "
                f"(should reference docs/{file_name} — see issue #81)"
            )


# --- Reference rewriting -----------------------------------------------------


def _rewrite_for_standalone(text: str) -> str:
    """Apply standalone (dist/skills/) rewrites — URL-aware.

      {{skill:X}}            -> ../X/SKILL.md
      shared/agents/X.md     -> references/agents/X.md
      docs/Y.md              -> references/docs/Y.md
    """
    return _rewrite_url_aware(
        text,
        skill_form=lambda name: f"../{name}/SKILL.md",
        agent_form=lambda name: f"references/agents/{name}",
        doc_form=lambda name: f"references/docs/{name}",
    )


def _rewrite_url_aware(text, *, skill_form, agent_form, doc_form):
    """Rewrite logical references outside of URLs only. URL spans are passed
    through verbatim."""
    parts = []
    cursor = 0
    for m in URL_RE.finditer(text):
        # Rewrite the non-URL gap.
        gap = text[cursor : m.start()]
        gap = SKILL_TOKEN_RE.sub(lambda mm: skill_form(mm.group(1)), gap)
        gap = SHARED_AGENT_RE.sub(lambda mm: agent_form(mm.group(1)), gap)
        gap = RUNTIME_DOC_RE.sub(lambda mm: doc_form(mm.group(1)), gap)
        parts.append(gap)
        # Pass URL through unchanged.
        parts.append(m.group(0))
        cursor = m.end()
    tail = text[cursor:]
    tail = SKILL_TOKEN_RE.sub(lambda mm: skill_form(mm.group(1)), tail)
    tail = SHARED_AGENT_RE.sub(lambda mm: agent_form(mm.group(1)), tail)
    tail = RUNTIME_DOC_RE.sub(lambda mm: doc_form(mm.group(1)), tail)
    parts.append(tail)
    return "".join(parts)


# --- Phase C — flattened skills ----------------------------------------------


def _emit_flattened_skill(
    src: Path,
    skill_root: Path,
    out_dir: Path,
    agents: set[str],
    docs: set[str],
) -> None:
    """Copy authored skill content to out_dir, copy transitive deps under
    out_dir/references/, rewrite logical refs throughout."""
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    # Copy authored content (rewriting text files).
    for f in _walk_files(skill_root):
        rel = f.relative_to(skill_root)
        dst_rel = Path(OUTPUT_SKILL_MD) if rel == Path(SOURCE_SKILL_MD) else rel
        dst = out_dir / dst_rel
        if _is_text_file(f):
            text = _read_text(f)
            _write_text(dst, _rewrite_for_standalone(text))
        else:
            _copy_binary(f, dst)

    # Copy transitive shared agents (banner + rewrite).
    for name in sorted(agents):
        src_path = src / "shared" / "agents" / name
        dst_path = out_dir / "references" / "agents" / name
        text = _read_text(src_path)
        banner = BANNER_TMPL.format(rel=f"src/shared/agents/{name}")
        _write_text(dst_path, banner + _rewrite_for_standalone(text))

    # Copy transitive runtime docs (banner + rewrite). Runtime docs live at
    # top-level docs/ post-#81 consolidation.
    for name in sorted(docs):
        src_path = src.parent / "docs" / name
        dst_path = out_dir / "references" / "docs" / name
        text = _read_text(src_path)
        banner = BANNER_TMPL.format(rel=f"docs/{name}")
        _write_text(dst_path, banner + _rewrite_for_standalone(text))


def _agent_description(agent_name: str) -> str:
    return AGENT_DESCRIPTIONS.get(
        agent_name,
        f"IDD shared agent prompt for {agent_name.replace('-', ' ')} workflows.",
    )


def _render_agent_definition(agent_name: str, source_text: str, source_rel: str) -> str:
    """Render a Claude Code subagent definition from a shared agent prompt.

    Claude Code loads subagents from Markdown files with YAML frontmatter.
    Only name and description are required; omitting tools lets the agent
    inherit the caller's tool set, matching the current shared-agent prompts.
    """
    frontmatter = (
        "---\n"
        f"name: {agent_name}\n"
        f"description: {json.dumps(_agent_description(agent_name))}\n"
        "---\n"
    )
    marker = (
        f"<!-- Managed by IDD installer. Generated from /{source_rel}. "
        "Do not edit installed copies; edit source and run ./scripts/build.sh. -->\n"
    )
    return frontmatter + "\n" + marker + BANNER_TMPL.format(rel=source_rel) + source_text


def _emit_repo_root_skills(repo_root: Path, out_skills: Path) -> None:
    """Mirror flattened skills to repo-root skills/ for ASM repo URL installs.

    ASM's standard repository installer discovers skills from top-level
    skills/<name>/ directories. Keep src/ as the authoring tree and dist/skills/
    for backward-compatible subpath installs, then publish the same
    self-contained skill packages at repo root so users can run:

      asm install https://github.com/luongnv89/idd

    and select all or any specific skill using ASM's built-in picker.
    """
    root_skills = repo_root / "skills"
    if root_skills.exists():
        shutil.rmtree(root_skills)
    shutil.copytree(out_skills, root_skills)


def _emit_standalone_agents(src: Path, out_dir: Path) -> None:
    """Emit installable Claude Code agent definitions under dist/agents/."""
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    shared_src = src / "shared" / "agents"
    if not shared_src.is_dir():
        return
    for f in _walk_files(shared_src):
        if f.suffix != ".md":
            continue
        agent_name = f.stem
        rel = f"src/shared/agents/{f.name}"
        text = _read_text(f)
        _write_text(out_dir / f.name, _render_agent_definition(agent_name, text, rel))


# --- Phase E — Sanity scan over emitted output -------------------------------


def _scan_dist_skills(out_skills: Path) -> None:
    """Verify no unresolved logical refs in dist/skills/."""
    for skill_dir in _sorted_iterdir(out_skills):
        if not skill_dir.is_dir():
            continue
        for f in _walk_files(skill_dir):
            if not _is_text_file(f):
                continue
            text = _read_text(f)
            cleaned = _strip_urls(text)
            if SKILL_TOKEN_RE.search(cleaned):
                _abort(f"unresolved {{{{skill:...}}}} in {f.relative_to(out_skills.parent)}")
            if SHARED_AGENT_RE.search(cleaned):
                _abort(
                    f"unresolved bare 'shared/agents/X.md' in "
                    f"{f.relative_to(out_skills.parent)}"
                )
            if RUNTIME_DOC_RE.search(cleaned):
                _abort(f"unresolved bare 'docs/Y.md' in {f.relative_to(out_skills.parent)}")
            if BARE_SKILL_PATH_RE.search(cleaned):
                _abort(
                    f"unresolved bare 'skills/<name>/SKILL.md' in "
                    f"{f.relative_to(out_skills.parent)}"
                )


def _scan_dist_agents(out_agents: Path) -> None:
    """Verify dist/agents/ contains valid Claude Code subagent definitions."""
    if not out_agents.is_dir():
        _abort(f"dist/agents/ missing at {out_agents}")
    for f in _walk_files(out_agents):
        if f.suffix != ".md":
            _abort(f"non-markdown file under dist/agents/: {f.name}")
        text = _read_text(f)
        if not text.startswith("---\n"):
            _abort(f"agent missing YAML frontmatter: {f.relative_to(out_agents.parent)}")
        if f"name: {f.stem}" not in text.split("---", 2)[1]:
            _abort(f"agent frontmatter name mismatch: {f.relative_to(out_agents.parent)}")
        if "description:" not in text.split("---", 2)[1]:
            _abort(f"agent missing description: {f.relative_to(out_agents.parent)}")


# --- Orchestration -----------------------------------------------------------


def _check_python_version() -> None:
    if sys.version_info < (3, 11):
        sys.exit(f"build.py requires Python 3.11+ (running {sys.version.split()[0]})")


def build(out: Path, src: Path, *, verbose: bool = False, no_root_skills: bool = False) -> None:
    if verbose:
        print(f"● Building from {src} to {out}")

    # Phase A: inventory.
    _check_non_markdown_in(src / "shared" / "agents", "src/shared/agents/")
    # Issue #81: runtime docs live at top-level docs/. Project docs (in
    # subdirs like decisions/, experiments/, release-notes/) coexist there
    # but are not bundled into skills, so only top-level .md files are
    # required to be markdown — recursion off.
    _check_non_markdown_in(src.parent / "docs", "docs/", recursive=False)
    public_skills = _discover_public_skills(src)
    deprecated_distributed = _discover_distributed_deprecated(src)
    if verbose:
        print(f"  ✓ public skills: {len(public_skills)} ({', '.join(public_skills)})")
        if deprecated_distributed:
            print(f"  ✓ deprecated (distributed): {', '.join(deprecated_distributed)}")

    # Phase E (early): stale-URL checks before any output is written.
    _check_stale_doc_urls(src)
    _check_init_template_urls(src)

    # Prepare output dirs (clean only the trees we own).
    out_skills = out / "skills"
    out_agents = out / "agents"
    if out_skills.exists():
        shutil.rmtree(out_skills)
    out_skills.mkdir(parents=True)

    # Phase B + C: closures + flattened emission.
    all_skill_sources = [(name, src / "skills" / name) for name in public_skills]
    for name in deprecated_distributed:
        all_skill_sources.append((name, src / "deprecated-skills" / name))
    for skill_name, skill_root in sorted(all_skill_sources, key=lambda x: x[0]):
        agents, docs = _compute_closure(src, skill_name, skill_root)
        _emit_flattened_skill(src, skill_root, out_skills / skill_name, agents, docs)
        if verbose:
            print(f"  ✓ flattened: {skill_name} (agents={len(agents)}, docs={len(docs)})")

    # Repo-root skills/ mirror. Prefer ./scripts/build.sh (build → verify →
    # promote). Use --no-root-skills when emitting only to <out>/skills/.
    repo_root = src.parent
    if not no_root_skills:
        _emit_repo_root_skills(repo_root, out_skills)
        if verbose:
            print("  ✓ root skills mirror: skills/")

    # Standalone Claude Code subagents. These are committed beside
    # dist/skills/ so the from-source installer can register subagent types.
    _emit_standalone_agents(src, out_agents)
    if verbose:
        agent_count = len(list(out_agents.glob("*.md"))) if out_agents.is_dir() else 0
        print(f"  ✓ agents: {agent_count}")

    # Phase E (post): scan emitted output.
    _scan_dist_skills(out_skills)
    _scan_dist_agents(out_agents)

    if verbose:
        print(f"✓ build complete")


def main(argv: list[str]) -> int:
    _check_python_version()
    parser = argparse.ArgumentParser(
        description="Build IDD distribution outputs (skills/, dist/skills/, and dist/agents/)."
    )
    parser.add_argument(
        "--out",
        default="dist",
        help="Output root directory (default: dist).",
    )
    parser.add_argument(
        "--src",
        default="src",
        help="Source root directory (default: src).",
    )
    parser.add_argument(
        "--no-root-skills",
        action="store_true",
        help="Do not copy output into repo-root skills/ (use ./scripts/build.sh for verify-then-promote).",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)
    no_root_skills = args.no_root_skills
    out = Path(args.out).resolve()
    src = Path(args.src).resolve()
    if not src.is_dir():
        print(f"✗ src not found: {src}", file=sys.stderr)
        return 1
    try:
        build(out, src, verbose=args.verbose, no_root_skills=no_root_skills)
    except BuildError:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
