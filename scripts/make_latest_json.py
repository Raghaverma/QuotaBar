#!/usr/bin/env python3
"""Generate dist/latest.json from the built artifacts.

Reads VERSION/OWNER_REPO from the environment, computes sha256 + size for the
DMG and ZIP, and writes the manifest that AppUpdateService consumes.
"""
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

DIST = Path("dist")
version = os.environ["VERSION"]
owner_repo = os.environ.get("OWNER_REPO", "Raghaverma/UsageStats")
base = f"https://github.com/{owner_repo}/releases/download/v{version}"


def asset(filename: str) -> dict:
    path = DIST / filename
    data = path.read_bytes()
    return {
        "url": f"{base}/{filename}",
        "sha256": hashlib.sha256(data).hexdigest(),
        "size": len(data),
    }


manifest = {
    "version": version,
    "pub_date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "release_url": f"https://github.com/{owner_repo}/releases/tag/v{version}",
    "notes_url": f"https://github.com/{owner_repo}/releases/tag/v{version}",
    "assets": {
        "macos_zip": asset("StatsUsage-macOS.zip"),
        "macos_dmg": asset("StatsUsage.dmg"),
    },
}

out = DIST / "latest.json"
out.write_text(json.dumps(manifest, indent=2))
print(f"Wrote {out}")
sys.exit(0)
