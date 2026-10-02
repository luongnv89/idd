#!/usr/bin/env bash
# Codex packaging: generated parity, complete inventory, safe deterministic ZIP.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/idd-codex-489.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
python3 "$ROOT/scripts/package-codex-plugin.py" --output "$TMP/first.zip" >/dev/null
python3 "$ROOT/scripts/package-codex-plugin.py" --output "$TMP/second.zip" >/dev/null
python3 - "$ROOT" "$TMP" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys
import zipfile

root, tmp = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location('packager', root / 'scripts/package-codex-plugin.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert (tmp / 'first.zip').read_bytes() == (tmp / 'second.zip').read_bytes(), 'non-deterministic ZIP'
with zipfile.ZipFile(tmp / 'first.zip') as archive:
    names = archive.namelist()
    assert names == sorted(names)
    assert all(not name.startswith('/') and '..' not in Path(name).parts for name in names)
    archive.extractall(tmp / 'package')
package = tmp / 'package'
module.validate(package)
public = module.PUBLIC_SKILLS
assert len(public) == 8 and 'idd-doctor' not in public
manifest_path = package / '.codex-plugin/plugin.json'
manifest = json.loads(manifest_path.read_text())
canonical = json.loads((root / 'src/plugin/plugin.json').read_text())
for key in ('name', 'version', 'author', 'homepage', 'repository', 'license', 'keywords'):
    assert manifest[key] == canonical[key], key
assert manifest['skills'] == ['./' + name for name in sorted(public)]
assert not any(key in manifest for key in ('mcpServers', 'hooks', 'apps'))
assert manifest['interface']['category'] == 'Developer Tools'
assert manifest['interface']['developerName'] == canonical['author']['name']
assert set(p.name for p in (package / '.codex-plugin').iterdir()) == {'plugin.json'}
# Committed outputs must match a fresh build, including every hidden file.
assert {p.relative_to(package) for p in package.rglob('*') if p.is_file()} == {
    p.relative_to(root / 'skills') for p in (root / 'skills').rglob('*') if p.is_file()}
for item in package.rglob('*'):
    if item.is_file():
        assert item.read_bytes() == (root / 'skills' / item.relative_to(package)).read_bytes(), item
catalog = json.loads((root / '.agents/plugins/marketplace.json').read_text())
claude = json.loads((root / '.claude-plugin/marketplace.json').read_text())
entry = catalog['plugins'][0]
assert catalog['name'] == manifest['name'] and len(catalog['plugins']) == 1
assert entry['source'] == {'source': 'git-subdir', 'url': canonical['repository'] + '.git',
                           'path': './skills', 'ref': claude['plugins'][0]['source']['ref']}
assert entry['source']['ref'] == 'v' + manifest['version']
assert entry['policy'] == {'installation': 'AVAILABLE', 'authentication': 'ON_INSTALL'}
# Negative checks exercise validation, not just a good fixture.
for field, value in [('logo', '../outside.png'), ('shortDescription', 'x' * 31)]:
    changed = json.loads(json.dumps(manifest))
    changed['interface'][field] = value
    manifest_path.write_text(json.dumps(changed))
    try:
        module.validate(package)
    except ValueError:
        pass
    else:
        raise AssertionError('accepted invalid ' + field)
manifest_path.write_text(json.dumps(manifest))
(package / 'private.env').write_text('decoy, not a credential')
try:
    module.validate(package)
except ValueError:
    pass
else:
    raise AssertionError('accepted unexpected file')
# Emitter removes stale output when reused for a non-plugin fixture.
spec = importlib.util.spec_from_file_location('builder', root / 'scripts/build.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
out = tmp / 'emitted/skills'
out.mkdir(parents=True)
builder._emit_plugin_manifest(root / 'src', out)
fresh_catalog = out.parent / '.agents/plugins/marketplace.json'
assert fresh_catalog.read_bytes() == (root / '.agents/plugins/marketplace.json').read_bytes()
fixture = tmp / 'fixture/src'
fixture.mkdir(parents=True)
builder._emit_plugin_manifest(fixture, out)
assert not fresh_catalog.exists(), 'stale catalog after fixture build'
print('✓ Codex package: metadata, parity, inventory, ZIP determinism and negative cases')
PY
