# AGENTS.md

## Project

- This repository contains `__ProjectName__`, an F# project.
- The public API lives in `src/__ProjectName__`.
- Tests live in `tests/__ProjectName__.Tests`.
- Keep the repository focused; do not introduce CLI, UI, hosting, logging, or dependency injection infrastructure unless explicitly requested.

## Agent instruction files are local-only in generated repos

> **Scope:** this section is for a repository **created from this template**, not
> the template itself. In the template, `AGENTS.md`, `CLAUDE.md`, and `.claude/`
> stay **tracked and pushed** — that is how the guidance ships. If you are reading
> this in the template repo, leave them tracked and do nothing.

In a generated repo, `AGENTS.md`, `CLAUDE.md`, and `.claude/` are local guidance for whoever (human or agent) works in the clone — not project source. Keep them **git-ignored and untracked** so they stay on disk for tooling but never reach the remote; each developer keeps their own. This is a **by-hand step — the init script does not do it** — done **before the first push**:

```bash
# Append last so `.claude/` overrides the earlier `!.claude/...` ship lines.
printf '\n/AGENTS.md\n/CLAUDE.md\n.claude/\n' >> .gitignore
git rm -r --cached AGENTS.md CLAUDE.md .claude
git add .gitignore && git commit -m "Keep agent instructions local"   # commit the ignore rule *and* the removals together
# jj-colocated: jj file untrack AGENTS.md CLAUDE.md .claude  (folds .gitignore + removals into the working copy; no separate commit). It only accepts already-ignored paths, so write .gitignore first.
```

`git rm --cached` keeps the files on disk; an ignore rule alone won't untrack already-committed files. `init` deletes `TEMPLATE.md` and `docs/AGENT-INIT-GUIDE.md`, so this section is the surviving copy of the recipe downstream — consult that guide while it exists for the `.gitignore` precedence details, an optional zero-trace `.git/info/exclude` variant, and the caveat that a repo created via GitHub's *Use this template* already carries these files in its initial commit's history (untracking drops them from the tip only).

## Runtime

- Use .NET (target framework `net10.0`).
- Do not change the target framework unless explicitly asked.
- Use the repository-wide language settings from `Directory.Build.props`.

## Dependencies

- Do not introduce new NuGet packages without explicit approval.
- Use centralized package management.
- Manage package versions only in `Directory.Packages.props`.
- Do not put package versions on individual `PackageReference` items.
- `Directory.Packages.props` is not a fixed allow-list — add the production and test packages the project actually needs there. `Microsoft.NET.Test.Sdk` is required for test discovery and execution through `dotnet test`; do not remove it.

### FSharp.Core under central package management

This is the one F# dependency rule that is easy to get wrong and fails silently.

- The F# SDK normally adds FSharp.Core as an **implicit** reference. Under central package management (`ManagePackageVersionsCentrally=true`) that implicit reference is **dropped from the dependency graph** — FSharp.Core then never reaches `deps.json`, the runtime cannot load it, and **NUnit discovers zero tests with no error** (`dotnet test` reports "No test is available").
- Therefore every `.fsproj` declares FSharp.Core **explicitly**: `<PackageReference Include="FSharp.Core" />` (no version on the item), and `Directory.Packages.props` carries `<PackageVersion Include="FSharp.Core" Version="..." />`.
- Pin FSharp.Core to the version that ships with the target .NET SDK (currently `10.1.300`). Do **not** pin a lower version than the SDK's compiler uses: the compiler emits references against its own FSharp.Core, and deploying an older assembly causes a `FileLoadException` at runtime.
- Symptom-to-cause: "build succeeds, 0 tests found" almost always means FSharp.Core is missing from the test project's `deps.json`. Check `bin/<cfg>/net10.0/<Tests>.deps.json` for an FSharp.Core entry.

## Architecture

- Keep all functionality available as reusable library APIs.
- Keep implementation details internal to the library (`internal` types, private modules, unexposed functions).
- Do not expose implementation types publicly unless explicitly requested.
- Prefer simple, direct code over new abstractions. Prefer module-level functions and immutable types; reach for classes/objects only when there is a concrete need (interop, IDisposable, etc.).
- Minimize public API surface area; public API changes must be intentional and documented.
- Do not add dependency injection unless there is a concrete need.

## F# compile order

- **F# resolves declarations strictly top-to-bottom.** A type or function must be declared *before* its first use, both within a file and across files.
- The order of `<Compile Include="..." />` items in the `.fsproj` **is** the dependency order. It is load-bearing, not cosmetic, and there is no globbing.
- When adding a file, insert its `<Compile>` entry after everything it depends on and before everything that depends on it. Do not rely on alphabetical order.
- Signature files (`.fsi`) must immediately precede their implementation (`.fs`) in the compile order.

