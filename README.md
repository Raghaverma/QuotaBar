<div align="center">

# StatsUsage

**One menu bar. Every AI subscription's usage — at a glance.**

A native macOS menu-bar app (with an optional Dynamic-Island-style notch hub) that
unifies the usage quotas scattered across your AI subscriptions: official plan
limits, rolling usage windows with reset countdowns, third-party relay balances, and
local desktop-client account status — each value annotated with *freshness*,
*health*, and *reset confidence* so you can trust what you see.

[![CI](https://github.com/Raghaverma/UsageStats/actions/workflows/ci.yml/badge.svg)](https://github.com/Raghaverma/UsageStats/actions/workflows/ci.yml)
[![Release](https://github.com/Raghaverma/UsageStats/actions/workflows/release.yml/badge.svg)](https://github.com/Raghaverma/UsageStats/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/Raghaverma/UsageStats?sort=semver)](https://github.com/Raghaverma/UsageStats/releases)

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange?logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-AppKit-1575F9?logo=swift&logoColor=white)](#architecture)
[![Dependencies](https://img.shields.io/badge/dependencies-none-success)](Package.swift)
[![Code size](https://img.shields.io/github/languages/code-size/Raghaverma/UsageStats)](https://github.com/Raghaverma/UsageStats)

</div>

---

## Highlights

- 🧭 **Notch-integrated hub** — a Dynamic-Island-style readout in opaque black that
  blends with the physical notch. The window is sized to fit the island exactly, so it
  never covers anything around it; hover to expand smoothly into a live usage panel.
  Falls back to a tidy floating pill on non-notched Macs.
- 📊 **Unified usage** — official plan quotas, rolling windows, relay balances, and
  local CLI account status in one place.
- ⏱ **Live reset timers** — a per-second ticking countdown to each window's reset, in
  the notch ear and beside every provider, so the time remaining is never stale.
- 🔎 **Trust metadata** — every number is tagged with freshness (`live` /
  `cachedFallback` / `empty`), health (`ok` / `authExpired` / `rateLimited` / …), and
  per-window reset confidence so stale or guessed values are never silently trusted.
- ⚙️ **Native settings** — a System-Settings-style preferences window (General, Menu
  Bar, Notch, Providers, About) with per-provider credentials, poll intervals, and
  alert thresholds.
- 🔐 **Secrets in the Keychain** — non-secret config is plain JSON with paranoid
  recovery; API keys and tokens live in the macOS Keychain.
- 📦 **Self-packaging & self-updating** — signs and bundles itself into a DMG and
  updates from a GitHub-hosted `latest.json`.
- 🪶 **Zero third-party dependencies** — pure Swift Package, layered by responsibility.

## Supported providers

| Family | Providers | Status |
| --- | --- | --- |
| **Official** | `codex`, `claude` | Local account status (reads local login state) |
| **Official** | `gemini` | Scaffolded — Cloud Code Assist endpoints |
| **Official** | `copilot`, `cursor`, `windsurf`, `jetbrains`, `kimi`, `openrouter*`, … | Registered placeholders, reported as not-yet-implemented |
| **Relay** | `relay`, `open`, `dragon` | NewAPI-style sites, described entirely by a JSON manifest — no code required |

See [`docs/PROVIDERS.md`](docs/PROVIDERS.md) for the full matrix and
[`docs/EXTENDING.md`](docs/EXTENDING.md) to onboard a new site.

## Installation & Setup

### 📥 Downloading the Application
1. Download **`StatsUsage.dmg`** from the [Latest GitHub Release](https://github.com/Raghaverma/UsageStats/releases/latest).
2. Open the downloaded `.dmg` disk image and drag **StatsUsage** into your **Applications** folder.

### 🛡️ First Launch (macOS Gatekeeper Setup)
Because the app is open-source and ad-hoc signed (not notarized under a paid Apple Developer ID), macOS will show a security warning on the first launch. You can bypass this easily:
* **Option A (Recommended)**: Right-click the **StatsUsage** app in your `/Applications` folder, select **Open**, and then click **Open** on the confirmation dialog.
* **Option B (Terminal)**: Run the following command in Terminal to clear the quarantine flag:
  ```bash
  xattr -dr com.apple.quarantine /Applications/StatsUsage.app
  ```

### ⚙️ Configuration
Once launched, a gauge icon will appear in your macOS menu bar. 
1. Click the icon or hover near the notch/top-center to view the live island.
2. Go to **Settings → Providers** to configure your API keys (securely saved in the macOS Keychain) and poll intervals.

---

## 🔄 Automatic In-App Updates
StatsUsage features a **fully automated, over-the-air update pipeline**:
* **Silent Background Checks**: Every time you launch the app, it checks the GitHub release manifest (`latest.json`) in the background. If a newer version is published, it alerts you via a macOS system notification.
* **One-Click Installation**: Go to **Settings → About**, click **Download and Install Update**, and the app will automatically download the latest ZIP, verify its integrity (via SHA256 checksum), swap the bundle, and relaunch the application for you. You never need to download the DMG again!
* **Toggle Auto-Checks**: You can enable or disable background update checks at any time in **Settings → General → Updates**.

## Requirements

- macOS 14 (Sonoma) or newer
- Swift 6.2+ toolchain (Xcode 16.x) — only needed to build from source

## Quick start

```bash
swift build          # compile
swift run            # launch from source (a menu-bar icon appears)
swift test           # run the XCTest suite
./scripts/package_dmg.sh   # build a distributable DMG + ZIP into dist/
```

> `swift test` requires the full Xcode toolchain (for XCTest). If your active
> developer dir is the Command Line Tools, prefix the command with
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Architecture

The package is layered by responsibility; dependency arrows point inward toward the
dependency-free `Domain` contract:

| Target | Responsibility |
| --- | --- |
| `StatsUsageDomain` | Pure `Sendable` models & enums (`UsageSnapshot`, `ProviderType`, …) |
| `StatsUsageApplication` | Refresh scheduler, backoff policy, alert engine |
| `StatsUsagePresentation` | View-state models & pure presenters |
| `StatsUsageProviders` | Slim fetching contract |
| `StatsUsageFeatures` | Feature assembly |
| `StatsUsageBootstrap` | Composition root |
| `StatsUsageInfrastructure` | Credential-store seam |
| `StatsUsage` (executable) | AppKit status item, SwiftUI UI, notch hub, concrete providers, relay engine, stores |

A boundary test (`ArchitectureBoundaryTests`) enforces that `Domain` and
`Application` never import AppKit/SwiftUI.

## Mental model

StatsUsage keeps a dictionary of `[providerID: UsageSnapshot]` fresh and renders it.
A **scheduler** drives a **factory-built set of providers** (official APIs, local
CLIs, or JSON-described relay sites) on one coalesced, jittered, backoff-aware poll
loop. Each provider returns a richly annotated snapshot which **pure presenters** turn
into menu-bar text, the notch hub, and popover cards. Config is non-secret JSON with
paranoid recovery; secrets live in the Keychain.

## The notch hub

The notch hub is hosted in a borderless, non-activating `NSPanel` pinned to the top of
the notched screen, using **public AppKit APIs only** (no private SkyLight/CGSSpace),
so it stays App Store-safe. The SwiftUI hub measures its own size and reports it up
through a `NotchLayoutBridge`; the controller then **resizes the panel to fit the
island exactly**. Because the window is never larger than the visible hub, there is no
transparent dead zone over other apps and no mouse-passthrough trickery is needed.

- **Collapsed** — an opaque-black island that straddles the notch with a compact
  readout on each ear (status dot + remaining %, and a live reset timer). The black
  fill blends with the physical notch instead of leaking out as a translucent box.
- **Expanded (on hover)** — smoothly (no bounce) expands into a panel listing every
  enabled provider with an animated progress ring, name, per-window live countdowns,
  and quick Refresh / Settings actions. Providers still waiting on data stay listed.

Toggle it, pick the primary provider, and disable hover-to-expand in **Settings**.

## Building & distributing

The app ships as a self-contained DMG built straight from the SwiftPM release binary —
no Xcode project required.

### Build a DMG locally

```bash
./scripts/package_dmg.sh
```

This builds `swift build -c release`, assembles `StatsUsage.app` (Info.plist, icon,
resource bundle), code-signs it, and writes both artifacts to `dist/`:

| Artifact | Purpose |
| --- | --- |
| `dist/StatsUsage.dmg` | Drag-to-Applications disk image for end users |
| `dist/StatsUsage-macOS.zip` | Zipped `.app`, used by the in-app updater |

Override the version with `APP_VERSION=0.2.0 ./scripts/package_dmg.sh` (otherwise it
reads the `VERSION` file).

### Signing levels

| Goal | Command |
| --- | --- |
| **Ad-hoc** (open-source default; users right-click → Open) | `./scripts/package_dmg.sh` |
| **Developer ID** (no Gatekeeper prompt, requires a paid Apple Developer account) | `DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" ./scripts/package_dmg.sh` |
| **Developer ID + notarized** (best experience) | `NOTARIZE_DMG=1 NOTARYTOOL_PROFILE=my-profile DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" ./scripts/package_dmg.sh` |

> The `NOTARYTOOL_PROFILE` is a stored `notarytool` keychain profile — create one once
> with `xcrun notarytool store-credentials my-profile --apple-id you@example.com
> --team-id TEAMID` (you'll be prompted for an app-specific password).

### Publish a release (recommended)

Distribution is fully automated by [`.github/workflows/release.yml`](.github/workflows/release.yml).
To cut a release, just tag it:

```bash
# 1. Make sure the build is green
swift build && swift test

# 2. Bump the version and commit
echo 0.2.0 > VERSION && git commit -am "Release 0.2.0"

# 3. Tag and push — the workflow does the rest
git tag v0.2.0
git push origin main --tags
```

The workflow then builds the DMG + ZIP, generates and validates `latest.json`, and
publishes a GitHub Release with all three assets attached — which is exactly what the
**Install** section above and the in-app updater download from. See
[`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md) for the full checklist.

> Want zero Gatekeeper friction for users? Add your Developer ID and notarization
> secrets to the repository and pass them through to `package_dmg.sh` in the workflow.

## Documentation

- [`docs/PROVIDERS.md`](docs/PROVIDERS.md) — provider matrix and trust metadata.
- [`docs/EXTENDING.md`](docs/EXTENDING.md) — add a relay site or a new provider.
- [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md) — cutting a release.

## Contributing

Issues and pull requests are welcome. Please run `swift build` and `swift test` before
opening a PR; CI runs both on every push.

## License

MIT — see [LICENSE](LICENSE).
