# Contributing to Shell_Tools

## Scope

Contributions should improve Linux or OpenWrt operations, diagnostics, security, or browser userscripts. Keep tools focused and independently runnable; do not add a framework dependency to production scripts.

## Before Opening a Pull Request

1. Do not commit credentials, webhook URLs, production hostnames, certificates, or machine-specific paths.
2. Add `--help` to new Shell tools and return `2` for invalid arguments.
3. State side effects clearly in the script header and README. Destructive actions need an explicit confirmation or `--yes` flag.
4. Downloaded artifacts must be verified before execution or installation. Prefer pinned hashes, signatures, or immutable commits.
5. Add or update a Bats test for argument validation, failure handling, or another safe behavior path.
6. Run `./shell_tools_lint.sh` and `git diff --check`.

## Pull Requests

Use a narrow, descriptive title. Explain the target environment, the operational impact, and how you tested it. Do not combine unrelated formatting changes with behavior changes.

## Reporting Bugs

Use the bug-report template and include the script version, distribution, shell version, commands run, sanitized output, and expected behavior. Please remove tokens, IP addresses, and domain names that are not public.
