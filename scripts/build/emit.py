#!/usr/bin/env python3
"""Flattened skill emission and repo-root promotion."""

from __future__ import annotations

import shutil
from pathlib import Path

from .agents import _render_agent_body
from .common import (
    BANNER_TMPL,
    OUTPUT_SKILL_MD,
    SOURCE_SKILL_MD,
    _copy_binary,
    _is_text_file,
    _read_text,
    _walk_files,
    _write_text,
)
from .doc_slimming import _slim_doc_for_skill
from .rewriting import _rewrite_for_standalone


def _emit_flattened_skill(
    src: Path,
    skill_root: Path,
    out_dir: Path,
    agents: set[str],
    docs: set[str],
    scripts: set[str],
    conventions: dict[str, str] | None = None,
    config_defaults: dict[str, object] | None = None,
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

    # Copy transitive shared agents (banner + inlined conventions + rewrite).
    # Issue #245: agent bodies use the agent-prompt rewrite (absolute repo
    # URLs), never skill-relative paths — they are injected into subagents
    # whose working directory is the target repo.
    for name in sorted(agents):
        src_path = src / "shared" / "agents" / name
        dst_path = out_dir / "references" / "agents" / name
        text = _read_text(src_path)
        banner = BANNER_TMPL.format(rel=f"src/shared/agents/{name}")
        body = _render_agent_body(Path(name).stem, text, conventions)
        _write_text(dst_path, banner + body)

    # Copy transitive runtime docs (banner + rewrite). Runtime docs live at
    # top-level docs/ post-#81 consolidation.
    for name in sorted(docs):
        src_path = src.parent / "docs" / name
        dst_path = out_dir / "references" / "docs" / name
        text = _slim_doc_for_skill(
            name, _read_text(src_path), skill_root.name, skill_root, config_defaults
        )
        banner = BANNER_TMPL.format(rel=f"docs/{name}")
        _write_text(dst_path, banner + _rewrite_for_standalone(text))

    # Copy transitive shared scripts verbatim. No banner: a .py file has no
    # HTML comment form, and byte-identity with the source is what makes the
    # shipped copy auditable. Provenance lives in each script's docstring.
    for name in sorted(scripts):
        _copy_binary(
            src / "shared" / "scripts" / name,
            out_dir / "references" / "scripts" / name,
        )


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
