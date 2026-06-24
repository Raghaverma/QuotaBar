# Release checklist

## Automatic: push/merge to `Prod`

Every push to the `Prod` branch (a direct push or a merged PR — both look the same
to GitHub) triggers an `auto-tag` job that:
- reads the highest existing `vX.Y.Z` tag,
- bumps the **patch** number (`0.2.10` → `0.2.11`),
- creates and pushes that tag.

Pushing the tag is what actually produces the release — it fires the exact same
`tags: v*` trigger described below, so it goes through the identical
build/sign/notarize/publish path as a manual tag push, including the "Verify CI
passed on this commit" gate (a release is *not* built if `Build and Test (macOS)`
hasn't passed on that commit — the auto-tag still gets created either way, since
that check happens downstream in the `release` job, but no DMG/ZIP/GitHub Release
is published for a failing commit).

Caveats:
- Versioning is **patch-only and automatic** — there's no way to request a minor/major
  bump via a Prod push. For a minor/major release, push the tag yourself first
  (`git tag vX.Y.0 && git push origin vX.Y.0`) — the auto-tag job only fires on a
  branch push, so a manually-pushed tag is never overridden or duplicated by it.
- If the repo has a **tag protection rule** restricting who/what can push tags
  matching `v*` (Settings → Tags), the auto-tag job's push will fail — its identity
  is the `github-actions[bot]` token, not a human collaborator.
- Two pushes to `Prod` within seconds of each other could race on "what's the latest
  tag" and both try to create the same next version; the second one to push loses
  (visible as a failed `auto-tag` run) — rare in practice, not auto-retried.

## Manual: tag push or workflow_dispatch

1. **Green build** — `swift build && swift test` passes locally (use
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if needed).
2. **Bump the version** — set `VERSION` (or pass `APP_VERSION`). Use semantic
   `X.Y.Z`.
3. **Smoke-test the bundle** — `./scripts/package_dmg.sh`, then open
   `dist/QuotaBar.app` and confirm the menu-bar item appears and refreshes.
4. **Tag & push** — `git tag vX.Y.Z && git push origin vX.Y.Z`. The `release.yml`
   workflow then:
   - builds the universal DMG + ZIP,
   - generates and validates `latest.json` (URLs match the tag, sha256 64 hex,
     sizes positive, ISO-8601 UTC date),
   - creates the GitHub release with all three assets,
   - re-fetches the published `latest.json` and asserts the version matches.
5. **Verify the update loop** — a prior install should detect the new version via
   `AppUpdateService.fetchLatestRelease(current:)`.

(`workflow_dispatch` with an explicit version input works the same way, useful for
re-running a release without creating a new tag.)

## Signing & notarization

- Ad-hoc signing is the default (open-source distribution; users right-click → Open).
- For Developer ID: set `DEVELOPER_ID_APPLICATION` (or `CODESIGN_IDENTITY`).
- For notarization: `NOTARIZE_DMG=1` plus `NOTARYTOOL_PROFILE` (a stored
  `notarytool` keychain profile).

### Enabling it in CI (release.yml)

`release.yml` already checks for these four repo secrets and, if present,
signs with your Developer ID and notarizes automatically — no workflow edits
needed. If they're absent it silently falls back to today's ad-hoc-signed
release (a `::notice::` in the job log says so). One-time setup, requires an
**Apple Developer Program membership** ($99/yr — only you can do this part):

1. **Enroll** at [developer.apple.com/programs](https://developer.apple.com/programs/)
   if you haven't already.
2. **Create a Developer ID Application certificate**: Xcode → Settings →
   Accounts → your team → Manage Certificates → "+" → *Developer ID
   Application*. (Or via [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates/list).)
3. **Export it as a `.p12`**: open Keychain Access, find the new certificate
   under *My Certificates*, right-click → Export, set a password — this
   password is `MACOS_CERTIFICATE_PASSWORD` below.
4. **Base64-encode it** for the secret: `base64 -i Certificate.p12 | pbcopy`.
5. **Create an app-specific password** for notarytool at
   [appleid.apple.com](https://appleid.apple.com/) → Sign-In and Security →
   App-Specific Passwords. This is `MACOS_NOTARIZATION_PASSWORD` — not your
   regular Apple ID password.
6. **Find your Team ID**: [developer.apple.com/account](https://developer.apple.com/account/#/membership) (top right, under your name).
7. **Add four repo secrets** (Settings → Secrets and variables → Actions):

   | Secret | Value |
   | --- | --- |
   | `MACOS_CERTIFICATE_P12` | output of step 4 |
   | `MACOS_CERTIFICATE_PASSWORD` | the export password from step 3 |
   | `MACOS_NOTARIZATION_APPLE_ID` | your Apple ID email |
   | `MACOS_NOTARIZATION_TEAM_ID` | your Team ID from step 6 |
   | `MACOS_NOTARIZATION_PASSWORD` | the app-specific password from step 5 |

   (Five rows, four distinct secret *names* used by the workflow — the
   certificate and its password are two separate secrets.)

Once those exist, the next tag push produces a Developer ID–signed,
notarized, stapled DMG/ZIP automatically, and users stop seeing the
"unidentified developer" Gatekeeper warning in the README's install steps.
