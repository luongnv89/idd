#!/usr/bin/env python3
"""Per-skill runtime-document digest and config-excerpt generation."""

from __future__ import annotations

import re
from pathlib import Path

from .closure import _scan_logical_refs
from .common import (
    CONFIG_SCHEMA_DOC,
    CONFIG_SECTIONS_ALWAYS,
    DOC_DIGEST_EXPECTED_BYTES,
    DOC_DIGEST_OPTIONAL_SECTIONS,
    DOC_SECTION_DIGESTS,
    FULL_CONFIG_SCHEMA_SKILLS,
    PRECHECK_HEADING_RE,
    _CONFIG_EXCERPT_NOTICE,
    _CONFIG_SECTION_MAP_RE,
    _DEFAULTS_TABLE_ROW_RE,
    _DIGEST_GENERIC_HEADINGS,
    _DIGEST_NOTICE,
    _FULL_SCHEMA_FENCE_RE,
    _TOP_LEVEL_YAML_KEY_RE,
    _abort,
    _is_text_file,
    _read_text,
    _walk_files,
)
from .yaml_config import _parse_config_mapping


def _split_h2_sections(text: str) -> tuple[str, list[tuple[str, str]]]:
    """Split a markdown document on top-level `## ` headings.

    Returns (preamble, [(heading, block), ...]) where each block includes its own
    heading line. Fenced code blocks are skipped so a `## ` inside an example is
    never mistaken for a section boundary.
    """
    preamble: list[str] = []
    sections: list[tuple[str, list[str]]] = []
    in_fence = False
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
        elif not in_fence and line.startswith("## "):
            sections.append((line[3:].strip(), [line]))
            continue
        (sections[-1][1] if sections else preamble).append(line)
    return "".join(preamble), [(h, "".join(b)) for h, b in sections]


def _section_names(heading: str, block: str) -> set[str]:
    """The heading plus every `### ` sub-heading inside a section block."""
    return {heading} | set(re.findall(r"^### (.+?)\s*$", block, re.MULTILINE))


def _check_doc_digest_size(name: str, source: str, digest: str) -> None:
    """Fail when a measured digest footprint drifts from its reviewed budget."""
    expected = DOC_DIGEST_EXPECTED_BYTES.get(name)
    if expected is None:
        return
    measured = (len(source.encode("utf-8")), len(digest.encode("utf-8")))
    if measured != expected:
        _abort(
            f"docs/{name} digest byte-size drift: expected source={expected[0]} "
            f"bytes and digest={expected[1]} bytes; measured source={measured[0]} "
            f"bytes and digest={measured[1]} bytes. Review the digest and update "
            "DOC_DIGEST_EXPECTED_BYTES."
        )


def _doc_digest(name: str, text: str, skill_root: Path) -> str:
    """Emit the per-skill digest of a document listed in DOC_SECTION_DIGESTS."""
    keep = DOC_SECTION_DIGESTS[name]
    preamble, sections = _split_h2_sections(text)
    present = {heading for heading, _ in sections}
    missing = [heading for heading in keep if heading not in present]
    if missing:
        _abort(
            f"docs/{name} is missing digest section(s): {', '.join(missing)} "
            f"(update DOC_SECTION_DIGESTS in scripts/build.py)"
        )
    optional = frozenset(DOC_DIGEST_OPTIONAL_SECTIONS.get(name, ()))
    if optional:
        skill_text = "\n".join(
            _read_text(f) for f in _walk_files(skill_root) if _is_text_file(f)
        )
        wanted = {
            heading
            for heading, block in sections
            if heading in optional
            and any(cited in skill_text for cited in _section_names(heading, block))
        }
    else:
        wanted = set()
    kept = frozenset(keep) | wanted
    body = "\n".join(
        block.rstrip("\n") + "\n" for heading, block in sections if heading in kept
    )
    digest = (
        preamble.rstrip("\n")
        + "\n\n"
        + _DIGEST_NOTICE.format(name=name)
        + "\n"
        + body
    )
    _check_doc_digest_size(name, text, digest)
    return digest


def _shared_doc_headings(repo_root: Path, name: str) -> frozenset[str]:
    """`## ` headings docs/<name> shares with another top-level docs/*.md.

    A bare mention of one of these cannot be attributed to a document by its
    text alone. *Lint Enforcement* is a section of both pre-commit-security.md
    (digested) and sync-conventions.md (bundled whole into six skills), so a
    skill citing the second reads, to a substring scan, exactly like a skill
    citing the first.
    """
    docs_dir = repo_root / "docs"
    own = {heading for heading, _ in _split_h2_sections(_read_text(docs_dir / name))[1]}
    others: set[str] = set()
    for other in sorted(docs_dir.glob("*.md")):
        if other.name == name:
            continue
        others |= {
            heading for heading, _ in _split_h2_sections(_read_text(other))[1]
        }
    return frozenset(own & others)


