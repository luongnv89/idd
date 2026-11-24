#!/usr/bin/env python3
# gi-requires: references/docs/config-schema.md
"""Resolve the effective IDD Stack configuration and print it as one JSON line.

Every skill starts by merging the documented defaults with the repository's
`.idd.yml`. Doing that by reading prose is where drift creeps in: a default
gets restated in six skills and one of them goes stale. This script instead
*derives* the defaults from the canonical schema document at run time — there is
no defaults table in this file, on purpose — validates the user's overrides
against it, and emits the merged result.

Output on success is exactly one line of JSON on stdout:

    {"config": {"<dotted.key>": <value>, ...},
     "config_file": ".idd.yml" or null,
     "first_run": true or false}

Unknown-key policy. The schema handed to this script may be the complete
document or a per-skill excerpt carrying only the sections that skill reads, so
"this key is not in the schema" has two very different meanings:

  * a key inside a section the schema *does* document is a typo — exit 3;
  * a key in a section the schema never shows is simply out of view. It is
    passed through into `config` and reported on stderr, because refusing to
    start over a section the caller was never given would stop every skill.
    When the schema is the complete document (it still carries the Config
    Section Map, which the per-skill excerpt drops) an unknown section is a
    typo and does fail;
  * a key the schema tombstones as *(removed)* is dropped with a warning — the
    documentation deprecated it, so an untouched old `.idd.yml` must not
    become a hard stop.

The `agents` section gets two extra steps. Every non-null `agents.*` value must
be a short opaque token (letters, digits and `._:/[]-`), else exit 3. After the
merge a null `agents.<knob>.<role>` is filled from `agents.<knob>.default`, so a
caller reads one key per role; all-null means "inherit the main agent".

The `compaction` section (issue #540) gets a value guard the type check cannot
give it: every accepted `compaction.threshold.<skill>` must be an integer from
1 to 99 (a percent of context remaining) and `compaction.enabled` a boolean,
else exit 3. Like the agents guard it runs whether or not the section is in
view.

`review.merge_method` (issue #564) is an enum the type check cannot see: an
accepted value outside squash, merge and rebase is exit 3, in view or not.

`triage.route.label_prefix` (issue #647) becomes part of a label that
/issue-triage --route puts on a `gh` command line, so an accepted value must be
1-39 characters, start with a letter or digit, and hold only letters, digits
and `._:-` (fullmatch), else exit 3, in view or not. 39 keeps the longest
route label within GitHub's 50-character limit; a leading `-` would read as a
flag. `triage.route.questions` is passed to `gi-route.py --enabled` as separate
words, so it must be a non-empty list of distinct strings that each fullmatch `[a-z]+`,
else exit 3, in view or not; gi-route.py owns which ids exist and are required.

`resolver.plan_approval` is an enum the type check cannot see: an accepted
value outside auto and human is exit 3, in view or not. `resolver.claim_label`
is put on `gh issue edit --add-label/--remove-label` and passed to
`gi-plan.py --claim-label`, so an accepted value must be the empty string (the
claim is off) or 1-50 characters that start with a letter or digit and hold
only letters, digits and `._:-` (fullmatch), else exit 3, in view or not.

Legacy name (issue #537). With no `--config`, `.idd.yml` in the working
directory is read; when it is absent the pre-rename `.gitissue.yml` is read in
its place (`first_run` false, `config_file` naming it) with
`⚠ legacy .gitissue.yml found — rename to .idd.yml` on stderr. When both exist
`.idd.yml` wins and the legacy file is reported as ignored.

Reading a git ref (`--ref REF`). A repository's `.idd.yml` decides how strict a
review of that repository is, so a reviewer with a pull request's branch checked
out would otherwise let the branch set the gates that judge it. With `--ref` the
config is read from the blob `<REF>:.idd.yml` (else the legacy
`<REF>:.gitissue.yml`, with a ⚠ line) and the work tree is never read. REF is
resolved to one commit first, and every read goes through that commit's id:

  * a 40- or 64-character lowercase hex object id must name a commit, and
    `HEAD` is the commit checked out;
  * any other REF must pass `git check-ref-format --allow-onelevel`, so
    revision syntax (`~`, `^`, `:`, `@{...}`) is refused: git would look the
    name inside it up again;
  * a `refs/...` name must be listed exactly by `git for-each-ref`. When it is
    not, git's lookup falls through to `refs/heads/refs/...`, a local branch a
    checked-out pull request can create;
  * a short name must match exactly one of git's five short-name lookup forms,
    because `refs/heads/<name>` shadows `refs/remotes/<name>`; a short name
    containing `/` must match `refs/remotes/<name>` itself;
  * the commit is the object id that `for-each-ref` row carries, never git's
    own lookup of the name, which tries a `$GIT_DIR/<name>` file first.

An empty or `-`-prefixed REF is exit 2. A REF that does not resolve, is
ambiguous or breaks a rule above, or a config blob that exists but cannot be
read, is exit 4. A REF that resolves and carries no config yields the
built-in defaults (`config_file` null, `first_run` true), never the work-tree
file. An invalid config at REF is exit 3. Under `--ref` the schema is the
copy bundled beside this script or `--schema`; the working-directory walk is
skipped, because the checked-out tree would choose it.

`--compare-ref REF2` (only with `--ref`) also reads REF2's config, raw, and
reports `changed_keys`: the sorted dotted keys, in any section, that are added,
removed or hold a different raw value at REF2 than at REF. A key set explicitly
to its default counts. REF2 is never merged or validated, and a failure to
resolve, read or parse it never fails the run: the exit stays 0 with REF's
config, `changed_keys: null` and `compare_error` naming the reason.

Under `--ref` the payload adds `config_source: "ref:<REF as passed>"` — the
`ref:` form of the vocabulary gi-secscan's `policy_source` uses (`ref:<REF>`,
`file:<path>`, `defaults`) — and under `--compare-ref` also `changed_keys` and
`compare_error`. Without `--ref` the payload is exactly the three keys above.

Exit codes
  0  merged config printed
  2  usage error
  3  `.idd.yml` is invalid (stderr: `✗ Invalid .idd.yml: <key> — <why>`)
  4  cannot complete — schema missing/unparsable, the config file could not
     be read, or `--ref` did not resolve to exactly one commit (stderr:
     `⚠ gi-config: <reason>`). Callers fall back to their inline defaults
     rather than failing the run.

Authored at src/shared/scripts/gi-config.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

SCHEMA_NAME = "config-schema.md"
DEFAULT_CONFIG_NAME = ".idd.yml"
LEGACY_CONFIG_NAME = ".gitissue.yml"

# A full object id, SHA-1 or SHA-256. Matched with `fullmatch`, so a trailing
# newline or an abbreviation is not an object id.
_OID_RE = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")

# git's lookup order for a short `<refname>`, minus rule 1
# (`$GIT_DIR/<refname>`): `for-each-ref` never lists that file, and it is kept
# out by reading through the listed ref's object id rather than by name. Copied
# from gi-secscan.py, which resolves `--policy-ref` the same way; scripts ship
# standalone, so it is copied rather than imported.
_REF_LOOKUP_RULES = (
    "refs/{ref}",
    "refs/tags/{ref}",
    "refs/heads/{ref}",
    "refs/remotes/{ref}",
    "refs/remotes/{ref}/HEAD",
)

# `git rev-parse --show-cdup` can only ever be empty or a run of `../`. Anything
# else is not an answer this script will resolve a path against.
_CDUP_RE = re.compile(r"^(\.\./)*$")

# --- Vendored config parsing -------------------------------------------------
#
# These four definitions are a deliberate verbatim copy of the restricted-YAML
# parser in scripts/build.py. This script ships inside installed skills, where
# the build tree does not exist, so it cannot import from it; the copy is kept
# behavior-identical instead and a test asserts both parsers agree on the
# canonical schema and template files.

_FULL_SCHEMA_FENCE_RE = re.compile(
    r"^## Full Schema \(advanced reference\).*?^```yaml\n(.*?)^```",
    re.MULTILINE | re.DOTALL,
)
_YAML_MAPPING_RE = re.compile(r"^(?P<indent> *)(?P<key>[A-Za-z_][A-Za-z0-9_-]*):(?:[ ]+(?P<value>.*))?$")
_YAML_LIST_RE = re.compile(r"^(?P<indent> *)- (?P<value>.*)$")

# A Defaults Table row whose first cell tombstones the key, e.g.
# `| *(removed)* `resolve.pr_auto_link` | — | Deprecated; ... |`.
_REMOVED_ROW_RE = re.compile(
    r"^\|[^|]*\(removed\)[^|]*`([A-Za-z_][A-Za-z0-9_.]*)`",
    re.MULTILINE | re.IGNORECASE,
)

# The Config Section Map diagrams the *whole* schema, so the build strips it
# when it emits a per-skill excerpt. Its presence is therefore the document's
# own signal that the section list in front of us is complete.
_SECTION_MAP_RE = re.compile(r"^#{2,4}\s+Config Section Map\s*$", re.MULTILINE)

# `.idd.yml` is repo-controlled, and an `agents.*` value travels into a
# spawn-tool parameter and a subagent prompt. The guard is a shape check only —
# the strings stay opaque to IDD — and is applied with `fullmatch`, because `$`
# would let a trailing newline through.
_AGENTS_PREFIX = "agents."
_AGENT_VALUE_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/\[\]-]{0,63}")
_AGENT_KNOBS = ("model", "effort")

# `compaction.threshold.<skill>` is a percent of context *remaining*. The schema
# documents 1-99, but its Min/Max comments are not enforced by the type check:
# 0 would never fire and 100 would fire on every step, so both are exit 3.
_COMPACTION_ENABLED = "compaction.enabled"
_COMPACTION_THRESHOLD_PREFIX = "compaction.threshold."
_COMPACTION_MIN = 1
_COMPACTION_MAX = 99

# The value becomes a `gh pr merge --<method>` flag, so it is one of three
# words or the config is invalid.
_MERGE_METHOD = "review.merge_method"
_MERGE_METHODS = ("squash", "merge", "rebase")

# The prefix is joined to a route word and substituted into `gh issue edit
# --add-label` and `gh label create`, so it is shape-checked like an agents
# value: a letter or digit first (no flag-like `-x`), fullmatch (no trailing
# newline), and at most 39 characters so `{prefix}needs-human` fits GitHub's
# 50-character label limit.
_ROUTE_PREFIX = "triage.route.label_prefix"
_ROUTE_PREFIX_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,38}")
# The question ids become separate words of `gi-route.py --enabled`, so each
# is a bare lowercase word; gi-route.py decides which ids are known.
_ROUTE_QUESTIONS = "triage.route.questions"
_ROUTE_QUESTION_RE = re.compile(r"[a-z]+")
# The plan-approval mode is one of two words. The claim label reaches `gh issue
# edit` and `gi-plan.py --claim-label` as a shell word, so it is shape-checked
# like the route prefix; "" turns the claim off. 50 is GitHub's label limit.
_PLAN_APPROVAL = "resolver.plan_approval"
_PLAN_APPROVALS = ("auto", "human")
_CLAIM_LABEL = "resolver.claim_label"
_CLAIM_LABEL_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,49}")


class ConfigError(Exception):
    """`.idd.yml` is invalid — exit 3."""


class Unavailable(Exception):
    """The script cannot complete; the caller should fall back — exit 4."""


class ParseError(Exception):
    """The restricted-YAML parser met syntax it does not support."""


class UsageError(Exception):
    """A malformed invocation — exit 2."""


def _parse_yaml_scalar(value: str) -> object:
    """Parse the restricted scalar syntax used by the canonical config files.

    This deliberately accepts mappings, block lists, quoted strings, booleans,
    integers, null, and init-template replacement tokens; unsupported YAML
    raises rather than silently producing a wrong value.
    """
    value = value.strip()
    if value.startswith('"'):
        try:
            return json.loads(value)
        except json.JSONDecodeError as exc:
            raise ParseError(f"invalid quoted YAML scalar: {value!r} ({exc.msg})") from exc
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    if value == "true":
        return True
    if value == "false":
        return False
    if value == "null":
        return None
    if re.fullmatch(r"-?[0-9]+", value):
        return int(value)
    if re.fullmatch(r"\{[a-z_]+\}", value):
        return value
    if value and not any(char in value for char in "[]{}#,\t"):
        return value
    raise ParseError(f"unsupported YAML scalar: {value!r}")


def _parse_config_mapping(text: str, label: str) -> dict[str, object]:
    """Flatten the project's restricted YAML config syntax into dotted keys."""
    result: dict[str, object] = {}
    parents: list[tuple[int, str]] = []
    pending_lists: list[tuple[int, str]] = []

    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue
        mapping = _YAML_MAPPING_RE.fullmatch(raw_line)
        if mapping:
            indent = len(mapping.group("indent"))
            key = mapping.group("key")
            value = mapping.group("value")
            while parents and parents[-1][0] >= indent:
                parents.pop()
            while pending_lists and pending_lists[-1][0] >= indent:
                pending_lists.pop()
            path = ".".join([part for _, part in parents] + [key])
            if value is None:
                parents.append((indent, key))
                pending_lists.append((indent, path))
            else:
                result[path] = _parse_yaml_scalar(value)
            continue

        list_item = _YAML_LIST_RE.fullmatch(raw_line)
        if list_item:
            indent = len(list_item.group("indent"))
            candidates = [entry for entry in pending_lists if entry[0] < indent]
            if not candidates:
                raise ParseError(f"invalid YAML list item in {label}:{line_number}")
            path = candidates[-1][1]
            result.setdefault(path, [])
            if not isinstance(result[path], list):
                raise ParseError(
                    f"mixed YAML container types for {path} in {label}:{line_number}"
                )
            result[path].append(_parse_yaml_scalar(list_item.group("value")))
            continue

        raise ParseError(f"unsupported YAML syntax in {label}:{line_number}: {raw_line!r}")
    return result


