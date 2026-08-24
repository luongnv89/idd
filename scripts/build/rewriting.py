#!/usr/bin/env python3
"""URL-aware logical-reference rewriting for emitted artifacts."""

from __future__ import annotations

from .common import (
    RUNTIME_DOC_RE,
    SHARED_AGENT_RE,
    SHARED_SCRIPT_RE,
    SKILL_TOKEN_RE,
    URL_RE,
    _REPO_BLOB_BASE,
)


def _rewrite_for_standalone(text: str) -> str:
    """Apply standalone (dist/skills/) rewrites — URL-aware.

      {{skill:X}}            -> ../X/SKILL.md
      shared/agents/X.md     -> references/agents/X.md
      docs/Y.md              -> references/docs/Y.md
      shared/scripts/Z.py    -> references/scripts/Z.py
    """
    return _rewrite_url_aware(
        text,
        skill_form=lambda name: f"../{name}/SKILL.md",
        agent_form=lambda name: f"references/agents/{name}",
        doc_form=lambda name: f"references/docs/{name}",
        script_form=lambda name: f"references/scripts/{name}",
    )


def _rewrite_for_agent_prompt(text: str) -> str:
    """Apply agent-file rewrites — URL-aware (issue #245).

    Identical in scope to `_rewrite_for_standalone`, except every logical
    reference renders as an absolute repo URL instead of a skill-relative path.
    Agent files are injected into subagents whose working directory is the
    target repo, where `references/…` resolves to nothing.

      {{skill:X}}            -> <repo>/skills/X/SKILL.md
      shared/agents/X.md     -> <repo>/src/shared/agents/X.md
      docs/Y.md              -> <repo>/docs/Y.md
      shared/scripts/Z.py    -> <repo>/src/shared/scripts/Z.py
    """
    return _rewrite_url_aware(
        text,
        skill_form=lambda name: f"{_REPO_BLOB_BASE}skills/{name}/SKILL.md",
        agent_form=lambda name: f"{_REPO_BLOB_BASE}src/shared/agents/{name}",
        doc_form=lambda name: f"{_REPO_BLOB_BASE}docs/{name}",
        script_form=lambda name: f"{_REPO_BLOB_BASE}src/shared/scripts/{name}",
    )


def _rewrite_url_aware(text, *, skill_form, agent_form, doc_form, script_form):
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
        gap = SHARED_SCRIPT_RE.sub(lambda mm: script_form(mm.group(1)), gap)
        parts.append(gap)
        # Pass URL through unchanged.
        parts.append(m.group(0))
        cursor = m.end()
    tail = text[cursor:]
    tail = SKILL_TOKEN_RE.sub(lambda mm: skill_form(mm.group(1)), tail)
    tail = SHARED_AGENT_RE.sub(lambda mm: agent_form(mm.group(1)), tail)
    tail = RUNTIME_DOC_RE.sub(lambda mm: doc_form(mm.group(1)), tail)
    tail = SHARED_SCRIPT_RE.sub(lambda mm: script_form(mm.group(1)), tail)
    parts.append(tail)
    return "".join(parts)
