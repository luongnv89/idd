#!/usr/bin/env python3
"""Source-tree inventory and structural checks."""

from __future__ import annotations

import re
from pathlib import Path

from .common import (
    SOURCE_SKILL_MD,
    _abort,
    _read_text,
    _sorted_iterdir,
    _walk_files,
)


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
