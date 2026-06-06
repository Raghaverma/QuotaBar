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

MAX_ATTEMPTS = 12
SLEEP_SECS = 15  # 12 × 15 s = 180 s; GitHub CDN can take 2–5 min to propagate

for attempt in range(1, MAX_ATTEMPTS + 1):
    try:
        with urllib.request.urlopen(url, timeout=20) as resp:
            manifest = json.loads(resp.read())
        if manifest.get("version") == version:
            print(f"Published latest.json matches v{version}.")
            sys.exit(0)
        print(f"Attempt {attempt}/{MAX_ATTEMPTS}: version {manifest.get('version')} != {version}")
    except Exception as exc:  # noqa: BLE001
        print(f"Attempt {attempt}/{MAX_ATTEMPTS}: {exc}")
    if attempt < MAX_ATTEMPTS:
        time.sleep(SLEEP_SECS)

print("Published latest.json did not match in time.")
sys.exit(1)
