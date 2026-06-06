#!/usr/bin/env python3
"""Fetch the published latest.json and assert its version matches, with retries."""
import os
import sys
import time
import urllib.request
import json

owner_repo = os.environ.get("OWNER_REPO", "Raghaverma/UsageStats")
version = os.environ["VERSION"]
url = f"https://github.com/{owner_repo}/releases/latest/download/latest.json"

for attempt in range(1, 7):
    try:
        with urllib.request.urlopen(url, timeout=20) as resp:
            manifest = json.loads(resp.read())
        if manifest.get("version") == version:
            print(f"Published latest.json matches v{version}.")
            sys.exit(0)
        print(f"Attempt {attempt}: version {manifest.get('version')} != {version}")
    except Exception as exc:  # noqa: BLE001
        print(f"Attempt {attempt}: {exc}")
    time.sleep(10)

print("Published latest.json did not match in time.")
sys.exit(1)
