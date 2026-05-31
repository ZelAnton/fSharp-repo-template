# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> This is the F# sibling of `cSharp-repo-template` / `rust-repo-template`, scaffolded
> by mirroring the C# template and adapting it for F#. It is a **token template**:
> `__ProjectName__`, `__Author__`, `__GitHubOwner__`, `__Description__`, and `__Year__`
> are stamped in by `scripts/init.ps1`. Read [TEMPLATE.md](TEMPLATE.md) and
> [AGENTS.md](AGENTS.md) for the full layout and the enforced conventions; the
> F#-specific deviations from the C# template are summarised in TEMPLATE.md.

## Commands

```bash
# Restore the local tools (Fantomas) — once per clone
dotnet tool restore

# Build the whole solution — warnings are errors. Build ordering (from the .slnx)
# resolves the test project's assembly Reference to the freshly built library.
dotnet build __ProjectName__.slnx

# Run all tests (build the solution first, as above)
dotnet test __ProjectName__.slnx

# Run a single test
dotnet test __ProjectName__.slnx --filter "FullyQualifiedName~TestName"

# Format F# / check formatting (Fantomas is the style authority; CI fails on unformatted F#)
dotnet fantomas src tests
dotnet fantomas --check src tests

# Run tests inside a Linux container (requires Rancher Desktop or Docker Desktop, PowerShell 7+)
pwsh scripts/test-linux.ps1
pwsh scripts/test-linux.ps1 -Filter "FullyQualifiedName~TestName"
```

## Architecture

> **Fill this in for `__ProjectName__`.** Describe the public surface, the
> main modules/types, and any non-obvious design decisions so an agent can
> navigate the code without re-deriving the structure each time.

The library namespace is `__ProjectName__`; the source lives in
`src/__ProjectName__`. Keep the public API surface small and intentional, prefer
`module`-level functions and immutable types, keep implementation details
internal (`internal` / private modules), and prefer simple, direct code over new
abstractions. Document deviations from the conventions below right here.

### F# compile order is significant

Unlike C#, F# resolves declarations strictly top-to-bottom: a type or function
must appear *before* its first use, both within a file and across files. The
order of `<Compile Include="..." />` items in the `.fsproj` **is** the dependency
order — it is not cosmetic. When adding a file, insert it after everything it
depends on and before everything that depends on it; do not rely on alphabetical
ordering or globbing.

### Exception handling style

F# uses `try`/`with` and `try`/`finally` (there is no `catch` keyword).

- **No one-line `try` / `with` / `finally`.** Each keyword owns its own block on
  its own lines. Collapsing a handler onto a single line is a style violation.
- **Swallowing handlers must carry a comment explaining the rationale** — what
  exception is expected and why doing nothing is correct here. A bare `-> ()`
  without justification is not acceptable; `// ignored` alone is not enough.

