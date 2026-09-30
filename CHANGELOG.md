# Changelog

- Self-heal diagnostics now report severity, failed systemd service count, recommendations, and a JSON contract; server benchmarks now include a score and elapsed time.

- Dashboard now supports Markdown output for README/status pages and an interactive `--watch` refresh mode while preserving JSON automation output.

- Shell_Tools dashboard now supports `--dashboard` text output and `--dashboard --format json` for monitoring integrations, with health score, load, memory, root disk, kernel, and module count.

- Expanded Shell_Tools to 23 modules with a dashboard, performance benchmark, router diagnostics, Shell security scan, self-heal recommendations, and SSH read-only inspection. New modules support preview or read-only operation and emoji-rich terminal output.

- Kernel optimization adds a read-only `--status` inspection and scene-specific strategy details to `--plan`, so current capability and persisted configuration can be reviewed before mutation.
- Kernel optimization now recommends a scene from hardware, provider, virtualization, memory, and routing signals while retaining manual selection; failed or degraded runs show actionable reasons and recovery paths before exit.

All notable changes to this project are documented in this file.

## Unreleased

- Added configurable health thresholds, opt-in remote TLS inspection, Nginx time windows/buckets, and custom HTTPS DoH endpoints with bounded concurrency.
- Expanded Bats coverage for safe validation paths.

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
