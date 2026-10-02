#!/usr/bin/env python3
"""Build and verify an IDD submission ZIP from fresh distributable output only."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
PUBLIC_SKILLS = {p.name for p in (ROOT / "src/skills").iterdir()
                 if (p / "SKILL.source.md").is_file()}


def validate(package: Path) -> None:
    """Reject incomplete packages and escaping asset paths before archiving."""
    manifest = json.loads((package / ".codex-plugin/plugin.json").read_text())
    if manifest["name"] != "idd" or manifest["skills"] != ["./" + name for name in sorted(PUBLIC_SKILLS)]:
        raise ValueError("unexpected plugin identity or skills root")
    expected = PUBLIC_SKILLS | {".claude-plugin", ".codex-plugin", "README.md"}
    if {p.name for p in package.iterdir()} != expected:
        raise ValueError("unexpected public plugin inventory")
    for skill in PUBLIC_SKILLS:
        if not (package / skill / "SKILL.md").is_file() or not (package / skill / "references").is_dir():
            raise ValueError(f"incomplete skill: {skill}")
    interface = manifest["interface"]
    for key, limit in (("displayName", 30), ("shortDescription", 30),
                       ("longDescription", 4000), ("developerName", 80)):
        if not isinstance(interface.get(key), str) or not 0 < len(interface[key]) <= limit:
            raise ValueError(f"invalid interface.{key}")
    for key in ("logo", "composerIcon"):
        value = interface[key]
        asset = (package / value).resolve()
        if not value.startswith("./") or not asset.is_relative_to(package.resolve()):
            raise ValueError(f"escaping interface.{key}")
        data = asset.read_bytes()
        if len(data) > 5 * 1024 * 1024 or data[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"invalid PNG: {key}")
        width, height = struct.unpack(">II", data[16:24])
        if width != height or not 48 <= width <= 4096:
            raise ValueError(f"invalid icon dimensions: {key}")
    for item in package.rglob("*"):
        if item.is_symlink():
            raise ValueError(f"symlink in package: {item}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="submission ZIP destination")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="idd-codex-package-") as directory:
        out = Path(directory)
        subprocess.run(["bash", str(ROOT / "scripts/build.sh"), "--out", str(out), "--quiet"],
                       cwd=ROOT, check=True)
        package = out / "skills"
        validate(package)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for item in sorted(package.rglob("*"), key=lambda p: p.relative_to(package).as_posix()):
                if not item.is_file():
                    continue
                info = zipfile.ZipInfo(item.relative_to(package).as_posix(), (1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, item.read_bytes())
    print(args.output.resolve())


if __name__ == "__main__":
    main()