# --- Schema ------------------------------------------------------------------


def search_ceiling() -> Path:
    """The highest directory an upward search may look in.

    The top of the working tree, or the working directory itself when there is
    none. Without a ceiling an upward walk leaves the repository entirely, and
    then a file in `$HOME` — or in whatever directory the checkout happens to
    sit under — governs the run. gi-secscan bounds its `.idd.yml` search
    the same way and for the same reason: a `security.allow_pattern` an
    ancestor directory can set is a security gate an ancestor directory can
    switch off. The two searches are kept identical on purpose; letting them
    diverge would be worse than either gap.
    """
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--show-cdup"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return Path.cwd().resolve()
    cdup = proc.stdout.rstrip("\n")
    if proc.returncode != 0 or not _CDUP_RE.match(cdup):
        return Path.cwd().resolve()
    # `--show-cdup` is empty or a run of `../` — never the repository's own name,
    # whose trailing bytes are as attacker-controlled as any other path's.
    return Path(os.path.normpath(os.path.join(os.getcwd(), cdup))) if cdup else Path.cwd().resolve()


def find_schema(explicit: str | None, allow_walk: bool = True) -> Path:
    """Locate the schema document: explicit path, bundled copy, then repo tree.

    `allow_walk` is False under `--ref`: the schema decides which keys are
    valid, and the working directory then holds the branch under review.
    """
    if explicit:
        path = Path(explicit)
        if not path.is_file():
            raise Unavailable(f"schema not found: {explicit}")
        return path
    # Installed layout: this script sits at references/scripts/, the schema at
    # references/docs/ of the same skill.
    bundled = Path(__file__).resolve().parent.parent / "docs" / SCHEMA_NAME
    if bundled.is_file():
        return bundled
    if not allow_walk:
        raise Unavailable(
            f"no {SCHEMA_NAME} beside this script; under --ref the working "
            "directory is not searched (pass --schema)"
        )
    # Source tree: walk up from the working directory, stopping at the top of
    # the working tree. A schema above the repository is not this repository's
    # schema, and it decides which keys are valid and which are tombstoned.
    cwd = Path.cwd().resolve()
    ceiling = search_ceiling().resolve()
    for base in (cwd, *cwd.parents):
        candidate = base / "docs" / SCHEMA_NAME
        if candidate.is_file():
            return candidate
        if base == ceiling:
            break
    raise Unavailable(
        f"no {SCHEMA_NAME} beside this script or between the working directory "
        "and the top of the working tree (pass --schema)"
    )