## Project References

- Do not use `ProjectReference`.
- Cross-project references must use `Reference`.
- Do not use `HintPath`.
- Projects that reference outputs from other projects must define `AssemblySearchPaths`.
- `AssemblySearchPaths` must contain the output directories of referenced projects.
- Project references must resolve through assembly lookup paths only.
- Build ordering is enforced by `BuildDependency` entries in `__ProjectName__.slnx`.

## Build Ordering

- Use the `.slnx` solution format.
- `.slnx` must define build dependencies between projects.
- Referencing projects must depend on referenced projects.
- Referenced projects must build before dependent projects.
- Build ordering must be explicit and deterministic.

## Repository Structure

- Use `__ProjectName__.slnx` as the solution file.
- Use `Directory.Build.props` for repository-wide MSBuild configuration.
- Use `Directory.Packages.props` for centralized package versions.
- Keep source code under `src/`.
- Keep tests under `tests/`.
- Keep helper scripts under `scripts/`.

## MSBuild Path Properties

- `Directory.Build.props` defines two canonical path properties available to every project in the repository:
	- `$(RepoRoot)` — absolute path to the repository root, with a trailing directory separator. Resolved from `$(MSBuildThisFileDirectory)` inside `Directory.Build.props`, which always equals the directory containing that file.
	- `$(MainProjectDir)` — absolute path to `src/__ProjectName__/` (the main library project directory).
