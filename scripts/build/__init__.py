"""IDD build package and explicit compatibility facade for ``build.py``."""

# Every imported name below is intentionally re-exported through __all__.
# ruff: noqa: F401

from __future__ import annotations

from .agents import (
    _agent_description,
    _emit_pi_agents,
    _emit_standalone_agents,
    _extract_doc_section,
    _inline_agent_conventions,
    _load_conventions_sections,
    _pi_display_name_from_source,
    _render_agent_body,
    _render_agent_definition,
    _render_conventions_preamble,
    _render_pi_agent_definition,
)
from .cli import _check_python_version, main
from .closure import _compute_closure, _scan_logical_refs
from .common import (
    AGENT_DESCRIPTIONS,
    ANY_SHARED_SCRIPT_RE,
    BANNER_TMPL,
    BARE_SKILL_PATH_RE,
    CONFIG_SCHEMA_DOC,
    CONFIG_SECTIONS_ALWAYS,
    CONVENTIONS_DOC,
    CONVENTIONS_PREAMBLE_HEADING,
    CONVENTIONS_SECTIONS_ALL,
    CONVENTIONS_SECTIONS_REVIEW,
    DOC_DIGEST_OPTIONAL_SECTIONS,
    DOC_SECTION_DIGESTS,
    FULL_CONFIG_SCHEMA_SKILLS,
    OUTPUT_SKILL_MD,
    PRECHECK_HEADING_RE,
    PRECHECK_REF_RE,
    RUNTIME_DOC_RE,
    SCRIPT_TOKEN_NAMES_A_FILE_RE,
    SHARED_AGENT_RE,
    SHARED_SCRIPT_RE,
    SKILL_TOKEN_RE,
    SOURCE_SKILL_MD,
    STALE_DOC_URL_RE,
    TEXT_EXTS,
    URL_RE,
    BuildError,
    _CONFIG_EXCERPT_NOTICE,
    _CONFIG_SECTION_MAP_RE,
    _DEFAULTS_TABLE_ROW_RE,
    _DIGEST_GENERIC_HEADINGS,
    _DIGEST_NOTICE,
    _DOC_SECTION_RE_TMPL,
    _DYNAMIC_TEMPLATE_DEFAULTS,
    _FENCE_MARKER,
    _FIRST_H2_RE,
    _FULL_ACCESS_AGENTS,
    _FULL_SCHEMA_FENCE_RE,
    _PI_READONLY_PREAMBLE,
    _PI_TOOLS_FULL_ACCESS,
    _PI_TOOLS_READ_ONLY,
    _PROMPT_FENCE_RE,
    _PROMPT_HEADING_RE,
    _REPO_BLOB_BASE,
    _REVIEW_AGENTS,
    _SCRIPT_REQUIRES_RE,
    _TOP_LEVEL_YAML_KEY_RE,
    _YAML_LIST_RE,
    _YAML_MAPPING_RE,
    _abort,
    _copy_binary,
    _is_text_file,
    _read_text,
    _sorted_iterdir,
    _strip_urls,
    _walk_files,
    _write_text,
)
from .doc_slimming import (
    _check_config_excerpt_coverage,
    _check_digest_coverage,
    _config_schema_excerpt,
    _config_sections_used,
    _doc_digest,
    _filter_defaults_table,
    _section_names,
    _shared_doc_headings,
    _slim_doc_for_skill,
    _split_config_blocks,
    _split_h2_sections,
    _strip_bibliography_blocks,
    _zero_mention_bundled_docs,
    _zero_mention_bundled_scripts,
)
from .emit import _emit_flattened_skill, _emit_repo_root_skills
from .inventory import (
    _check_non_markdown_in,
    _discover_distributed_deprecated,
    _discover_public_skills,
)
from .pipeline import build
from .rewriting import (
    _rewrite_for_agent_prompt,
    _rewrite_for_standalone,
    _rewrite_url_aware,
)
from .validation import (
    _bundled_reference_paths,
    _check_init_template_urls,
    _check_precheck_drift,
    _check_script_requirements,
    _check_stale_doc_urls,
    _parse_precheck_refs,
    _scan_dist_agents,
    _scan_dist_skills,
    _scan_pi_agents,
)
from .yaml_config import (
    _check_init_template_schema_parity,
    _documented_config_defaults,
    _parse_config_mapping,
    _parse_yaml_scalar,
)

# This is intentionally the old build.py API, not every name imported by the
# package implementation. The compatibility shim uses it verbatim.
__all__ = [
    name
    for name in globals()
    if not name.startswith("__") and name not in {"annotations"}
]