def load_schema(path: Path) -> tuple[dict[str, object], frozenset[str], bool]:
    """Return (documented defaults, tombstoned keys, schema-is-complete)."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise Unavailable(f"cannot read {path}: {exc}") from exc
    except UnicodeDecodeError as exc:
        # UnicodeDecodeError subclasses ValueError, not OSError, so it escapes
        # the clause above. The schema is a bundled dependency, not user input:
        # an undecodable one is a broken install, so the caller falls back.
        raise Unavailable(f"{path} is not valid UTF-8 — {exc.reason}") from exc
    match = _FULL_SCHEMA_FENCE_RE.search(text)
    if match is None:
        raise Unavailable(f"{path} has no Full Schema YAML block")
    try:
        defaults = _parse_config_mapping(match.group(1), str(path))
    except ParseError as exc:
        raise Unavailable(f"cannot parse the schema defaults — {exc}") from exc
    removed = frozenset(_REMOVED_ROW_RE.findall(text))
    return defaults, removed, _SECTION_MAP_RE.search(text) is not None


# --- User configuration ------------------------------------------------------


def _flatten(mapping: dict, prefix: str = "") -> dict[str, object]:
    """Flatten a nested mapping into dotted keys, matching the schema's form."""
    out: dict[str, object] = {}
    for key, value in mapping.items():
        dotted = f"{prefix}{key}"
        if isinstance(value, dict):
            out.update(_flatten(value, dotted + "."))
        else:
            out[dotted] = value
    return out


