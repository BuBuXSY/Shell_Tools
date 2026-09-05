# Changelog

All notable changes to this project are documented in this file.

## Unreleased

- Added a standalone, read-only `system_health_snapshot.sh` with text/JSON output, strict mode, and no-color behavior.
- Added an optional NOC-style UI helper with documented `COLOR_MODE=auto|always|never` precedence (`always` forces ANSI; `auto` honors `NO_COLOR`, `TERM=dumb`, and non-TTY output) without becoming a runtime dependency.
- Fixed DNS monitor default blacklist initialization so ShellCheck warning checks pass.

- Added Bats behavior tests for safe command paths and invalid arguments.
- Added contributor guidance, a security reporting policy, and GitHub issue and pull-request templates.
- Expanded local and CI validation to run Shell behavior tests when Bats is available.
- DNS monitor configuration is now constrained plain text, never sourced, and shared output uses a non-blocking lock.
- Certificate deployment tightens directory and private-key permissions with post-install verification.
- Kernel optimization records persistent-file state and restores persistent files on failed transactions; runtime recovery remains compensating rather than atomic.
- Notification webhooks require HTTPS and curl redirects are restricted to HTTPS.

## 2026-07-11

- Hardened download, validation, rollback, backup, and diagnostic behavior across the toolset.
- Added the repository self-check workflow and userscript smoke tests.
