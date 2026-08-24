#!/usr/bin/env python3
"""Transitive dependency closure discovery for authored skills."""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path

from .common import (
    BARE_SKILL_PATH_RE,
    RUNTIME_DOC_RE,
    SHARED_AGENT_RE,
    SHARED_SCRIPT_RE,
    SKILL_TOKEN_RE,
    _abort,
    _is_text_file,
    _read_text,
    _strip_urls,
    _walk_files,
)


def _scan_logical_refs(text: str) -> tuple[set[str], set[str], set[str], set[str]]:
    """Return skill, agent, runtime-doc, and script references outside URLs."""
    cleaned = _strip_urls(text)
    return (
        set(SKILL_TOKEN_RE.findall(cleaned)),
        set(SHARED_AGENT_RE.findall(cleaned)),
        set(RUNTIME_DOC_RE.findall(cleaned)),
        set(SHARED_SCRIPT_RE.findall(cleaned)),
    )


@dataclass
class ClosureState:
    """Mutable traversal state owned by one closure computation."""

    agents: set[str] = field(default_factory=set)
    docs: set[str] = field(default_factory=set)
    scripts: set[str] = field(default_factory=set)
    visited: set[str] = field(default_factory=set)
    active: set[str] = field(default_factory=set)


class ClosureWalker:
    """Resolve one skill's logical references with explicit traversal inputs."""

    def __init__(self, src: Path, skill_name: str, state: ClosureState) -> None:
        self.src = src
        self.skill_name = skill_name
        self.state = state

    def resolve(self, kind: str, name: str) -> Path | None:
        if kind == "agent":
            path = self.src / "shared" / "agents" / name
        elif kind == "script":
            path = self.src / "shared" / "scripts" / name
        else:
            path = self.src.parent / "docs" / name
        return path if path.is_file() else None

    def visit(
        self,
        kind: str,
        name: str,
        path_chain: list[str],
        bundle: bool,
    ) -> None:
        key = f"{kind}:{name}:{int(bundle)}"
        if key in self.state.active:
            chain = " -> ".join(path_chain + [key])
            print(f"⚠ cycle detected: {chain}", file=sys.stderr)
            return
        if key in self.state.visited:
            return

        resolved = self.resolve(kind, name)
        if resolved is None:
            _abort(
                f"unresolved {kind} reference '{name}' "
                f"(reachable from skill '{self.skill_name}')"
            )

        self.state.active.add(key)
        if kind == "agent":
            self.state.agents.add(name)
        elif kind == "script" and bundle:
            self.state.scripts.add(name)
        elif kind == "doc" and bundle:
            self.state.docs.add(name)

        if kind != "script":
            text = _read_text(resolved)
            _, sub_agents, sub_docs, sub_scripts = _scan_logical_refs(text)
            next_chain = path_chain + [key]
            for agent in sorted(sub_agents):
                self.visit("agent", agent, next_chain, False)
            for doc in sorted(sub_docs):
                self.visit("doc", doc, next_chain, bundle and kind != "agent")
            for script in sorted(sub_scripts):
                self.visit("script", script, next_chain, bundle and kind != "agent")

        self.state.active.discard(key)
        self.state.visited.add(key)


def _compute_closure(
    src: Path,
    skill_name: str,
    skill_root: Path,
) -> tuple[set[str], set[str], set[str]]:
    """Compute the deterministic agent, doc, and script closure for a skill."""
    state = ClosureState()
    walker = ClosureWalker(src=src, skill_name=skill_name, state=state)
    seed_agents: set[str] = set()
    seed_docs: set[str] = set()
    seed_scripts: set[str] = set()

    for path in _walk_files(skill_root):
        if not _is_text_file(path):
            continue
        text = _read_text(path)
        _, agents, docs, scripts = _scan_logical_refs(text)
        seed_agents.update(agents)
        seed_docs.update(docs)
        seed_scripts.update(scripts)
        if BARE_SKILL_PATH_RE.search(_strip_urls(text)):
            _abort(
                "illegal bare 'skills/<name>/SKILL.md' reference in source: "
                f"{path.relative_to(src.parent)} (use {{{{skill:<name>}}}} token)"
            )

    origin = [f"skill:{skill_name}"]
    for agent in sorted(seed_agents):
        walker.visit("agent", agent, origin, False)
    for doc in sorted(seed_docs):
        walker.visit("doc", doc, origin, True)
    for script in sorted(seed_scripts):
        walker.visit("script", script, origin, True)

    return state.agents, state.docs, state.scripts