def load_user_config(path: Path) -> dict[str, object]:
    """Read the user's config file and parse it into dotted keys."""
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise Unavailable(f"cannot read {path}: {exc}") from exc
    return parse_user_config(data, str(path))


def parse_user_config(data: bytes, label: str) -> dict[str, object]:
    """Parse config bytes — a file's or a blob's — into dotted keys.

    PyYAML is used when the interpreter has it and the restricted parser is the
    fallback, so a config using YAML this project's own parser does not model
    still loads wherever possible. When neither can read it the caller degrades
    (exit 4) rather than declaring the file invalid — a parser limitation is not
    a user error.
    """
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        # UnicodeDecodeError subclasses ValueError, not OSError, so it escapes
        # the clause above and would leave the interpreter to print a traceback
        # and exit 1 — a code outside this script's 0/2/3/4 contract, which
        # callers read as "degrade", silently discarding the repo's real config.
        # The file was found and read: its *bytes* are wrong, which is a user
        # error (an editor saving cp1252), so it is exit 3, stop and report.
        raise ConfigError(
            f"{label} is not valid UTF-8 — {exc.reason} at byte {exc.start}; "
            "re-save the file as UTF-8"
        ) from exc
    try:
        import yaml  # type: ignore[import-not-found]
    except ImportError:
        pass
    else:
        try:
            loaded = yaml.safe_load(text)
        except yaml.YAMLError as exc:
            raise ConfigError(f"{label} is not valid YAML — {exc}") from exc
        if loaded is None:
            return {}
        if not isinstance(loaded, dict):
            raise ConfigError(f"{label} must contain a mapping at the top level")
        return _flatten(loaded)
    try:
        return _parse_config_mapping(text, label)
    except ParseError as exc:
        raise Unavailable(
            f"cannot parse {label} without PyYAML — {exc}"
        ) from exc


# --- Reading a git ref -------------------------------------------------------


