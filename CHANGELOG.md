# Changelog

All notable changes to **__ProjectName__** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed
- Initializer transformations now stage and roll back checkout changes when an intermediate operation fails.
- First releases now apply the selected major, minor, or patch bump to the project version seed.

### Fixed
- PowerShell initialization now applies author and email fallbacks when Git is unavailable while preserving explicit metadata.
- Initializers now reject dangling local `.claude/settings.json` links and Bash activation no longer overwrites a destination created after preflight.
- Initializers now refuse to overwrite an existing local `.claude/settings.json`.
- Releases now fail preflight when project metadata still contains template tokens or default placeholders.
- First releases now include the full relevant history and use a valid release-tag changelog link.
- PowerShell initializer rollback now restores all mutable files after a failed path rename.
- Release packages now verify that the finalized versioned CHANGELOG.md is included unchanged.
- Ordinary package builds no longer consume stale ignored release notes; release notes are supplied explicitly by the release workflow.
- Both initializers now reject metadata control characters and line separators before mutating the checkout.
- Bash initializer escaping now preserves backslashes in generated shell, Python, and JSON contexts.
- Linux test runs now preserve existing NuGet cache volume names and use a Docker-safe fallback only for leading-underscore project names.
- Release retries now verify the published package contents and repository commit before reusing an existing NuGet version.
- PowerShell initialization now replaces tokens in hidden files and renames hidden token-named paths.
- Reject missing, option-like, and non-numeric Bash initializer values before changing the checkout.
- Pass Linux test-helper `-Filter` values as data so shell metacharacters cannot inject Bash commands.

[Unreleased]: https://github.com/__GitHubOwner__/__ProjectName__/commits/main
