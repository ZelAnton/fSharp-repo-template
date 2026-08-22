# Changelog

All notable changes to **__ProjectName__** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Fixed
- Both initializers now reject metadata control characters and line separators before mutating the checkout.
- Bash initializer escaping now preserves backslashes in generated shell, Python, and JSON contexts.
- Linux test runs now preserve existing NuGet cache volume names and use a Docker-safe fallback only for leading-underscore project names.
- Release retries now verify the published package contents and repository commit before reusing an existing NuGet version.
- PowerShell initialization now replaces tokens in hidden files and renames hidden token-named paths.
- Reject missing, option-like, and non-numeric Bash initializer values before changing the checkout.
- Pass Linux test-helper `-Filter` values as data so shell metacharacters cannot inject Bash commands.

[Unreleased]: https://github.com/__GitHubOwner__/__ProjectName__/commits/main