def _git(args: list[str]) -> subprocess.CompletedProcess:
    """Run one read-only git command with replace objects ignored.

    `--no-replace-objects` is a top-level option (a subcommand rejects it): a
    `refs/replace` entry could otherwise swap the commit or blob this read
    reports for one that never shipped.
    """
    try:
        return subprocess.run(
            ["git", "--no-replace-objects", *args],
            capture_output=True,
            check=False,
            env={**os.environ, "LC_ALL": "C"},
        )
    except (OSError, ValueError) as exc:  # git missing, or a bad argv
        raise Unavailable(f"cannot run git — {exc}") from exc


def _commit_of(spec: str) -> str | None:
    """The commit id `spec` peels to, or None when it names no commit."""
    proc = _git(["rev-parse", "--verify", "--quiet", "--end-of-options", f"{spec}^{{commit}}"])
    oid = proc.stdout.decode("ascii", errors="replace").strip()
    return oid if proc.returncode == 0 and _OID_RE.fullmatch(oid) else None


def check_ref_arg(flag: str, ref: str) -> None:
    """Reject a value that is not a revision at all — exit 2."""
    if not ref:
        raise UsageError(f"{flag} value must not be empty")
    if ref.startswith("-"):
        # It would reach git as an option, not a revision.
        raise UsageError(f"{flag} value must be a revision, not an option: {ref!r}")


def _is_ref_name(ref: str) -> bool:
    """True when `git check-ref-format --allow-onelevel` accepts `ref`.

    That rejects revision syntax — `~`, `^`, `:`, `@{`, `..`, a lone `@` — which
    git would resolve by looking the name inside it up again by itself.
    """
    return _git(["check-ref-format", "--allow-onelevel", ref]).returncode == 0


def resolve_ref(flag: str, ref: str) -> str:
    """Resolve `ref` to exactly one commit id, or raise Unavailable — exit 4.

    A ref name is a search to git, and a checked-out pull request can write a
    ref that wins it: a local branch `origin/main` (tried before
    `refs/remotes/origin/main`), a local `refs/heads/refs/remotes/origin/main`
    (tried when the remote ref is missing), a revision suffix that git looks up
    again, or a `$GIT_DIR/origin/main` file (tried first). So the name is
    checked against what `git for-each-ref` lists, and the object id that
    listing carries is the answer — the name is never resolved by git:

      1. A 40- or 64-hex object id must name a commit; `HEAD` is the commit
         checked out.
      2. Anything else must pass `git check-ref-format --allow-onelevel`.
      3. A `refs/...` name must be listed exactly as itself. A short name must
         match exactly one of git's five lookup forms; two is ambiguous. A
         short name containing `/` must match `refs/remotes/<ref>` — a local
         branch or tag of that name is refused even when it is the only match.
    """
    if _OID_RE.fullmatch(ref):
        oid = _commit_of(ref)
        if oid is None:
            raise Unavailable(f"{flag} {ref} names no commit in this repository")
        return oid
    if ref == "HEAD":
        oid = _commit_of(ref)
        if oid is None:
            raise Unavailable(f"{flag} HEAD does not resolve to a commit")
        return oid
    if not _is_ref_name(ref):
        raise Unavailable(
            f"{flag} {ref} is not a ref name — revision syntax such as ~, ^, : "
            "or @{...} is looked up by git again and could reach a branch the "
            "checked-out pull request wrote; pass the ref itself or a commit id"
        )
    if ref.startswith("refs/"):
        candidates = [ref]
    else:
        candidates = [rule.format(ref=ref) for rule in _REF_LOOKUP_RULES]
    listed = _git(["for-each-ref", "--format=%(refname)%00%(objectname)", "--", *candidates])
    if listed.returncode != 0:
        raise Unavailable(f"cannot list refs to check {flag} {ref}")
    # Exact membership: a for-each-ref pattern also matches anything below
    # it, which is not a ref this lookup would reach.
    rows = {}
    for line in os.fsdecode(listed.stdout).split("\n"):
        name, sep, oid = line.partition("\0")
        if sep and name in candidates:
            rows[name] = oid
    found = [name for name in candidates if name in rows]
    if len(found) > 1:
        raise Unavailable(
            f"{flag} {ref} is ambiguous — it names "
            + ", ".join(sorted(found))
            + "; pass the fully-qualified name of the one you mean"
        )
    if not found:
        raise Unavailable(
            f"{flag} {ref} is not an existing ref — pass a ref "
            "`git for-each-ref` lists, or a commit id"
        )
    if "/" in ref and not ref.startswith("refs/") and found[0] != f"refs/remotes/{ref}":
        raise Unavailable(
            f"{flag} {ref} names {found[0]}, not refs/remotes/{ref} — a short "
            "name containing / must be a remote-tracking ref; pass the "
            "fully-qualified name to use any other"
        )
    oid = _commit_of(rows[found[0]])
    if oid is None:
        raise Unavailable(f"{flag} {ref} does not resolve to a commit")
    return oid