Example:
```fsharp
try
    cts.Cancel()
with
| :? ObjectDisposedException ->
    // already disposed - being torn down concurrently; nothing to recover.
    ()
```
See [AGENTS.md](AGENTS.md#exception-handling-style) for the canonical rule.

### Formatting: spaces and Fantomas

F# source (`.fs`/`.fsi`/`.fsx`) is indented with **spaces, not tabs** — the F#
compiler rejects tabs in indentation. This is the deliberate exception to the
tabs-everywhere convention of the C# template; `.fsproj`/`.json`/`.config` still
use tabs. [Fantomas](https://fsprojects.github.io/fantomas/) (pinned in
`.config/dotnet-tools.json`) is the formatter and CI fails on unformatted F# —
the F# compiler does not enforce `.editorconfig` style the way Roslyn does for C#.

## Test project setup

`tests/__ProjectName__.Tests` references the library via a direct
`<Reference Include="__ProjectName__" />` + `AssemblySearchPaths` (not
`<ProjectReference>`). Build ordering comes from `BuildDependency` entries in
`__ProjectName__.slnx`. Run tests after a `dotnet build` (or let the test runner
build implicitly), because the assembly reference only resolves once the library
has been built into its output directory. The test stack is NUnit
(`Microsoft.NET.Test.Sdk` + `NUnit` + `NUnit3TestAdapter`) — `Microsoft.NET.Test.Sdk`
is required for `dotnet test` discovery; do not remove it.

Write tests as a **`[<TestFixture>]` type with instance `[<Test>]` members**, not
as a module: an F# module compiles to a static class, which NUnit's discovery
skips (tests build but are never found). If `dotnet test` reports "No test is
available", see the FSharp.Core note under
[Dependencies and project references](#dependencies-and-project-references).

## Linux testing from Windows

`scripts/test-linux.ps1` mounts the repo into `mcr.microsoft.com/dotnet/sdk:10.0`
and runs `dotnet build` + `dotnet test`. Anonymous Docker volumes shadow the
`bin`/`obj` folders so the host working copy stays untouched; a named volume
(`__ProjectName__-nuget`) caches packages between runs. CI mirrors this with
[.github/workflows/ci.yml](.github/workflows/ci.yml), which runs the same
build/test across `ubuntu-latest`, `windows-latest`, and `macos-latest` on PR
and push to main. This script is optional — delete it and `docs/linux-testing.md`
if not needed.

## MSBuild path properties

`Directory.Build.props` defines two canonical path properties that every project in the repo inherits:

- `$(RepoRoot)` — absolute path to the repository root (trailing separator included). Derived from `$(MSBuildThisFileDirectory)` inside `Directory.Build.props`, so it is always the directory that contains that file.
- `$(MainProjectDir)` — absolute path to `src/__ProjectName__/` (the main library project directory).

Use these properties wherever a `.fsproj`, `.props`, or `.targets` file must reference something outside its own directory — never write `..\..\` or `$(MSBuildThisFileDirectory)..\` directly. If a new project is added that others reference by path, add a matching `$(XxxProjectDir)` property to `Directory.Build.props`.

## Dependencies and project references

- Centralized package management: declare every version once in `Directory.Packages.props`; individual `.fsproj` files reference packages **without** a `Version` attribute. It is not a fixed allow-list — add the production/test packages the project actually needs.
- Cross-project references use `<Reference Include="..." />` + `AssemblySearchPaths`, never `<ProjectReference>` or `HintPath`. Build ordering is enforced by `BuildDependency` entries in `__ProjectName__.slnx`, so referenced projects build before the projects that depend on them.
- **FSharp.Core under CPM (load-bearing).** Each `.fsproj` declares `<PackageReference Include="FSharp.Core" />` and `Directory.Packages.props` pins `<PackageVersion Include="FSharp.Core" Version="..." />` to the .NET SDK's bundled FSharp.Core. Under Central Package Management the F# SDK's *implicit* FSharp.Core reference is dropped from the dependency graph; without the explicit reference, FSharp.Core never reaches `deps.json`, the runtime can't load it, and `dotnet test` silently finds **zero tests** on an otherwise-green build. Do not remove either half, and do not pin below the SDK's version (the compiler references its own FSharp.Core, so a lower deployed assembly throws at runtime). When bumping the SDK, realign the pin.

## Changelog

`CHANGELOG.md` is the single source of truth for release notes. The release workflow reads the `## [Unreleased]` section automatically — it populates the GitHub Release body and the NuGet `<PackageReleaseNotes>` field.

**Rule: every user-visible change ships with a `CHANGELOG.md` entry in the same change set.** This covers new or modified public API, behavioural changes, bug fixes, deprecations, and removals. The only exemption is pure internal refactors that do not alter observable behaviour. The changelog update is part of the change, not a follow-up task — never defer it.

**How to add an entry:**

1. Open `CHANGELOG.md`.
2. Under `## [Unreleased]`, find the appropriate subsection:
   - `### Added` — new features or API members
   - `### Changed` — modified behaviour or API
   - `### Fixed` — bug fixes
   - `### Removed` — removed features or API members
   - `### Deprecated` — features still present but marked for removal
3. Replace the placeholder `-` with a real bullet (or append after existing bullets). Keep it one line, written for a consumer of the library — not for the implementer. One bullet per distinct user-visible effect — bundle nothing.

Do **not** touch the versioned sections (`## [1.0.0]`, etc.) — the release workflow manages those.

### Auto-fill from git log

If `## [Unreleased]` has no real bullets when the release workflow runs, it auto-generates entries from commits since the previous tag via [git-cliff](https://git-cliff.org/) (config: `cliff.toml`). Manual entries always take priority — auto-fill is a fallback so a release never blocks on missing notes, not the default.

The auto-fill bucket is decided by the first word of the commit subject:

| Prefix (case-insensitive) | Bucket |
|---|---|
| `Add`, `Feat` | `### Added` |
| `Fix`, `Bug` | `### Fixed` |
| `Remove`, `Delete`, `Drop` | `### Removed` |
| `Refactor`, `Update`, `Change`, `Rename`, `Perf`, `CI`, `Cleanup`, ... | `### Changed` |
| `Doc`, `Chore`, `Test`, `Style` | skipped (not in notes) |
| `Release v...`, `Merge ...` | skipped |
| anything else | `### Changed` (fallback) |

Write commit subjects accordingly when you want them to appear in the right bucket without touching `CHANGELOG.md`. If you want one wording for the commit and another for the changelog, write the manual entry — it wins.

## Release packaging

> Applies when the repository ships a NuGet package. If `__ProjectName__` is an
> app or internal library, delete `.github/workflows/release.yml` and the
> packaging properties in the `.fsproj`.

The release workflow ([.github/workflows/release.yml](.github/workflows/release.yml)) packs `.nupkg`/`.snupkg`, writes a `SHA256SUMS` manifest (standard `sha256sum -c` format), pushes the package to NuGet.org, and attaches all three artifacts to the GitHub Release. There is **no** author-signing step — NuGet.org adds its repository signature on the publisher account automatically, which is what attributes the package on the registry.

Publishing requires one repo secret: `NUGET_API_KEY` — a nuget.org API key with push permission for the `__ProjectName__` package.

Self-signed author-signing is rejected by nuget.org (`NU3018`): the author signature's chain is validated against the Microsoft Trusted Root Program. If author-signing is ever introduced, the certificate must come from a public CA (DigiCert, Sectigo, SSL.com, …) — not from `New-SelfSignedCertificate`.

## Security scanning

**CodeQL does not support F#** (its compiled-language support covers C#, not F#),
so the C# template's `codeql.yml` workflow does not carry over unchanged. Do not
add a CodeQL workflow declaring `language: fsharp` — it will fail. If you want
static analysis, rely on `TreatWarningsAsErrors` plus F# analyzers
(e.g. the [Ionide analyzers](https://github.com/ionide/ionide-analyzers)) wired
through `Directory.Build.props`, and keep dependency scanning (Dependabot /
`dotnet list package --vulnerable`) instead. If a CodeQL workflow is present from
the scaffold, treat new alerts like build warnings; dismiss confirmed false
positives in the GitHub UI with a written justification rather than weakening the
workflow.

## Version control workflow

The repo uses [jujutsu (`jj`)](https://jj-vcs.github.io/jj/) (colocated with git). Use `jj` commands; the canonical workflow:

- **Describe early.** When starting a new piece of work, immediately set the change description:
	```
	jj describe -m "Concise summary"
	```
	Small follow-ups for the same task get folded into the current change without asking — keep extending the same `jj` change, don't spawn one per edit. If the scope shifts, run `jj describe -m "..."` again so the description matches reality.
- **Unrelated work mid-task.** If the user requests something orthogonal, ask before splitting:
	- Current change finished? → `jj new -m "..."` (descendant).
	- Current change still in progress? → `jj new @- -m "..."` (parallel sibling, so you can return to the original later).
- **Sync on the user's trigger.** When the user says `pull` (or `push`/`sync`), run the full handshake:
	1. `jj git fetch` first — picks up any remote movement (CI release commits, etc.).
	2. Rebase if `main@origin` advanced: `jj rebase -r @- -d main@origin`.
	3. `jj bookmark set main -r <rev>` then `jj git push --bookmark main`.

	Never push without an explicit signal from the user.
- **Undoing dropped work.** When the user decides to abandon something already done, reach for `jj`'s safety net rather than hand-cleanup:
	- `jj undo` (alias of `jj op undo`) reverses the last operation — describe, edit, squash, rebase, abandon, push, all of it. Repeatable.
	- `jj abandon <rev>` drops a specific change entirely; descendants auto-rebase.
	- `jj restore` discards working-copy edits back to the parent's tree.
	- `jj op log` is the full reflog if you need to go further back via `jj op restore <op-id>`.
- **No new bookmarks** unless the user explicitly asks. Work lives on `main`; that is the publish target.
