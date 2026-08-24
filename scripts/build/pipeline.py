#!/usr/bin/env python3
"""Phase-oriented orchestration for deterministic IDD distribution builds."""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

from .agents import (
    _emit_pi_agents,
    _emit_standalone_agents,
    _load_conventions_sections,
)
from .closure import _compute_closure
from .common import CONFIG_SCHEMA_DOC, SOURCE_SKILL_MD
from .doc_slimming import (
    _check_digest_coverage,
    _zero_mention_bundled_docs,
    _zero_mention_bundled_scripts,
)
from .emit import _emit_flattened_skill, _emit_repo_root_skills
from .inventory import (
    _check_non_markdown_in,
    _discover_distributed_deprecated,
    _discover_public_skills,
)
from .validation import (
    _check_init_template_urls,
    _check_precheck_drift,
    _check_script_requirements,
    _check_stale_doc_urls,
    _scan_dist_agents,
    _scan_dist_skills,
    _scan_pi_agents,
)
from .yaml_config import (
    _check_init_template_schema_parity,
    _documented_config_defaults,
)


def _inventory_phase(src: Path, verbose: bool) -> tuple[list[str], list[str]]:
    _check_non_markdown_in(src / "shared" / "agents", "src/shared/agents/")
    _check_non_markdown_in(src.parent / "docs", "docs/", recursive=False)
    public_skills = _discover_public_skills(src)
    deprecated = _discover_distributed_deprecated(src)
    if verbose:
        print(f"  ✓ public skills: {len(public_skills)} ({', '.join(public_skills)})")
        if deprecated:
            print(f"  ✓ deprecated (distributed): {', '.join(deprecated)}")
    return public_skills, deprecated


def _source_validation_phase(
    src: Path,
    verbose: bool,
) -> tuple[dict[str, object] | None, dict[str, str] | None]:
    _check_stale_doc_urls(src)
    _check_init_template_urls(src)
    _check_init_template_schema_parity(src)
    _check_digest_coverage(src, src.parent)
    config_schema = src.parent / "docs" / CONFIG_SCHEMA_DOC
    config_defaults = (
        _documented_config_defaults(config_schema) if config_schema.is_file() else None
    )
    conventions = _load_conventions_sections(src.parent)
    if verbose and conventions is not None:
        print(f"  ✓ conventions preamble: {len(conventions)} sections inlined per agent")
    return config_defaults, conventions


def _prepare_output_phase(out: Path) -> tuple[Path, Path]:
    out_skills = out / "skills"
    out_agents = out / "agents"
    if out_skills.exists():
        shutil.rmtree(out_skills)
    out_skills.mkdir(parents=True)
    return out_skills, out_agents


def _all_skill_sources(
    src: Path,
    public_skills: list[str],
    deprecated: list[str],
) -> list[tuple[str, Path]]:
    sources = [(name, src / "skills" / name) for name in public_skills]
    sources.extend((name, src / "deprecated-skills" / name) for name in deprecated)
    return sorted(sources, key=lambda item: item[0])


def _emit_skills_phase(
    src: Path,
    out_skills: Path,
    public_skills: list[str],
    deprecated: list[str],
    conventions: dict[str, str] | None,
    config_defaults: dict[str, object] | None,
    verbose: bool,
) -> None:
    public_skill_set = set(public_skills)
    for skill_name, skill_root in _all_skill_sources(src, public_skills, deprecated):
        agents, docs, scripts = _compute_closure(src, skill_name, skill_root)
        out_skill_dir = out_skills / skill_name
        _emit_flattened_skill(
            src,
            skill_root,
            out_skill_dir,
            agents,
            docs,
            scripts,
            conventions,
            config_defaults,
        )
        for unused in _zero_mention_bundled_docs(skill_root, docs):
            print(
                f"⚠ skill '{skill_name}' bundles docs/{unused} but no runtime "
                "instruction references it (only its index/precheck entry)",
                file=sys.stderr,
            )
        for unused in _zero_mention_bundled_scripts(skill_root, scripts):
            print(
                f"⚠ skill '{skill_name}' bundles the script {unused} but no "
                "runtime instruction references it (only its index/precheck entry)",
                file=sys.stderr,
            )
        if skill_name in public_skill_set:
            _check_precheck_drift(
                skill_name,
                skill_root / SOURCE_SKILL_MD,
                out_skill_dir,
            )
        _check_script_requirements(skill_name, out_skill_dir, scripts)
        if verbose:
            print(
                f"  ✓ flattened: {skill_name} (agents={len(agents)}, "
                f"docs={len(docs)}, scripts={len(scripts)})"
            )


def _emit_agents_phase(
    src: Path,
    out_agents: Path,
    conventions: dict[str, str] | None,
    verbose: bool,
) -> Path:
    _emit_standalone_agents(src, out_agents, conventions)
    if verbose:
        count = len(list(out_agents.glob("*.md"))) if out_agents.is_dir() else 0
        print(f"  ✓ agents: {count}")
    repo_root = src.parent
    pi_agents = repo_root / ".pi" / "agents"
    _emit_pi_agents(src, repo_root, conventions)
    if verbose:
        count = len(list(pi_agents.glob("*.md"))) if pi_agents.is_dir() else 0
        print(f"  ✓ pi agents: {count} → .pi/agents/")
    return pi_agents


def _scan_output_phase(out_skills: Path, out_agents: Path, pi_agents: Path) -> None:
    _scan_dist_skills(out_skills)
    _scan_dist_agents(out_agents)
    _scan_pi_agents(pi_agents)


def build(
    out: Path,
    src: Path,
    *,
    verbose: bool = False,
    no_root_skills: bool = False,
) -> None:
    if verbose:
        print(f"● Building from {src} to {out}")
    public_skills, deprecated = _inventory_phase(src, verbose)
    config_defaults, conventions = _source_validation_phase(src, verbose)
    out_skills, out_agents = _prepare_output_phase(out)
    _emit_skills_phase(
        src, out_skills, public_skills, deprecated, conventions, config_defaults, verbose
    )
    if not no_root_skills:
        _emit_repo_root_skills(src.parent, out_skills)
        if verbose:
            print("  ✓ root skills mirror: skills/")
    pi_agents = _emit_agents_phase(src, out_agents, conventions, verbose)
    _scan_output_phase(out_skills, out_agents, pi_agents)
    if verbose:
        print("✓ build complete")