- Use these properties instead of relative constructs (`..\..\`, `$(MSBuildThisFileDirectory)..\`, etc.) whenever a project file needs to reference a file or directory outside its own directory.
- Do not hardcode cross-project or cross-directory relative paths in `.fsproj`, `.props`, or `.targets` files.
- If a new project is added that other projects must reference by path, add a corresponding `$(XxxProjectDir)` property to `Directory.Build.props`.

## Build And Test

- Use `dotnet build __ProjectName__.slnx` to validate compilation.
- Use `dotnet test tests/__ProjectName__.Tests/__ProjectName__.Tests.fsproj --no-build` to run tests after a successful build.
- Test execution must report NUnit discovery and a test summary, for example:
	- `NUnit3TestExecutor discovered ...`
	- `Passed! - Failed: 0, Passed: ..., ...`
- A successful test run must execute the discovered tests, not only complete MSBuild targets. If `dotnet test` reports "No test is available", see [FSharp.Core under central package management](#fsharpcore-under-central-package-management).
- Put NUnit tests in a **`[<TestFixture>]` type with instance `[<Test>]` members**, not in a module. A module compiles to a static class, and NUnit's discovery skips it (tests build but are never found).
- Because project-to-project references use `Reference` instead of `ProjectReference`, build ordering must come from `__ProjectName__.slnx`.

## Linux Testing (local, from Windows)

- `scripts/test-linux.ps1` runs the full test suite inside a Linux container using Rancher Desktop or Docker Desktop. It is an optional helper — remove it (and `docs/linux-testing.md`) if your project does not need it.
- Requires PowerShell 7+ and a running Docker daemon (`docker` on PATH).
- The script shadows `bin/` and `obj/` folders with anonymous Docker volumes so Windows IDE artifacts do not leak into the Linux build.
- A named volume (`__ProjectName__-nuget`) caches NuGet packages between runs.
- Supports `-Filter`, `-Configuration`, and `-Rebuild` parameters.
- Do not modify the anonymous-volume list in the script without also verifying that the Linux build still resolves `__ProjectName__.dll` correctly (the test project uses `AssemblySearchPaths` pointing to the standard `src/__ProjectName__/bin/` location).

## Formatting

- `.editorconfig` is the source of truth for indentation and line endings — follow it.
- **F# source (`.fs`/`.fsi`/`.fsx`) uses SPACES, never tabs.** The F# compiler rejects tab characters in indentation; a tab in a `.fs` file is a compile error. This is the deliberate exception to the tabs-everywhere convention of the sibling C# template.
- MSBuild/XML (`.fsproj`/`.props`/`.targets`/`.slnx`), `.json`, and `.config` use tabs.
- YAML (`.yml`/`.yaml`) and PowerShell (`.ps1`) use spaces, per `.editorconfig` (tabs are invalid in YAML).
- Do not mix tabs and spaces for indentation within a file.
- Preserve LF line endings, except Windows batch files (`.cmd`/`.bat`) which require CRLF.
- **Fantomas is the formatter.** Run `dotnet tool restore` once, then `dotnet fantomas src tests` to format and `dotnet fantomas --check src tests` to verify. CI fails on unformatted F#. Fantomas reads the `fsharp_*` keys in `.editorconfig`.

## F# Style

- Keep nullable annotations enabled (`<Nullable>enable</Nullable>` — the F# 9+ language feature, not the C# analyzer).
- Treat warnings as errors.
- Prefer module-level functions and immutable types over classes and mutable state.
- Prefer simple, direct code over new abstractions.
- Minimize public API surface area; mark implementation `internal` or `private`.
- Public API changes must be intentional and documented.

### Exception handling style

F# uses `try`/`with` and `try`/`finally` (there is no `catch` keyword, and a single `try` cannot have both `with` and `finally` — nest them).

- **No one-line `try` / `with` / `finally`.** Every `try`, `with`, and `finally` keyword must own its own block on its own lines. Forbidden:
	```fsharp
	try foo () with _ -> ()
	```
	Required:
	```fsharp
	try
	    foo ()
	with
	| :? IOException ->
	    // swallowed - pipe closed by the OS during teardown; nothing actionable.
	    ()
	```
- **Swallowing handlers must carry a comment explaining the rationale** — what exception is expected and why doing nothing is correct here. A bare `-> ()` without justification is not acceptable; `// ignored` or `// swallow` alone is not enough. The comment must explain the *rationale*, not restate the match.
	```fsharp
	try
	    cts.Cancel()
	with
	| :? ObjectDisposedException ->
	    // already disposed - being torn down concurrently; nothing to recover.
	    ()
	```
- Prefer narrow exception filters (`| :? SpecificException ->`) over a catch-all `| _ ->`. A catch-all that swallows must justify why catching everything is correct.

## Documentation

- All documentation must be written in English.
- All code comments must be written in English.
- Functional changes must include corresponding README updates when behavior, requirements, usage, or public API changes.
- README updates must reflect the current behavior of the module.
- Documentation changes must be completed after implementation and successful validation.
- Do not leave changed behavior undocumented.

## Changelog

- `CHANGELOG.md` is the single source of truth for release notes.
- The release workflow reads `## [Unreleased]` automatically to populate the GitHub Release body and the NuGet `<PackageReleaseNotes>` field.
- **Every user-visible change must be accompanied by a `CHANGELOG.md` update in the same change set.** This is non-negotiable for: new or modified public API, behavioural changes, bug fixes, deprecations, removals. Pure internal refactors that do not alter observable behaviour are the only exemption.
	- The changelog entry is part of the change, not an optional follow-up. Do not split it into a separate commit unless explicitly asked.
	- If a single change set produces multiple user-visible effects, write one bullet per effect — do not bundle.
- Add a manual bullet under `## [Unreleased]` in `CHANGELOG.md`. Use the appropriate subsection:
	- `### Added` — new features or API members
	- `### Changed` — modified behaviour or API
	- `### Fixed` — bug fixes
	- `### Removed` — removed features or API members
	- `### Deprecated` — features still present but marked for removal
- Write the entry for a consumer of the library, not the implementer. Keep it to one line.
- Replace the placeholder `-` with a real bullet; do not leave placeholder lines alongside real entries.
- Do not modify versioned sections (`## [1.0.0]`, etc.) — those are managed by the release workflow.

### Auto-fill fallback

- If `## [Unreleased]` has no real bullets at release time, the workflow auto-generates entries from commits since the previous tag using `git-cliff` (config: `cliff.toml`). Manual entries always win over auto-fill.
- The first word of the commit subject decides the bucket (case-insensitive):
	- `Add`, `Feat` → `### Added`
	- `Fix`, `Bug` → `### Fixed`
	- `Remove`, `Delete`, `Drop` → `### Removed`
	- `Refactor`, `Update`, `Change`, `Rename`, `Perf`, `CI`, `Cleanup`, etc. → `### Changed`
	- `Doc`, `Chore`, `Test`, `Style` → skipped (excluded from notes)
	- `Release v...` and merge commits → skipped
	- anything unrecognised → `### Changed` (fallback)
- Write commit subjects with these prefixes when you want them to land in the right bucket without editing `CHANGELOG.md`.
- If the auto-fill produces no entries (e.g. only skipped commits since the previous tag), the release fails with a clear error — add a manual entry to unblock it.

## Release Checksums

> Applies only when the repository ships a NuGet package. Remove this section and `.github/workflows/release.yml` for apps or internal libraries.

- The release workflow (`.github/workflows/release.yml`) does **not** author-sign the `.nupkg`/`.snupkg`. NuGet.org adds a repository signature on the publisher account automatically; that is what attributes the package to the `__ProjectName__` owner.
- A `SHA256SUMS` manifest is generated from the packed artifacts and attached to the GitHub Release. Format is the standard `<hex>  <filename>` consumed by `sha256sum -c` — this is how downstream consumers verify integrity of artifacts downloaded from the GitHub Release.
- Publishing requires one repository secret:
	- `NUGET_API_KEY` — nuget.org API key with push permission for the `__ProjectName__` package
- Do not reintroduce `dotnet nuget sign` against a self-signed certificate: nuget.org validates the author signature's certificate chain against the Microsoft Trusted Root Program and rejects self-signed packages with `NU3018`. If author-signing is brought back later, the cert must be from a public CA.

## Security Scanning

- **CodeQL does not support F#.** There is deliberately no `codeql.yml` in this template — a CodeQL workflow declaring `language: fsharp` will fail. Do not add one.
- Static analysis relies on `TreatWarningsAsErrors` (the F# compiler's own diagnostics) plus Fantomas formatting in CI. For deeper analysis, wire F# analyzers (e.g. the [Ionide analyzers](https://github.com/ionide/ionide-analyzers)) through `Directory.Build.props`.
- Keep dependency scanning instead of CodeQL. `Directory.Build.props` enables `NuGetAudit`/`NuGetAuditMode=all` (direct + transitive packages checked against the NuGet advisory database on restore; NU1901-1904 stay warnings, not build-breaking errors). `.github/dependabot.yml` opens weekly grouped PRs for Actions and central NuGet versions. `dotnet list package --vulnerable` is the ad-hoc check. Treat new vulnerability alerts like build warnings.
- Actions in `.github/workflows/*.yml` are pinned to full commit SHAs with a `# vN` comment; Dependabot bumps the SHA and the comment. Do not replace a pinned SHA with a floating tag.

## Comments

- Minimize comments.
- Write comments only when explaining:
	- why something exists
	- architectural decisions
	- non-obvious platform or runtime behavior
- Do not write comments describing what the code already says.

## Version control (jujutsu)

This repository uses [jujutsu (`jj`)](https://jj-vcs.github.io/jj/) for version control. The repo is colocated with git, but `jj` is the primary tool — use `jj` commands for everything in this workflow, not raw `git`.

### Describing the current change

- When you start a new piece of work, set the change description right away:
	```
	jj describe -m "Concise summary of what this change does"
	```
- For larger work, fold subsequent small edits into the current change without asking the user — keep extending the same change rather than starting a new one for each follow-up.
- If the scope of the current change shifts mid-work, refresh the description with another `jj describe -m "..."`. The description must always reflect what's actually being done.

### Starting unrelated work

If the user asks for something unrelated to the in-progress change:
- **Current change is complete** → propose a new change descended from it:
	```
	jj new -m "Description of the new task"
	```
- **Current change still needs more work** → propose a parallel change off the same parent so the user can come back to the current one later:
	```
	jj new @- -m "Description of the unrelated task"
	```
- Do not silently mix the two — every change must stay coherent.

### Pushing to remote

The user signals "synchronise with remote" with a short trigger word (typically `pull` or `push`). On that signal, run the full sync:
1. `jj git fetch` — pull down any remote-side movement (e.g. CI release commits or other contributors' pushes) **before** doing anything else.
2. If `main@origin` has moved past the local change, rebase: `jj rebase -r @- -d main@origin`.
3. Move the `main` bookmark to the completed change: `jj bookmark set main -r <rev>`.
4. Push: `jj git push --bookmark main`.

Never push without an explicit signal from the user.

### Undoing work

When the user decides to abandon work in progress, prefer `jj`'s native undo facilities — they are safer than hand-rolled cleanup:

- **`jj undo`** (alias of `jj op undo`) — reverses the last operation (describe / edit / squash / rebase / abandon / push / etc.). Use this when the latest step was the wrong call. It is repeatable.
- **`jj abandon <rev>`** — drops a specific change entirely. Descendants automatically rebase onto its parent.
- **`jj restore`** — discards working-copy modifications and resets `@` to its parent's tree.
- **`jj op log`** is the reflog equivalent — every operation is reachable. If `jj undo` overshoots, `jj op restore <op-id>` jumps to any prior point.

Never hide a deliberate undo: if the user asks to "undo the last commit/change", run `jj undo` (or `jj abandon`) and tell them what was reverted.

### Bookmarks

Work happens on `main`. **Do not create new bookmarks unless the user explicitly asks for one** (e.g. for a feature-branch / PR workflow). The default flow is push-to-main.

### Safety

- Do not revert or amend changes the user authored without explicit agreement.
- Do not rewrite unrelated files when making a focused change.

## Command Conventions

- Commands and APIs should be idempotent where possible.
- Output should remain concise.
- Output should remain script-friendly.
- Breaking changes must be explicit.