def _read_blob(oid: str, name: str) -> bytes | None:
    """The bytes of `<oid>:<name>`, or None when no such path exists there.

    Raises Unavailable when the path exists but is not a readable blob — a
    tree, or a blob a partial clone never fetched — so an unreadable config is
    never mistaken for an absent one.
    """
    spec = f"{oid}:{name}"
    if _git(["rev-parse", "--verify", "--quiet", spec]).returncode != 0:
        return None
    proc = _git(["cat-file", "blob", spec])
    if proc.returncode != 0:
        raise Unavailable(f"{name} exists at {oid} but could not be read")
    return proc.stdout


def read_ref_config(oid: str) -> tuple[bytes | None, str | None]:
    """(config bytes, the name read) at `oid`; (None, None) when it has none.

    The legacy name is read only when `.idd.yml` is absent: a present but
    unreadable `.idd.yml` has already raised.
    """
    data = _read_blob(oid, DEFAULT_CONFIG_NAME)
    if data is not None:
        return data, DEFAULT_CONFIG_NAME
    data = _read_blob(oid, LEGACY_CONFIG_NAME)
    if data is not None:
        return data, LEGACY_CONFIG_NAME
    return None, None


def changed_keys(base: dict[str, object], other: dict[str, object]) -> list[str]:
    """Dotted keys added, removed or holding a different raw value.

    Values are compared by their JSON form, so `true` and `1` differ (Python's
    `True == 1` would hide that change).
    """
    def form(value: object) -> str:
        return json.dumps(value, sort_keys=True, default=str)

    return sorted(
        key
        for key in set(base) | set(other)
        if key not in base or key not in other or form(base[key]) != form(other[key])
    )


def compare_overrides(
    ref2: str, base: dict[str, object]
) -> tuple[list[str] | None, str | None]:
    """(changed_keys, None), or (None, reason) when REF2 cannot be compared.

    Every failure here is reported, never raised: REF2 is the side under
    review, and its config being unreadable must not stop the review.
    """
    try:
        oid = resolve_ref("--compare-ref", ref2)
        data, name = read_ref_config(oid)
        other = {} if data is None else parse_user_config(data, f"{ref2}:{name}")
    except (Unavailable, ConfigError) as exc:
        return None, str(exc).replace("\n", "; ")
    return changed_keys(base, other), None


# --- Validation and merge ----------------------------------------------------


def _type_problem(value: object, default: object) -> str | None:
    """Describe how `value` violates the documented default's type, or None."""
    if isinstance(default, bool):
        return None if isinstance(value, bool) else "must be true or false"
    if isinstance(default, int):
        ok = isinstance(value, int) and not isinstance(value, bool)
        return None if ok else "must be an integer"
    if isinstance(default, str):
        return None if isinstance(value, str) else "must be a string"
    if isinstance(default, list):
        return None if isinstance(value, list) else "must be a list"
    if default is None:
        # A documented `null` default pins no type — it means "unset" (a board
        # number or nothing). Only a container is clearly wrong.
        ok = value is None or isinstance(value, (int, float, str))
        return None if ok else "must be a scalar or null"
    return None


