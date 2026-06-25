# Security Policy

QuotaBar reads local CLI credential files (e.g. `~/.codex/auth.json`, `~/.gemini/oauth_creds.json`,
`~/.claude/.credentials.json`) and stores provider secrets in the macOS Keychain. Given that scope,
we take security reports seriously.

## Reporting a Vulnerability

Please report suspected vulnerabilities privately to **rvraghav09@gmail.com** rather than opening a
public issue. Include:

- A description of the issue and its potential impact
- Steps to reproduce, or a proof of concept
- The QuotaBar version and macOS version you tested on

We aim to acknowledge reports within 5 business days and to ship a fix or mitigation before any
public disclosure.

## Scope

In scope: the QuotaBar app itself (credential handling, Keychain usage, auto-update flow, network
calls to provider APIs) and its build/release pipeline (`.github/workflows/`, `scripts/`).

Out of scope: vulnerabilities in the third-party CLIs/services QuotaBar reads from (Claude Code,
Codex CLI, Gemini CLI, their respective APIs) — please report those upstream.

## Supported Versions

Only the latest released version is supported with security fixes.
