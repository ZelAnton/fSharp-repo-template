# Agent guide: initializing a repo from this template

This guide is for an AI agent (Claude Code or similar) asked to "initialize a new
repository from this template." It exists because real initialization sessions
have gone wrong in avoidable ways. **Read it before touching any files.**

> **Living document — keep it accurate.** This guide is meant to grow. If you
> make a mistake while initializing a repo (or watch one happen), add it to
> [Failure log](#failure-log) below with the symptom, the root cause, and the
> rule that prevents it. Fix or sharpen existing entries when they turn out to be
> incomplete. The whole point is that the *next* agent doesn't repeat what the
> last one got wrong. See [Updating this guide](#updating-this-guide).

## TL;DR — the rules

1. **Read before you write.** Read `TEMPLATE.md`, this file, `AGENTS.md`, and
   `CLAUDE.md` *first*. Do not generate a single file based on an assumed layout.
2. **Prefer the init script over hand-rolling.** `scripts/init.ps1` is the
   supported path for a standard single-project init. Run it; don't recreate its
   work by hand.
3. **F# source is spaces, not tabs.** The compiler rejects tabs in indentation.
   `.editorconfig` already encodes this — don't "fix" `.fs` files to tabs.
4. **Respect F# compile order.** The `.fsproj` lists `.fs` files in dependency
   order; there is no globbing. New files go in the right place in `<Compile>`.
5. **FSharp.Core must be explicit under CPM** (see the dedicated section below) —
   the single most common way to ship a "builds but 0 tests" repo.
6. **Match the shell to the tool.** On Windows the Bash tool is POSIX (git bash);
   PowerShell cmdlets fail there. Use the PowerShell tool for cmdlets.
7. **Don't fight the permission model.** `.claude/settings.json` ships as a
   `.template`; activating it is the script's / user's job.
8. **Verify, then clean.** `dotnet tool restore`, `dotnet build`, `dotnet test`
   (+ `dotnet pack` if it publishes, + `dotnet fantomas --check`), then remove
   build artifacts before finishing.
9. **Agent files stay local in the new repo.** `AGENTS.md`, `CLAUDE.md`, and
   `.claude/` must become git-ignored and untracked so they never reach the new
   repository's remote. This is a **by-hand step — the init script does not do
   it** — done before the first push. See
   [Keep agent-instruction files local](#keep-agent-instruction-files-local-to-the-new-repo).

## What this template actually is

Confirm these facts by reading, not by assuming:

- It is a **token template**, not a ready project. Placeholder tokens
  (`__ProjectName__`, `__Author__`, `__AuthorEmail__`, `__GitHubOwner__`,
  `__Description__`, `__Year__`) appear in file *contents* and in file/folder *names*. They are
  substituted by `scripts/init.ps1`.
- It is **single-project** by default: one library in `src/__ProjectName__`, one
  test project in `tests/__ProjectName__.Tests`.
- Stack and conventions (all enforced — see `AGENTS.md`):
  - **net10**, **F#**, NUnit (not Expecto/xUnit), `TreatWarningsAsErrors`.
  - **`.slnx`** solution format with explicit `BuildDependency` for build order.
  - Cross-project references use **`Reference` + `AssemblySearchPaths`**, never
    `ProjectReference`, never `HintPath`.
  - **Central Package Management** — versions live only in
    `Directory.Packages.props`; `PackageReference` items carry no `Version`.
  - **FSharp.Core is referenced explicitly** in each `.fsproj` and pinned in
    `Directory.Packages.props` (see below).
  - **Spaces** in `.fs`/`.fsi`/`.fsx`; **tabs** in `.fsproj`/`.json`/`.config`;
    spaces in `.yml`/`.ps1` (see `.editorconfig`).
  - **Fantomas** formats F# and is checked in CI. **No CodeQL** (unsupported for F#).
  - Canonical MSBuild path props (`$(RepoRoot)`, `$(MainProjectDir)`) instead of `..\..\`.
- It uses **jujutsu (`jj`)** colocated with git. Drive VCS through `jj`.

## The FSharp.Core / central-package-management trap

Read this even if you do nothing else. **It fails silently.**

- With `ManagePackageVersionsCentrally=true`, the F# SDK's *implicit* FSharp.Core
  reference is dropped from the dependency graph. FSharp.Core never reaches
  `deps.json`, the test host can't load it, and `dotnet test` reports
  **"No test is available"** — a green build with zero tests run.
- The template already handles this: each `.fsproj` has
  `<PackageReference Include="FSharp.Core" />` and `Directory.Packages.props`
  pins `<PackageVersion Include="FSharp.Core" Version="..." />` to the SDK's
  bundled version. **Do not remove either half.**
- If you bump the .NET SDK and tests vanish, confirm the FSharp.Core pin matches
  the new SDK's bundled FSharp.Core, and that `bin/.../<Tests>.deps.json` lists
  FSharp.Core.

## The happy path (standard single-project init)

1. **Read** `TEMPLATE.md` and this guide. Skim `AGENTS.md` / `CLAUDE.md`.
2. **Run the init script** with the values the user gave you:

   ```pwsh
   pwsh ./scripts/init.ps1 -ProjectName Acme.Widgets -Author "Jane Doe" -GitHubOwner acme -Description "Widget toolkit"
   ```

   `-ProjectName` is required; the rest fall back to sensible defaults. The
   script substitutes tokens, renames files/folders, activates
   `.claude/settings.json` from its `.template`, and deletes `TEMPLATE.md` and
   `docs/AGENT-INIT-GUIDE.md` (and itself unless `-KeepScript`). It does **not**
   change what is tracked — making the agent files local is a separate by-hand
   step (see below).
3. **Verify**:

   ```pwsh
   dotnet tool restore
   dotnet build Acme.Widgets.slnx
   dotnet test  Acme.Widgets.slnx
   dotnet fantomas --check src tests
   ```
4. Replace the placeholder `Greeter` module with the real API, delete the sample
   test, fill in the `CLAUDE.md` "Architecture" section, and work through the
   `TEMPLATE.md` post-setup checklist.
5. **Make the agent-instruction files local** — git-ignore and untrack
   `AGENTS.md` / `CLAUDE.md` / `.claude/` so they stay on disk but never reach the
   remote, then commit. This is a by-hand step; see
   [Keep agent-instruction files local](#keep-agent-instruction-files-local-to-the-new-repo).
6. Remove build artifacts (`bin/`, `obj/`, any `artifacts/`) before finishing.

If the user only asks to "initialize from the template" with a project name and
nothing structurally unusual, **this is the whole job.** Resist the urge to
redesign.

## Keep agent-instruction files local to the new repo

`AGENTS.md`, `CLAUDE.md`, and `.claude/` are guidance for whoever (human or agent)
works in a checkout — they are **not** project source. In a repo created from this
template they must be **git-ignored and untracked** so they never reach that
repo's remote: each developer keeps their own, and the shared history is not
polluted with one contributor's agent config.

This applies **only to the initialized project**, not to the template repository
itself — in the template these files stay tracked and pushed (that is how the
guidance ships). Do not "fix" the template by un-tracking them here.

This is **instruction-only — there is no script step.** `scripts/init.ps1` does
*not* touch tracking; you do this by hand after running it (or after a by-hand
init), **before the first push.**

Which files: `AGENTS.md`, `CLAUDE.md`, and the `.claude/` directory (after the
init script activates `settings.json`). Include any other agent-instruction files
you add later — e.g. `.cursorrules`, `.github/copilot-instructions.md`.
(`TEMPLATE.md` and this guide are template-only and the init script deletes them
outright, so they need no handling.)

### Untrack and ignore them

Two facts make this more than a one-line `.gitignore` append:

1. The files start out *tracked* (the template committed `AGENTS.md`, `CLAUDE.md`,
   and `.claude/settings.json.template`; the init script renames the last to
   `.claude/settings.json`). An ignore rule never untracks an already-tracked
   file — you must also drop it from the index.
2. The template's `.gitignore` **deliberately ships** `.claude/settings.json`
   (`.claude/*` followed by `!.claude/settings.json` …). So you must *either*
   append `.claude/` **after** that block (a later directory-exclude overrides the
   negations) *or* delete the negation lines. A plain ignore placed *before* them
   won't hide `.claude/settings.json`.

Append the ignore patterns, then untrack (working copy kept), then commit:

```bash
# Appended last so `.claude/` overrides the earlier `!.claude/...` ship lines.
printf '\n/AGENTS.md\n/CLAUDE.md\n.claude/\n' >> .gitignore
git rm -r --cached AGENTS.md CLAUDE.md .claude   # jj-colocated: jj file untrack AGENTS.md CLAUDE.md .claude
git add .gitignore && git commit -m "Keep agent instructions local"   # commit the ignore rule *and* the removals together
```

`jj file untrack` only drops paths *already* matched by an ignore rule, so add the
patterns first (jj honors `.gitignore` and `.git/info/exclude` alike).

**Zero filename trace in the remote (optional).** `AGENTS.md` and `CLAUDE.md`
aren't referenced anywhere in the tracked `.gitignore`, so you can instead keep
*them* in a local, never-pushed `.git/info/exclude` — then their names never
appear in the pushed repo (trade-off: it is per-clone, so a fresh clone re-tracks
them and you re-apply):

```bash
printf '/AGENTS.md\n/CLAUDE.md\n' >> .git/info/exclude
git rm --cached AGENTS.md CLAUDE.md
```

`.claude` can't use this route — the ship-negations outrank `.git/info/exclude`,
so its rule still has to live in (or be removed from) the tracked `.gitignore` as
above.

Verify with `git status` (or `jj st`): the files must not appear as tracked or as
new/untracked-to-be-added, and a `git push` must not carry them.

**Caveat — files already in the remote's history.** Untrack-and-ignore stops the
files from going *forward* in new commits, which is what matters day to day. But a
repo created via GitHub's **"Use this template"** (or any flow that already pushed
an initial commit) already has the template's copies in that first commit on the
remote — removing them now drops them from the tip but they survive in history.
For a repo that has **never** contained them, copy the template files into a fresh
`git init` and untrack *before* the first commit; or, starting from a pushed "Use
this template" repo, fold the removal into the initial commit (amend it) before
the first push you control.

## When you must deviate (e.g. multiple projects)

The init script assumes one project. If the user wants several (e.g. three
libraries, each its own NuGet package), the script's single-token substitution
won't fit, so you adapt by hand — but still respect every convention above:

- One folder per library under `src/`, one matching test project under `tests/`.
- Put **shared packaging metadata once** in `src/Directory.Build.props` (authors,
  license, URLs, symbols, SourceLink, README/CHANGELOG pack items). Each library
  `.fsproj` then carries only `PackageId`, `Description`, `PackageTags`.
- Keep a single shared `<Version>` (in `Directory.Build.props`), not per-project.
- Every `.fsproj` still needs `<PackageReference Include="FSharp.Core" />`.
- Add a `BuildDependency` per test→library pair in the `.slnx`.
- Give each test project an `AssemblySearchPaths` pointing at its library's
  output; add a matching `$(XxxProjectDir)` property in `Directory.Build.props`.
- The release workflow should pack the **solution**, not a single hard-coded
  `.fsproj`.
- Git-ignore and untrack the agent-instruction files (`AGENTS.md` / `CLAUDE.md` /
  `.claude/`) — a by-hand step on every path (see
  [Keep agent-instruction files local](#keep-agent-instruction-files-local-to-the-new-repo)).
- Still verify with build + test + pack, then clean artifacts.

Whatever you change, update `AGENTS.md` / `CLAUDE.md` so they describe the layout
you actually produced.

## Tooling discipline (this is where agents slip)

- **Shell ≠ shell.** The Bash tool runs POSIX (git bash) here. `Get-ChildItem`,
  `Select-Object`, etc. fail in it with `command not found`. Use the PowerShell
  tool for cmdlets and the Bash tool only for POSIX commands. Prefer the
  dedicated Read / Glob / Grep tools over either shell for file inspection.
- **Don't over-batch.** A failure in one call of a parallel batch can cancel the
  rest. Never put *exploratory* calls or calls that *depend on each other* in the
  same batch as file writes. Read and ask first; write once you know the answers.
- **Permission model.** Do not write permission allow-rules into
  `.claude/settings.json` yourself — the self-modification classifier will (and
  should) block it. The template ships `.claude/settings.json.template`; the init
  script activates it, or the user does.
- **VCS.** The repo is jj-colocated. Use `jj` commands; if you must use raw git,
  follow with `jj git import`.

## Updating this guide

When something goes wrong during an init — yours or one you review — do this in
the **same change set**, not as a follow-up:

1. Add an entry to [Failure log](#failure-log): the symptom (what was observed),
   the root cause (why it happened), and the rule (what to do instead).
2. If the lesson generalizes, also fold it into the TL;DR or the relevant section
   above so it's seen in the normal reading flow, not just the log.
3. If `scripts/init.ps1`, `TEMPLATE.md`, `AGENTS.md`, or `CLAUDE.md` could be
   changed to make the mistake *impossible* (rather than merely documented),
   prefer that fix and note it in the entry.

Keep entries short and concrete. Delete or rewrite an entry if it turns out to be
wrong or obsolete.

## Failure log

Newest first. Each entry: **Symptom → Root cause → Rule.**

### 2026-05-31 — `dotnet test` reported "No test is available" (0 tests, green build)
- **Symptom:** Build succeeded, but NUnit discovered zero tests. The fixture and
  `[<Test>]` attribute were present in the compiled assembly, yet nothing ran.
- **Root cause:** Under Central Package Management the F# SDK's implicit
  FSharp.Core reference was dropped from the dependency graph, so FSharp.Core was
  absent from the test project's `deps.json`. The test host could not load
  FSharp.Core, so it could not load the test types — and reported no tests rather
  than an error. A first attempt that pinned FSharp.Core to a version *below* the
  SDK's bundled one made it worse (compiler referenced the SDK version, a lower
  assembly was deployed → `FileLoadException`).
- **Rule:** Declare FSharp.Core explicitly in every `.fsproj`
  (`<PackageReference Include="FSharp.Core" />`) and pin its `PackageVersion` to
  the SDK's bundled version. See
  [The FSharp.Core / central-package-management trap](#the-fsharpcore--central-package-management-trap).

### 2026-05-31 — NUnit found no tests in an F# *module*
- **Symptom:** Tests written as `[<Test>] let` functions in a `module` were never
  discovered.
- **Root cause:** An F# module compiles to a static class; NUnit's discovery
  skips static classes.
- **Rule:** Use a `[<TestFixture>]` **type** with instance `[<Test>]` members.