def merge(
    defaults: dict[str, object],
    overrides: dict[str, object],
    removed: frozenset[str],
    complete: bool,
) -> tuple[dict[str, object], list[str]]:
    """Validate overrides against the schema and merge them onto the defaults.

    Returns (merged config, warnings). Raises ConfigError listing every problem
    at once, so a user fixes one round of errors rather than one error.
    """
    sections = {key.split(".", 1)[0] for key in defaults}
    accepted: dict[str, object] = {}
    warnings: list[str] = []
    errors: list[str] = []
    out_of_view: dict[str, int] = {}

    for key in sorted(overrides):
        value = overrides[key]
        section = key.split(".", 1)[0]
        if key in removed:
            warnings.append(f"{key} was removed from the schema — ignoring it")
            continue
        if key in defaults:
            problem = _type_problem(value, defaults[key])
            if problem is None:
                accepted[key] = value
            else:
                errors.append(f"{key} — {problem}")
            continue
        if section not in sections:
            if complete:
                errors.append(f"{key} — unknown configuration section '{section}'")
            else:
                # Grouped into one line: a per-skill excerpt legitimately hides
                # most of the file, and one warning per hidden key would bury
                # the warnings that matter.
                out_of_view[section] = out_of_view.get(section, 0) + 1
                accepted[key] = value
            continue
        errors.append(f"{key} — not a documented key of section '{section}'")

    if out_of_view:
        listed = ", ".join(f"{name} ({n})" for name, n in sorted(out_of_view.items()))
        warnings.append(
            "section(s) outside this schema view, passed through unvalidated: " + listed
        )

    # Guarded on every accepted `agents.*` key, in view or not: a per-skill
    # excerpt that hides the section must not also hide the value guard.
    for key in sorted(accepted):
        value = accepted[key]
        if not key.startswith(_AGENTS_PREFIX) or value is None:
            continue
        if not isinstance(value, str) or _AGENT_VALUE_RE.fullmatch(value) is None:
            errors.append(
                f"{key} — must be null or a string of 1-64 letters, digits and "
                "._:/[]- that starts with a letter or digit"
            )

    # Same scope as the agents guard: every accepted `compaction.*` key, in view
    # or not. An in-view value of the wrong type was already refused above and
    # never reaches `accepted`, so nothing is reported twice.
    for key in sorted(accepted):
        value = accepted[key]
        if key == _COMPACTION_ENABLED:
            if not isinstance(value, bool):
                errors.append(f"{key} — must be true or false")
        elif key.startswith(_COMPACTION_THRESHOLD_PREFIX):
            is_int = isinstance(value, int) and not isinstance(value, bool)
            if not is_int or not _COMPACTION_MIN <= value <= _COMPACTION_MAX:
                errors.append(
                    f"{key} — must be an integer from {_COMPACTION_MIN} to "
                    f"{_COMPACTION_MAX} (percent of context remaining)"
                )

    if _MERGE_METHOD in accepted and accepted[_MERGE_METHOD] not in _MERGE_METHODS:
        errors.append(f"{_MERGE_METHOD} — must be one of: " + ", ".join(_MERGE_METHODS))

    if _ROUTE_PREFIX in accepted:
        prefix = accepted[_ROUTE_PREFIX]
        if not isinstance(prefix, str) or _ROUTE_PREFIX_RE.fullmatch(prefix) is None:
            errors.append(
                f"{_ROUTE_PREFIX} — must be 1-39 letters, digits and ._:- that "
                "starts with a letter or digit"
            )

    if _ROUTE_QUESTIONS in accepted:
        ids = accepted[_ROUTE_QUESTIONS]
        if (
            not isinstance(ids, list)
            or not ids
            or not all(isinstance(i, str) and _ROUTE_QUESTION_RE.fullmatch(i) for i in ids)
            or len(set(ids)) != len(ids)
        ):
            errors.append(
                f"{_ROUTE_QUESTIONS} — must be a non-empty list of distinct lowercase-letter ids"
            )

    if _PLAN_APPROVAL in accepted and accepted[_PLAN_APPROVAL] not in _PLAN_APPROVALS:
        errors.append(f"{_PLAN_APPROVAL} — must be one of: " + ", ".join(_PLAN_APPROVALS))

    if _CLAIM_LABEL in accepted:
        label = accepted[_CLAIM_LABEL]
        if not isinstance(label, str) or (label and _CLAIM_LABEL_RE.fullmatch(label) is None):
            errors.append(
                f"{_CLAIM_LABEL} — must be \"\" or 1-50 letters, digits and ._:- that "
                "starts with a letter or digit"
            )

    merged = {**defaults, **accepted}
    # Default fill: a null `agents.<knob>.<role>` takes `agents.<knob>.default`,
    # so an orchestrator reads exactly one key per role.
    for knob in _AGENT_KNOBS:
        prefix = f"{_AGENTS_PREFIX}{knob}."
        fallback = merged.get(prefix + "default")
        if fallback is None:
            continue
        for key in merged:
            if key.startswith(prefix) and merged[key] is None:
                merged[key] = fallback
    phrase_weight = merged.get("duplicate_detection.weights.phrase")
    overlap_weight = merged.get("duplicate_detection.weights.title_overlap")
    if (
        isinstance(phrase_weight, int)
        and not isinstance(phrase_weight, bool)
        and isinstance(overlap_weight, int)
        and not isinstance(overlap_weight, bool)
        and phrase_weight < overlap_weight
    ):
        errors.append(
            "duplicate_detection.weights.phrase — must be greater than or equal "
            "to duplicate_detection.weights.title_overlap"
        )
    if errors:
        raise ConfigError("\n".join(errors))
    return merged, warnings


# --- CLI ---------------------------------------------------------------------