def _check_digest_coverage(src: Path, repo_root: Path) -> None:
    """Abort when a skill source names a section the digest would drop.

    This is the safety net for the digests: dropping a section only stays
    correct while nothing points a skill at it by name.

    A dropped heading that another docs/*.md also uses is checked only in files
    that name the digested document as well, because those are the files whose
    mention can be attributed to it. Without that condition the scan reported
    the wrong document: naming sync-conventions' *Lint Enforcement* section
    aborted the build with a message about pre-commit-security.md and two
    remedies, neither of which applied to what the author had written.
    """
    for name, keep in sorted(DOC_SECTION_DIGESTS.items()):
        doc = repo_root / "docs" / name
        if not doc.is_file():
            continue
        _, sections = _split_h2_sections(_read_text(doc))
        kept = frozenset(keep) | frozenset(DOC_DIGEST_OPTIONAL_SECTIONS.get(name, ()))
        dropped = sorted(
            heading
            for heading, _ in sections
            if heading not in kept and heading not in _DIGEST_GENERIC_HEADINGS
        )
        if not dropped:
            continue
        ambiguous = _shared_doc_headings(repo_root, name)
        for f in _walk_files(src):
            if not _is_text_file(f):
                continue
            text = _read_text(f)
            for heading in dropped:
                if heading not in text:
                    continue
                if heading in ambiguous and name not in text:
                    continue
                _abort(
                    f"{f.relative_to(repo_root)} names "
                    f"'{heading}' — a section the docs/{name} runtime digest "
                    f"drops. Add it to DOC_SECTION_DIGESTS in "
                    f"scripts/build.py or stop citing it from a skill."
                )


def _split_config_blocks(fence_body: str) -> list[tuple[str, str]]:
    """Slice the Full Schema YAML fence into (top-level key, block) pairs.

    A block runs from the first line of the comment run introducing its
    top-level key through the line before the next block's comment run, so the
    documentation of each section travels with it.
    """
    lines = fence_body.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if _TOP_LEVEL_YAML_KEY_RE.match(line)]
    if not starts:
        _abort("Full Schema YAML block has no top-level keys")
    begins: list[int] = []
    for start in starts:
        begin = start
        while begin > 0 and lines[begin - 1].startswith("#"):
            begin -= 1
        begins.append(begin)
    blocks: list[tuple[str, str]] = []
    for index, start in enumerate(starts):
        stop = begins[index + 1] if index + 1 < len(begins) else len(lines)
        key = lines[start].split(":", 1)[0]
        blocks.append((key, "".join(lines[begins[index] : stop])))
    return blocks


def _filter_defaults_table(text: str, sections: frozenset[str], known: frozenset[str]) -> str:
    """Drop Defaults Table rows documenting a section the excerpt omits.

    Scoped to the `## Defaults Table` section: other pipe-delimited tables in
    the document (notably the `.gitissue/` directory table) must survive intact.
    Fenced code blocks are skipped, so a `## ` inside an example never flips the
    section boundary (same rule as `_split_h2_sections`).
    """
    out: list[str] = []
    in_defaults = False
    in_fence = False
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
        elif not in_fence and line.startswith("## "):
            in_defaults = line.strip() == "## Defaults Table"
        match = _DEFAULTS_TABLE_ROW_RE.match(line) if in_defaults and not in_fence else None
        if match:
            key = match.group(1).split(".", 1)[0]
            if key in known and key not in sections:
                continue
        out.append(line)
    return "".join(out)


def _config_schema_excerpt(text: str, sections: frozenset[str]) -> str:
    """Render the per-skill excerpt of docs/config-schema.md."""
    match = _FULL_SCHEMA_FENCE_RE.search(text)
    if match is None:
        _abort("config schema has no Full Schema YAML block")
    blocks = _split_config_blocks(match.group(1))
    known = frozenset(key for key, _ in blocks)
    unknown = sorted(sections - known)
    if unknown:
        _abort(f"unknown config section(s) requested for excerpt: {', '.join(unknown)}")
    fence = "".join(block for key, block in blocks if key in sections).rstrip("\n") + "\n"
    out = text[: match.start(1)] + fence + text[match.end(1) :]
    # The Config Section Map diagrams the *whole* schema; in an excerpt it would
    # advertise sections the file no longer contains.
    out = _CONFIG_SECTION_MAP_RE.sub("", out)
    out = _filter_defaults_table(out, sections, known)
    notice = _CONFIG_EXCERPT_NOTICE.format(
        sections=", ".join(f"`{name}`" for name in sorted(sections))
    )
    lines = out.splitlines(keepends=True)
    return "".join(lines[:1]) + "\n" + notice + "".join(lines[1:])


