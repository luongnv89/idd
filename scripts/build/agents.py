#!/usr/bin/env python3
"""Shared-agent prompt rendering and standalone agent emission."""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path

from .common import (
    AGENT_DESCRIPTIONS,
    BANNER_TMPL,
    CONVENTIONS_DOC,
    CONVENTIONS_PREAMBLE_HEADING,
    CONVENTIONS_SECTIONS_ALL,
    CONVENTIONS_SECTIONS_REVIEW,
    _CONVENTIONS_PREAMBLE_INTRO,
    _DOC_SECTION_RE_TMPL,
    _FENCE_MARKER,
    _FIRST_H2_RE,
    _FULL_ACCESS_AGENTS,
    _PI_READONLY_PREAMBLE,
    _PI_TOOLS_FULL_ACCESS,
    _PI_TOOLS_READ_ONLY,
    _PROMPT_FENCE_RE,
    _PROMPT_HEADING_RE,
    _REVIEW_AGENTS,
    _abort,
    _read_text,
    _walk_files,
    _write_text,
)
from .rewriting import _rewrite_for_agent_prompt


def _extract_doc_section(text: str, heading: str) -> str:
    """Return the body of the `## <heading>` section of a markdown document.

    Returns an empty string when the heading is absent or its body is blank —
    the caller turns either into a build abort. Deliberately exact-match on the
    heading line so a renamed section fails the build loudly instead of
    silently emitting a shorter preamble.
    """
    pattern = re.compile(
        _DOC_SECTION_RE_TMPL.format(heading=re.escape(heading)),
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(text)
    if match is None:
        return ""
    return match.group("body").strip()


def _load_conventions_sections(repo_root: Path) -> dict[str, str] | None:
    """Parse the inlinable sections out of docs/shared-agent-conventions.md.

    Returns None when the document does not exist at all (synthetic build
    fixtures legitimately ship a docs/ tree without it); in the real repo every
    shared agent references the document, so a missing file already aborts the
    closure. When the document *is* present, every section named in
    CONVENTIONS_SECTIONS_ALL / CONVENTIONS_SECTIONS_REVIEW must resolve to a
    non-empty body or the build aborts — an empty preamble must never ship
    silently.
    """
    doc = repo_root / "docs" / CONVENTIONS_DOC
    if not doc.is_file():
        return None
    text = _read_text(doc)
    sections: dict[str, str] = {}
    for heading in CONVENTIONS_SECTIONS_ALL + CONVENTIONS_SECTIONS_REVIEW:
        body = _extract_doc_section(text, heading)
        if not body:
            _abort(
                f"docs/{CONVENTIONS_DOC} is missing the '## {heading}' section "
                "(or its body is empty) — the inlined shared-agent conventions "
                "preamble cannot be generated. Restore the heading or update "
                "CONVENTIONS_SECTIONS_ALL/REVIEW in scripts/build.py."
            )
        # An inlined body is spliced *inside* the ``` fence of the
        # code-reviewer / fixer / ui-reviewer prompts. A fence marker in the
        # body would close that fence early and silently truncate the injected
        # prompt, so reject it at parse time rather than shipping it.
        if _FENCE_MARKER in body:
            _abort(
                f"docs/{CONVENTIONS_DOC} section '## {heading}' contains a "
                "``` code fence. Inlined sections are spliced inside the "
                "agents' ``` prompt fence, where a nested fence would close it "
                "early and truncate the injected prompt. Use indented code or "
                "move the example to a non-inlined section."
            )
        sections[heading] = body
    return sections


def _render_conventions_preamble(agent_name: str, sections: dict[str, str]) -> str:
    """Compose the inlined conventions block for one agent.

    Section order is the fixed order of the CONVENTIONS_SECTIONS_* tuples, so
    the output is byte-deterministic. Review agents additionally carry the
    shared confidence scale.
    """
    headings = list(CONVENTIONS_SECTIONS_ALL)
    if agent_name in _REVIEW_AGENTS:
        headings.extend(CONVENTIONS_SECTIONS_REVIEW)
    parts = [f"{CONVENTIONS_PREAMBLE_HEADING}\n\n{_CONVENTIONS_PREAMBLE_INTRO}\n"]
    for heading in headings:
        parts.append(f"\n### {heading}\n\n{sections[heading]}\n")
    return "".join(parts)


def _inline_agent_conventions(
    agent_name: str, text: str, sections: dict[str, str] | None
) -> str:
    """Splice the conventions preamble into a shared-agent prompt (issue #245).

    Insertion point depends on the agent's shape:

      * Agents with a `## Prompt` fenced block (code-reviewer, fixer,
        ui-reviewer) get the preamble *inside* the fence, because the
        orchestrator injects only the fence body.
      * Agents without one (the whole file is the prompt) get it immediately
        before their first `## ` section.

    An agent that declares `## Prompt` but whose fence does not parse aborts the
    build: the fallback would place the preamble *before* `## Contract`, outside
    the only region the orchestrator injects, so the conventions would silently
    never reach the subagent — the exact failure issue #245 exists to fix.
    """
    if sections is None:
        return text
    preamble = _render_conventions_preamble(agent_name, sections)
    fence = _PROMPT_FENCE_RE.search(text)
    if fence is not None:
        return text[: fence.end()] + preamble + "\n" + text[fence.end() :]
    if _PROMPT_HEADING_RE.search(text):
        _abort(
            f"src/shared/agents/{agent_name}.md has a '## Prompt' section but no "
            "parsable opening ``` fence, so the inlined conventions preamble "
            "would land outside the injected prompt body and never reach the "
            "subagent. Restore the fenced block or update _PROMPT_FENCE_RE in "
            "scripts/build.py."
        )
    first_h2 = _FIRST_H2_RE.search(text)
    if first_h2 is not None:
        return text[: first_h2.start()] + preamble + "\n" + text[first_h2.start() :]
    return text.rstrip("\n") + "\n\n" + preamble


def _render_agent_body(
    agent_name: str, source_text: str, sections: dict[str, str] | None
) -> str:
    """Inline the conventions, then rewrite references to absolute repo URLs."""
    return _rewrite_for_agent_prompt(
        _inline_agent_conventions(agent_name, source_text, sections)
    )


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


def _emit_standalone_agents(
    src: Path, out_dir: Path, conventions: dict[str, str] | None = None
) -> None:
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
        text = _render_agent_body(agent_name, _read_text(f), conventions)
        _write_text(out_dir / f.name, _render_agent_definition(agent_name, text, rel))


def _pi_display_name_from_source(source_text: str, agent_name: str) -> str:
    """Role-only label for pi-subagents UI (no historical persona names)."""
    for line in source_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("# "):
            return stripped[2:].strip()
    return agent_name.replace("-", " ").title()


def _render_pi_agent_definition(agent_name: str, source_text: str, source_rel: str) -> str:
    """Render a @tintinweb/pi-subagents agent file from a shared agent prompt."""
    display_name = _pi_display_name_from_source(source_text, agent_name)
    tools = (
        _PI_TOOLS_FULL_ACCESS
        if agent_name in _FULL_ACCESS_AGENTS
        else _PI_TOOLS_READ_ONLY
    )
    frontmatter = (
        "---\n"
        f"description: {json.dumps(_agent_description(agent_name))}\n"
        f"display_name: {json.dumps(display_name)}\n"
        f"tools: {tools}\n"
        "prompt_mode: replace\n"
        "skills: true\n"
        "---\n"
    )
    marker = (
        f"<!-- Managed by IDD installer (pi-subagents). Generated from /{source_rel}. "
        "Do not edit installed copies; edit source and run ./scripts/build.sh. -->\n"
    )
    body = source_text
    if agent_name not in _FULL_ACCESS_AGENTS:
        body = _PI_READONLY_PREAMBLE + body
    return frontmatter + "\n" + marker + BANNER_TMPL.format(rel=source_rel) + body


def _emit_pi_agents(
    src: Path, repo_root: Path, conventions: dict[str, str] | None = None
) -> None:
    """Emit pi-subagents agent definitions under .pi/agents/ (project-local)."""
    out_dir = repo_root / ".pi" / "agents"
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
        text = _render_agent_body(agent_name, _read_text(f), conventions)
        _write_text(
            out_dir / f.name,
            _render_pi_agent_definition(agent_name, text, rel),
        )
