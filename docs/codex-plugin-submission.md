# Prepare IDD for Codex submission

IDD is a skills-only plugin. The packaging command builds the package; it does not
publish it or create a release tag. v0.25.0 is the first tag that carries the Codex
package, so the release-pinned catalog installs from v0.25.0 or later. Use the
local preview below to try an unreleased checkout.

## Build and inspect the submission ZIP

From the repository root with Python 3.11+ and Bash installed:

```bash
bash tests/test-codex-plugin-489.sh
python3 scripts/package-codex-plugin.py --output /tmp/idd-codex-plugin.zip
python3 -m zipfile -l /tmp/idd-codex-plugin.zip
```

The packager builds into a fresh temporary directory and runs the existing
flattened-skill verifier. It archives that distributable output, with stable
ordering, timestamps and permissions, including hidden metadata and the shared
icon. It never archives the working directory or a previously built `skills/`
tree. Keep the destination outside the repository. The ZIP root contains
`.codex-plugin/plugin.json`, `.claude-plugin/` (the compatible Claude manifest and
shared icon), `README.md`, and these eight skill directories:

- `auto-pilot`
- `init-gitissue`
- `issue-analysis`
- `issue-creator`
- `issue-pr-review`
- `issue-resolver`
- `issue-triage`
- `plan-to-issues`

Each skill carries its own references. The internal `idd-doctor`, development
files, local configuration, credentials and run logs are not package inputs.
There are no MCP servers or hooks. Inspect the ZIP before uploading, and retain
its SHA-256 with the release evidence. The packager validates the local package;
it does not replace the portal’s automated checks or guarantee approval.

## Preview this checkout without a release

Use an isolated temporary Codex home and local marketplace; this avoids changing
your regular installed plugins. Build first, then create a preview catalog pointing
at the built package:

```bash
bash scripts/build.sh --quiet
preview_dir="$(mktemp -d)"
mkdir -p "$preview_dir/.agents/plugins" "$preview_dir/home"
cp -R skills "$preview_dir/skills"
python3 - "$preview_dir" <<'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
catalog = {
    "name": "idd-preview",
    "plugins": [{"name": "idd", "source": {"source": "local", "path": "./skills"},
                 "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
                 "category": "Developer Tools"}]
}
(root / ".agents/plugins/marketplace.json").write_text(json.dumps(catalog))
PY
CODEX_HOME="$preview_dir/home" codex plugin marketplace add "$preview_dir"
CODEX_HOME="$preview_dir/home" codex plugin add idd@idd-preview
CODEX_HOME="$preview_dir/home" codex plugin list --json
CODEX_HOME="$preview_dir/home" codex
# In that fresh session: inspect the skill picker, then try $idd:issue-triage
# against a disposable GitHub repository you own and have authenticated with gh.
CODEX_HOME="$preview_dir/home" codex plugin remove idd@idd-preview
CODEX_HOME="$preview_dir/home" codex plugin marketplace remove idd-preview
```

The isolated home may require your normal Codex sign-in before an interactive
session. Verify all eight skills appear once and their bundled references resolve.
Choose a disposable repository for write workflows: resolver pushes branches and
opens PRs, while auto-pilot can also merge them. Record the Codex version and
results; Codex 0.160.0 has no `plugin validate` command. Structural CI checks
and a fresh-session native smoke test provide the local validation.

## Owner submission and release checklist

IDD’s core workflow requires local execution and repository file access. The
[conversion guidance](https://developers.openai.com/plugins/guides/submit-claude-plugin)
asks owners of such plugins to contact their OpenAI partner before submission
for possible product-specific review. Confirm that distribution path with the
owner; a working Codex package alone does not establish public eligibility.

1. Confirm the publisher identity, organization/project and submission access in
   the [Plugins dashboard](https://platform.openai.com/plugins). Complete the
   required individual or business verification. The manifest’s developer name
   must describe the selected owner; directory identity comes from verification.
2. Review the package description and `skills/README.md` disclosures. Confirm the
   public repository and publisher details are accurate. Add policy/support URLs
   only when the owner has real, accessible pages; none are fabricated here.
3. Upload the ZIP as a new plugin draft. Review Metadata & Skills findings,
   correct sources, rebuild, and upload again until required checks succeed.
   This skills-only package needs no MCP connection, OAuth credentials, MCP demo
   video or MCP review test cases. Do not add a dummy server.
4. Submit the draft for review, then publish only after approval. Uploading,
   submitting and publishing are separate owner actions and remain outstanding.
5. Repository marketplace installs follow the release pin; v0.25.0 is the first
   tag that contains the generated package. For each release, follow
   [release coupling](DEVELOPMENT.md#codex-plugin-issue-489): update the canonical
   version and existing Claude pin, rebuild, and publish the tag with the release
   commit. Test installation from that tag. Tags before v0.25.0 do not contain
   these files. Skill/metadata changes require another ZIP.

Official references: [Package your plugin](https://developers.openai.com/plugins/build/plugins)
(compatibility manifests, marketplace sources and CLI),
[Upload and submit](https://developers.openai.com/plugins/deploy/submission)
(identity, metadata/skills checks and review), and
[Plugin guidelines](https://developers.openai.com/plugins/plugin-guidelines).
Consult the current dashboard for any additional owner requirements.
