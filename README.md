<div align="center">

# QuotaBar

**Say hello to QuotaBar, the coolest way to make your macOS menu bar and notch the unified command center for all your AI subscription quotas!**

Say goodbye to hunting down usage stats across a dozen browser tabs: with QuotaBar, your menu bar and notch transform into a dynamic live-activity readout for all your AI subscriptions. Complete with real-time countdowns for rolling reset windows, visual progress gauges, and custom alert thresholds, it keeps you in control of your usage. But that's just the start! QuotaBar offers a beautiful notch-integrated island, secure credentials stored locally in your Keychain, and a fully automated in-app update pipeline!

[![CI](https://github.com/Raghaverma/UsageStats/actions/workflows/ci.yml/badge.svg)](https://github.com/Raghaverma/UsageStats/actions/workflows/ci.yml)
[![Release](https://github.com/Raghaverma/UsageStats/actions/workflows/release.yml/badge.svg)](https://github.com/Raghaverma/UsageStats/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/Raghaverma/UsageStats?sort=semver)](https://github.com/Raghaverma/UsageStats/releases)

---

[Features](#-roadmap) · [Installation](#installation) · [Building from Source](#building-from-source) · [Contributing](#-contributing)

<!--
  HERO SCREENSHOT — replace this with a real capture before merging.
  Goal: one image, ~1280px wide, that shows the menu bar widget, the expanded
  notch hub, and the Settings window in the same shot (composite if needed) so a
  visitor understands what the app is within one glance, before reading anything.
  Save as docs/screenshots/hero.png and update the path below.
-->
<img src="docs/screenshots/hero.png" alt="QuotaBar menu bar widget, expanded notch hub, and Settings window showing live AI quota usage" width="800">

<!--
  DEMO GIF — replace this with a real capture before merging.
  Goal: ~8-10s loop — hover the notch, watch it expand, show 2-3 provider rows
  with live reset countdowns, then move away and watch it collapse. This single
  GIF sells the app faster than any text on this page.
  Save as docs/screenshots/demo.gif and update the path below.
-->
<img src="docs/screenshots/demo.gif" alt="QuotaBar notch hub expanding on hover to reveal live AI usage quotas and reset countdowns" width="800">

</div>

## Installation

### System Requirements
* macOS 14 Sonoma or later
* Apple Silicon or Intel Mac

### Option 1: Download and Install Manually

1. Download **`QuotaBar.dmg`** from the [Latest GitHub Release](https://github.com/Raghaverma/UsageStats/releases/latest).
2. Open the downloaded `.dmg` disk image and drag **QuotaBar** into your **Applications** folder.

> [!IMPORTANT]
> We don't have an Apple Developer account (yet 👀), so macOS will warn you that QuotaBar is from an unidentified developer on first launch. This is expected behavior.
>
> You'll need to bypass this before the app will open. You only need to do this once. Use one of the methods below.

#### Recommended: Terminal (Always Works)
This is the quickest and easiest method. It only requires a single command and works consistently for all users. System Settings can sometimes fail and won't work for non-admin users.

After moving QuotaBar to your Applications folder, run:
```bash
xattr -dr com.apple.quarantine /Applications/QuotaBar.app
```
Then open the app normally.

#### Alternative: System Settings
1. Try to open the app — you'll see a security warning.
2. Click **OK** to dismiss it.
3. Open **System Settings > Privacy & Security**.
4. Scroll to the bottom and click **Open Anyway** next to the QuotaBar warning.
5. Confirm if prompted.

---

## 🔄 Automatic In-App Updates
QuotaBar features a **fully automated, over-the-air update pipeline**:
* **Silent Background Checks**: Every time you launch the app, it checks the GitHub release manifest (`latest.json`) in the background. If a newer version is published, it alerts you via a macOS system notification.
* **One-Click Installation**: Go to **Settings → About**, click **Download and Install Update**, and the app will automatically download the latest ZIP, verify its integrity (via SHA256 checksum), swap the bundle, and relaunch the application for you. You never need to download the DMG again!
* **Toggle Auto-Checks**: You can enable or disable background update checks at any time in **Settings → General → Updates**.

---

## Usage
1. Launch the app, and voilà—your menu bar is now showing your fresh usage stats.
2. Hover over the notch/top-center of your screen to see the live notch hub expand and reveal all your active provider quotas.
3. Click the notch hub or the menu bar item to open **Settings** and customize your providers, credentials, and refresh intervals.
4. Add API keys safely—they are securely stored in the native macOS Keychain!

---

## 📋 Roadmap & Features

* 🧭 **Notch-integrated hub** — Dynamic-Island-style readout that blends with the physical notch. Hover to expand smoothly into a live usage panel. 🖥️
* 📊 **Unified usage stats** — Official plan limits, rolling windows, and relay balances in one place. 🎯
* ⏱ **Live reset timers** — Real-time countdowns to subscription quota resets. ⌛
* 🔎 **Trust metadata** — Freshness annotations (`live` / `cachedFallback`) and reset confidence scores. 🏷️
* ⚙️ **Native settings** — System-Settings-style preferences (General, Menu Bar, Notch, Providers, About). 🛠️
* 🔐 **Keychain security** — Secure storage for all sensitive tokens and API keys. 🔑
* 🔄 **In-app updates** — Fully automated, one-click updating over the internet. ☁️
* 🪶 **Zero dependencies** — Built purely on native Swift 6 and SwiftUI APIs. ⚡
* 🩺 **Provider diagnostics** — Connection testing, visible refresh errors, last-updated status, and retry controls.
* 📈 **Persistent trends** — Menu-bar sparklines and consumption estimates survive application relaunches.
* 🛡️ **Safer credentials and updates** — Keychain-backed relay secrets, opt-in CLI credential writes with backups, checksum/size validation, and code-signature verification.

---

## Building from Source

### Prerequisites
* **macOS 14 or later**: If you’re not on macOS 14+, we might need to send a search party.
* **Swift 6.0+ toolchain (Xcode 16.x)**: This is where the magic happens, so make sure it's up-to-date.

### Installation & Run
1. **Clone the Repository**:
   ```bash
   git clone https://github.com/Raghaverma/UsageStats.git
   cd UsageStats
   ```
2. **Build the Project**:
   ```bash
   swift build
   ```
3. **Run the Application**:
   ```bash
   swift run
   ```
4. **Run the Test Suite**:
   ```bash
   ./scripts/check_toolchain.sh
   swift test
   ```
   If Command Line Tools are selected instead of full Xcode, run:
   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
   ```
5. **Assemble Local DMG & ZIP**:
   ```bash
   ./scripts/package_dmg.sh
   ```

---

## 🤝 Contributing
We’re all about good vibes and awesome contributions! Feel free to open issues or submit pull requests. Please run `swift build` and `swift test` before opening a PR; our GitHub Actions CI runs both on every push.

---

## 🎉 Acknowledgments
We would like to express our gratitude to the authors and maintainers of the open-source projects and platforms that made this possible.

* **SwiftUI & AppKit**: For making us look like coding wizards.
* **macOS System Services**: For providing a secure Keychain and native system APIs.
* **You**: For being awesome and checking out QuotaBar!

---

## 📄 License
MIT — see [LICENSE](LICENSE) for details.
