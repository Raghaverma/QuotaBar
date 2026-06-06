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

- 🧭 **Notch-integrated hub** — a Dynamic-Island-style readout that sits flush inside
  the notch (opaque black, no floating glass box) and expands on hover into a live
  usage panel. Falls back to a tidy menu-bar pill on non-notched Macs.
- 📊 **Unified usage** — official plan quotas, rolling windows, relay balances, and
  local CLI account status in one place.
- 🔎 **Trust metadata** — every number is tagged with freshness (`live` /
  `cachedFallback` / `empty`), health (`ok` / `authExpired` / `rateLimited` / …), and
  per-window reset confidence so stale or guessed values are never silently trusted.
- ⏱ **Reset countdowns** — see exactly when each rolling window refills.
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

## Requirements

- macOS 14 (Sonoma) or newer
- Swift 6.2+ toolchain (Xcode 16.x)

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
so it stays App Store-safe. The panel is click-through everywhere except over the
visible island — a global mouse monitor toggles `ignoresMouseEvents` so the large
transparent panel never creates a dead zone over the desktop or other windows.

- **Collapsed** — an opaque-black island that straddles the notch with a compact
  readout on each ear (status dot + remaining %, and a reset countdown). The black
  fill blends with the physical notch instead of leaking out as a translucent box.
- **Expanded (on hover)** — drops down into a frosted panel listing every live
  provider with an animated progress ring, name, countdown, and quick Refresh /
  Settings actions.

Toggle it, pick the primary provider, and disable hover-to-expand in **Settings**.

## Documentation

- [`docs/PROVIDERS.md`](docs/PROVIDERS.md) — provider matrix and trust metadata.
- [`docs/EXTENDING.md`](docs/EXTENDING.md) — add a relay site or a new provider.
- [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md) — cutting a release.

## Contributing

Issues and pull requests are welcome. Please run `swift build` and `swift test` before
opening a PR; CI runs both on every push.

## License

MIT — see [LICENSE](LICENSE).
