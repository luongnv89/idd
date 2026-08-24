#!/usr/bin/env python3
"""Pre-emission validators and post-emission sanity scans."""

from __future__ import annotations

import re
from pathlib import Path

from .common import (
    ANY_SHARED_SCRIPT_RE,
    BARE_SKILL_PATH_RE,
    PRECHECK_HEADING_RE,
    PRECHECK_REF_RE,
    RUNTIME_DOC_RE,
    SCRIPT_TOKEN_NAMES_A_FILE_RE,
    SHARED_AGENT_RE,
    SHARED_SCRIPT_RE,
    SKILL_TOKEN_RE,
    SOURCE_SKILL_MD,
    STALE_DOC_URL_RE,
    _SCRIPT_REQUIRES_RE,
    _abort,
    _is_text_file,
    _read_text,
    _sorted_iterdir,
    _strip_urls,
    _walk_files,
)


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


def _parse_precheck_refs(skill_source_text: str) -> set[str] | None:
    """Extract the references/ paths named in a skill's 'Bundled dependency
    precheck' section.

    Returns a set of references/<path> tokens, or None when the skill has no
    precheck section (such skills are not policed). The section is bounded from
    its heading to the next top-level '## ' heading or '---' rule, so inline
    references/ mentions elsewhere in the skill (e.g. an Additional Resources
    index or prose) are never captured. Both authoring styles are supported: a
    bulleted list with trailing descriptions and a bare ```text fence with one
    path per line.
    """
    lines = skill_source_text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if PRECHECK_HEADING_RE.match(line):
            start = i + 1
            break
    if start is None:
        return None
    body: list[str] = []
    for line in lines[start:]:
        if re.match(r"^\s*##\s", line) or re.match(r"^\s*---\s*$", line):
            break
        body.append(line)
    return set(PRECHECK_REF_RE.findall("\n".join(body)))


def _bundled_reference_paths(out_skill_dir: Path) -> set[str]:
    """Return every bundled references/ file under an emitted skill directory
    as skill-relative POSIX paths (e.g. 'references/docs/config-schema.md')."""
    refs_root = out_skill_dir / "references"
    if not refs_root.is_dir():
        return set()
    return {
        f.relative_to(out_skill_dir).as_posix()
        for f in _walk_files(refs_root)
    }


def _check_precheck_drift(
    skill_name: str, skill_source: Path, out_skill_dir: Path
) -> None:
    """Fail the build when a skill's bundled-dependency precheck list diverges
    from the files actually bundled under its references/ tree.

    Scope is references/ only — README.md and templates/ are intentionally not
    policed here (the precheck may name required templates, but templates are
    not part of the closure-driven references/ bundle this guard verifies).
    Skills without a precheck section are skipped.
    """
    named = _parse_precheck_refs(_read_text(skill_source))
    if named is None:
        return
    bundled = _bundled_reference_paths(out_skill_dir)
    missing_from_list = sorted(bundled - named)
    stale_in_list = sorted(named - bundled)
    if not missing_from_list and not stale_in_list:
        return
    details = []
    if missing_from_list:
        details.append(
            "bundled but not in precheck list: " + ", ".join(missing_from_list)
        )
    if stale_in_list:
        details.append(
            "in precheck list but not bundled: " + ", ".join(stale_in_list)
        )
    _abort(
        f"bundled-dependency precheck drift in skill '{skill_name}' — "
        + " | ".join(details)
        + f" (fix the 'Bundled dependency precheck' list in "
        f"src/skills/{skill_name}/{SOURCE_SKILL_MD})"
    )


def _check_script_requirements(
    skill_name: str, out_skill_dir: Path, scripts: set[str]
) -> None:
    """A shipped script may declare the bundled files it reads at run time with
    a `# gi-requires: references/...` header. Every declaration must resolve
    inside the same skill's bundle, or the script silently degrades forever."""
    bundled = _bundled_reference_paths(out_skill_dir)
    for name in sorted(scripts):
        path = out_skill_dir / "references" / "scripts" / name
        text = path.read_text(encoding="utf-8", errors="replace")
        for req in sorted(set(_SCRIPT_REQUIRES_RE.findall(text))):
            if req not in bundled:
                _abort(
                    f"script '{name}' in skill '{skill_name}' declares "
                    f"'gi-requires: {req}' but that file is not bundled — "
                    f"cite its source document from the skill's runtime prose"
                )


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
            if SHARED_SCRIPT_RE.search(cleaned):
                _abort(
                    f"unresolved bare 'shared/scripts/X.py' in "
                    f"{f.relative_to(out_skills.parent)}"
                )
            for stray_script in ANY_SHARED_SCRIPT_RE.finditer(cleaned):
                if not SCRIPT_TOKEN_NAMES_A_FILE_RE.match(stray_script.group(1)):
                    continue  # prose about the directory, not an instruction
                # \S+ is deliberately greedy so nothing escapes detection; trim
                # the markdown delimiters it swallows before reporting.
                token = stray_script.group(0).rstrip("`'\".,;:)]}>")
                _abort(
                    f"unrewritable bare shared-script token "
                    f"'{token}' in "
                    f"{f.relative_to(out_skills.parent)} — the closure resolves "
                    f"only lowercase hyphenated '.py' names, so this one was "
                    f"never bundled and would ship as a dead instruction"
                )
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


def _scan_pi_agents(pi_agents: Path) -> None:
    """Verify .pi/agents/ contains valid pi-subagents definitions."""
    if not pi_agents.is_dir():
        _abort(f".pi/agents/ missing at {pi_agents}")
    for f in _walk_files(pi_agents):
        if f.suffix != ".md":
            _abort(f"non-markdown file under .pi/agents/: {f.name}")
        text = _read_text(f)
        if not text.startswith("---\n"):
            _abort(f"pi agent missing YAML frontmatter: {f.name}")
        fm = text.split("---", 2)[1]
        if "display_name:" not in fm:
            _abort(f"pi agent missing display_name: {f.name}")
        dn_line = fm.split("display_name:", 1)[-1].split("\n", 1)[0]
        if "\u2014" in dn_line or "—" in dn_line:
            _abort(
                f"pi agent display_name must be role-only (no persona em dash): {f.name}"
            )
        if "tools:" not in fm:
            _abort(f"pi agent missing tools: {f.name}")
        if "prompt_mode: replace" not in fm:
            _abort(f"pi agent must use prompt_mode: replace: {f.name}")