def load_from_ref(args: argparse.Namespace) -> tuple[dict[str, object], list[str], dict[str, object]]:
    """Merge the config at `--ref` (never the work tree's) onto the defaults.

    Returns (config, warnings, the payload's file/source/compare fields).
    """
    oid = resolve_ref("--ref", args.ref)
    data, name = read_ref_config(oid)
    if name == LEGACY_CONFIG_NAME:
        print(
            f"⚠ legacy {LEGACY_CONFIG_NAME} found at {args.ref} — rename to {DEFAULT_CONFIG_NAME}",
            file=sys.stderr,
        )
    overrides = {} if data is None else parse_user_config(data, f"{args.ref}:{name}")
    defaults, removed, complete = load_schema(find_schema(args.schema, allow_walk=False))
    config, warnings = merge(defaults, overrides, removed, complete)
    fields: dict[str, object] = {
        "config_file": name,
        "config_source": f"ref:{args.ref}",
        "first_run": data is None,
    }
    if args.compare_ref is not None:
        keys, error = compare_overrides(args.compare_ref, overrides)
        fields["changed_keys"] = keys
        fields["compare_error"] = error
    return config, warnings, fields


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-config.py",
        description=(
            "Merge the documented IDD Stack defaults with the repository's "
            f"{DEFAULT_CONFIG_NAME} and print the result as one JSON line."
        ),
        epilog=(
            "Exit codes: 0 ok; 2 usage; 3 invalid config; 4 cannot complete "
            "(caller falls back to its inline defaults). With --ref the payload "
            "adds config_source (ref:<REF>), and with --compare-ref also "
            "changed_keys and compare_error."
        ),
    )
    parser.add_argument(
        "--config",
        default=DEFAULT_CONFIG_NAME,
        help=(
            f"config file to read (default: {DEFAULT_CONFIG_NAME}, else the legacy "
            f"{LEGACY_CONFIG_NAME}, relative to cwd); not with --ref"
        ),
    )
    parser.add_argument(
        "--schema",
        default=None,
        help=(
            f"{SCHEMA_NAME} to derive defaults from (default: the copy bundled "
            "beside this script, then — without --ref only — the nearest one "
            "above the working directory)"
        ),
    )
    parser.add_argument(
        "--key",
        default=None,
        metavar="DOTTED",
        help="print only this dotted key's value, as raw JSON",
    )
    parser.add_argument(
        "--ref",
        default=None,
        metavar="REF",
        help=(
            f"read <REF>:{DEFAULT_CONFIG_NAME} (else <REF>:{LEGACY_CONFIG_NAME}) "
            "instead of the work tree: a full commit id, HEAD, an existing "
            "refs/... name, or a short name naming exactly one ref (with a /, "
            "the remote-tracking one); no revision syntax; no config there = "
            "defaults"
        ),
    )
    parser.add_argument(
        "--compare-ref",
        default=None,
        metavar="REF2",
        help=(
            "with --ref: also list in changed_keys every dotted key added, "
            "removed or changed at REF2; a REF2 that cannot be read sets "
            "changed_keys null and compare_error, never a non-zero exit"
        ),
    )
    args = parser.parse_args(argv)

    explicit_config = args.config != DEFAULT_CONFIG_NAME
    try:
        if args.compare_ref is not None and args.ref is None:
            raise UsageError("--compare-ref needs --ref")
        if args.ref is not None:
            if explicit_config:
                raise UsageError("--config cannot be combined with --ref")
            check_ref_arg("--ref", args.ref)
        if args.compare_ref is not None:
            check_ref_arg("--compare-ref", args.compare_ref)
    except UsageError as exc:
        parser.error(str(exc))

    if args.ref is not None:
        try:
            config, warnings, fields = load_from_ref(args)
        except ConfigError as exc:
            for line in str(exc).splitlines():
                print(f"✗ Invalid config at {args.ref}: {line}", file=sys.stderr)
            return 3
        except Unavailable as exc:
            print(f"⚠ gi-config: {exc}", file=sys.stderr)
            return 4
        return emit(args, config, warnings, fields)

    config_path = Path(args.config)
    # The name an exit-3 message blames: the file actually parsed.
    config_name = DEFAULT_CONFIG_NAME
    if not explicit_config:
        legacy_path = Path(LEGACY_CONFIG_NAME)
        if config_path.is_file():
            if legacy_path.is_file():
                print(
                    f"⚠ legacy {LEGACY_CONFIG_NAME} ignored — {DEFAULT_CONFIG_NAME} takes precedence",
                    file=sys.stderr,
                )
        elif legacy_path.is_file():
            print(
                f"⚠ legacy {LEGACY_CONFIG_NAME} found — rename to {DEFAULT_CONFIG_NAME}",
                file=sys.stderr,
            )
            config_path = legacy_path
            config_name = LEGACY_CONFIG_NAME
    try:
        defaults, removed, complete = load_schema(find_schema(args.schema))
        if config_path.is_file():
            overrides = load_user_config(config_path)
        elif explicit_config:
            raise Unavailable(f"config file not found: {args.config}")
        else:
            overrides = {}
        config, warnings = merge(defaults, overrides, removed, complete)
    except ConfigError as exc:
        for line in str(exc).splitlines():
            print(f"✗ Invalid {config_name}: {line}", file=sys.stderr)
        return 3
    except Unavailable as exc:
        print(f"⚠ gi-config: {exc}", file=sys.stderr)
        return 4

    return emit(
        args,
        config,
        warnings,
        {
            "config_file": str(config_path) if config_path.is_file() else None,
            "first_run": not config_path.is_file(),
        },
    )


def emit(
    args: argparse.Namespace,
    config: dict[str, object],
    warnings: list[str],
    fields: dict[str, object],
) -> int:
    """Print the warnings, then the payload (or the one `--key` value)."""
    for warning in warnings:
        print(f"⚠ gi-config: {warning}", file=sys.stderr)

    if args.key is not None:
        if args.key not in config:
            print(f"✗ gi-config: unknown key '{args.key}'", file=sys.stderr)
            return 2
        print(json.dumps(config[args.key], sort_keys=True))
        return 0

    payload = {"config": config, **fields}
    sys.stdout.write(json.dumps(payload, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
