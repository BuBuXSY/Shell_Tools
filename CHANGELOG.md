# Changelog

All notable changes to this project are documented in this file.

## Unreleased

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