def _config_sections_used(skill_root: Path, known: frozenset[str]) -> frozenset[str]:
    """Top-level config sections a skill's own text references."""
    pattern = re.compile(
        r"(?<![\w.-])(" + "|".join(sorted(known)) + r")\.[a-z_]+"
    )
    used = set(CONFIG_SECTIONS_ALWAYS & known)
    for f in _walk_files(skill_root):
        if _is_text_file(f):
            used.update(pattern.findall(_read_text(f)))
    return frozenset(used)


def _check_config_excerpt_coverage(
    skill_name: str, skill_root: Path, excerpt: str, documented: dict[str, object]
) -> None:
    """Verify the excerpt still documents every config key the skill mentions.

    Section detection is a heuristic over prose; this closes the loop on it, so a
    skill that names a key whose section was not detected fails the build instead
    of shipping an excerpt with a hole in it.
    """
    match = _FULL_SCHEMA_FENCE_RE.search(excerpt)
    if match is None:
        _abort(f"generated config excerpt for '{skill_name}' lost its Full Schema block")
    present = set(_parse_config_mapping(match.group(1), f"{skill_name} config excerpt"))
    mentioned: set[str] = set()
    key_pattern = re.compile(
        r"(?<![\w.-])(" + "|".join(sorted(re.escape(k) for k in documented)) + r")(?![\w.-])"
    )
    for f in _walk_files(skill_root):
        if _is_text_file(f):
            mentioned.update(key_pattern.findall(_read_text(f)))
    missing = sorted(key for key in mentioned if key not in present)
    if missing:
        _abort(
            f"config excerpt for skill '{skill_name}' omits mentioned key(s): "
            + ", ".join(missing)
            + " (widen CONFIG_SECTIONS_ALWAYS or the detection in "
            "_config_sections_used, scripts/build.py)"
        )


def _slim_doc_for_skill(
    name: str,
    text: str,
    skill_name: str,
    skill_root: Path,
    config_defaults: dict[str, object] | None,
) -> str:
    """Return the per-skill bundled form of a runtime doc."""
    if name in DOC_SECTION_DIGESTS:
        return _doc_digest(name, text, skill_root)
    if (
        name == CONFIG_SCHEMA_DOC
        and skill_name not in FULL_CONFIG_SCHEMA_SKILLS
        and config_defaults
    ):
        known = frozenset(key.split(".", 1)[0] for key in config_defaults)
        excerpt = _config_schema_excerpt(text, _config_sections_used(skill_root, known))
        _check_config_excerpt_coverage(skill_name, skill_root, excerpt, config_defaults)
        return excerpt
    return text


def _zero_mention_bundled_docs(skill_root: Path, docs: set[str]) -> list[str]:
    """Bundled docs a skill's runtime instructions never point at.

    A doc reaches a skill's bundle through any `docs/X.md` token in its sources,
    including the *Additional Resources* bibliography and the *Bundled dependency
    precheck* fence — neither of which is an instruction to read the document.
    Those two blocks are stripped before the scan so a doc that survives only via
    its own index entry is reported rather than silently shipped.
    """
    mentioned: set[str] = set()
    for f in _walk_files(skill_root):
        if not _is_text_file(f):
            continue
        text = _strip_bibliography_blocks(_read_text(f))
        _, _, found, _ = _scan_logical_refs(text)
        mentioned.update(found)
    return sorted(docs - mentioned)


def _zero_mention_bundled_scripts(skill_root: Path, scripts: set[str]) -> list[str]:
    """Bundled scripts a skill's runtime instructions never point at.

    Same rule as _zero_mention_bundled_docs: a script that reaches the bundle
    only through the *Additional Resources* index or the *Bundled dependency
    precheck* fence is shipped weight nothing tells the agent to run.
    """
    mentioned: set[str] = set()
    for f in _walk_files(skill_root):
        if not _is_text_file(f):
            continue
        text = _strip_bibliography_blocks(_read_text(f))
        _, _, _, found = _scan_logical_refs(text)
        mentioned.update(found)
    return sorted(scripts - mentioned)


def _strip_bibliography_blocks(text: str) -> str:
    """Remove the precheck fence and Additional Resources index from a source."""
    out: list[str] = []
    skipping = False
    for line in text.splitlines(keepends=True):
        if PRECHECK_HEADING_RE.match(line) or re.match(
            r"^\s{0,3}#{2,4}\s+Additional Resources\s*$", line
        ):
            skipping = True
            continue
        if skipping and (re.match(r"^\s*##\s", line) or re.match(r"^\s*---\s*$", line)):
            skipping = False
        if not skipping:
            out.append(line)
    return "".join(out)
