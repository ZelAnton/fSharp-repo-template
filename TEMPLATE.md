# F# repository template

A starting point for F# repositories: central package management, a strict
`.editorconfig`, Fantomas formatting, cross-platform CI, an optional NuGet
release pipeline, and conventions for agents in [CLAUDE.md](CLAUDE.md) /
[AGENTS.md](AGENTS.md).

> **AI agents:** before initializing a repo from this template, read
> [docs/AGENT-INIT-GUIDE.md](docs/AGENT-INIT-GUIDE.md). It captures the mistakes
> past initialization sessions made (assuming the layout instead of reading it,
> using tabs in F# source, mishandling FSharp.Core under central package
> management, mixing shells) and is a living document you are expected to extend
> when new mistakes happen.

## Using this template

1. Create a new repository from this one (GitHub: **Use this template**), or copy
   the files into a fresh repo.
2. **Check your environment is ready.** Before initializing, confirm this machine
   has the toolchain to build and test an F# project. Use whichever matches your
   shell:

   ```pwsh
   pwsh ./scripts/check-env.ps1
   ```

   ```bash
   bash ./scripts/check-env.sh
   ```

   It checks for the .NET SDK (the major band pinned in `global.json`). If
   anything required is missing it lists the install commands for your OS and
   exits non-zero — install what it names, then re-run it. **Don't run init until
   it reports the environment is ready.**
3. Run the init script once to stamp your project name in:

   ```pwsh
   pwsh ./scripts/init.ps1 -ProjectName Acme.Widgets -Author "Jane Doe" -GitHubOwner acme -Description "Widget toolkit"
   ```

   On a POSIX shell (Linux/macOS, or git-bash) run the equivalent instead:

   ```bash
   bash ./scripts/init.sh --project-name Acme.Widgets --author "Jane Doe" --github-owner acme --description "Widget toolkit"
   ```

   `-ProjectName` / `--project-name` is required; the rest are optional and fall
   back to sensible defaults (`git config user.name`, `git config user.email`,
   `your-org`, a TODO description, the current year). The script:
   - replaces the placeholder tokens in every file's contents;
   - renames the token-named files and folders (`src/__ProjectName__`,
     `tests/__ProjectName__.Tests`, the `.fsproj`/`.slnx`/`.sln.DotSettings`);
   - activates `.claude/settings.json` from its shipped `.template` form
     (sane shared permissions for `dotnet` commands);
   - deletes `TEMPLATE.md`, `docs/AGENT-INIT-GUIDE.md`, and (unless
     `-KeepScript` / `--keep-script`) both initializers (`init.ps1` and
     `init.sh`).
4. Verify:

   ```pwsh
   dotnet tool restore
   dotnet build Acme.Widgets.slnx
   dotnet test  Acme.Widgets.slnx
   ```

5. Replace the placeholder `Greeter` module in `src/...` with your real API and
   delete the sample test.
6. **Make the agent-instruction files local to your repo.** `AGENTS.md`,
   `CLAUDE.md`, and `.claude/` are local guidance for tools, not something to
   publish — in *your* generated repo, untrack and ignore them so each developer
   keeps their own and they never reach the remote. (They stay tracked in the
   *template* repo; this is only for downstream repos.) The init script does
   **not** do this — do it by hand, before the first push:

   ```sh
   # 1) Ignore them going forward. Append last so `.claude/` overrides the
   #    earlier `!.claude/...` ship lines (last matching pattern wins).
   printf '\n/AGENTS.md\n/CLAUDE.md\n.claude/\n' >> .gitignore
   # 2) Stop tracking the copies the template committed (kept on disk).
   git rm -r --cached AGENTS.md CLAUDE.md .claude   # jj: jj file untrack AGENTS.md CLAUDE.md .claude
   git add .gitignore && git commit -m "Keep agent instructions local"   # commit the ignore rule *and* the removals together
   ```

   See [docs/AGENT-INIT-GUIDE.md](docs/AGENT-INIT-GUIDE.md) for why a `.gitignore`
   rule alone won't untrack already-committed files, an optional zero-trace
   variant, and the caveat that a repo created via **"Use this template"** already
   carries these files in its initial commit on the remote — untracking keeps them
   out of *later* commits only; for a truly clean history, copy the template into
   a fresh `git init` and untrack before the first commit.

## Placeholder tokens

| Token | Meaning |
|---|---|
| `__ProjectName__` | project / namespace / assembly / package id + file & folder names |
| `__Author__` | author (LICENSE, `<Authors>`, `<Copyright>`) |
| `__AuthorEmail__` | author email (release-commit identity in `release.yml`) |
| `__GitHubOwner__` | GitHub owner/org in repository URLs |
| `__Description__` | package description |
| `__Year__` | copyright year |

## What differs from the C# template (F#-specific)

- **F# source uses spaces, not tabs.** The F# compiler rejects tab characters in
  indentation. `.editorconfig` enforces spaces for `.fs`/`.fsi`/`.fsx`; the rest
  of the repo (`.fsproj`, `.json`, `.config`) keeps tabs.
- **Compile order is significant.** The `.fsproj` lists every `.fs` file with
  `<Compile Include="..." />` in dependency order — there is no globbing.
- **FSharp.Core is pinned and referenced explicitly.** Under central package
  management the SDK's implicit FSharp.Core reference is dropped from the
  dependency graph, so each `.fsproj` carries `<PackageReference Include="FSharp.Core" />`
  and `Directory.Packages.props` pins the version. See [AGENTS.md](AGENTS.md).
- **Fantomas, not `dotnet format`.** Formatting is enforced by Fantomas
  (`.config/dotnet-tools.json`) and checked in CI; the F# compiler does not apply
  `.editorconfig` style the way Roslyn does for C#.
- **No CodeQL.** CodeQL has no F# support, so there is no `codeql.yml`. CI relies
  on `TreatWarningsAsErrors` and Fantomas instead.

## Optional pieces — remove what you don't need

- **NuGet publishing** — if this is an app or internal library, delete
  `.github/workflows/release.yml`, `release-token-bypass.md` (the release-only
  protected-`main` recipe), and the packaging properties in the `.fsproj`
  (`PackageId`, `Authors`, `Description`, URLs, symbols, SourceLink, the README/
  CHANGELOG `Pack` items). Keep `Directory.Build.props` and CI.
- **Linux testing from Windows** — delete `scripts/test-linux.ps1` and
  `docs/linux-testing.md` if you don't need to run the Linux code path locally.
- **Rider settings** — delete `__ProjectName__.sln.DotSettings` if you don't use
  Rider/ReSharper.
- **SDK pin** — `global.json` pins the .NET SDK feature band (10.0.3xx and up via
  `rollForward: latestFeature`) so builds are reproducible and a contributor on an
  older SDK gets a clear error instead of confusing failures. The band is pinned
  one notch higher than the C# template's (10.0.1xx) on purpose: the F# compiler
  ships with the SDK, and the `FSharp.Core` pin in `Directory.Packages.props`
  (`10.1.300`) is the version bundled with the **10.0.3xx** band — pinning a lower
  floor would let a contributor compile against an older bundled FSharp.Core while
  the project deploys the pinned one (the version-mismatch trap described in
  [AGENTS.md](AGENTS.md)). Keep the two in lockstep: when you bump this band, bump
  the FSharp.Core pin to the version that band bundles. Delete `global.json` to
  always use whatever SDK is installed.
- **Dependency updates** — `.github/dependabot.yml` opens weekly PRs to bump GitHub
  Actions and the central NuGet versions in `Directory.Packages.props`. Action and
  NuGet bumps are each grouped into a single weekly PR. Remove it if you update
  dependencies by hand.
- **Community-health files** — `SECURITY.md`, `CONTRIBUTING.md`,
  `.github/PULL_REQUEST_TEMPLATE.md`, and `.github/CODEOWNERS`. Edit them to taste;
  delete any you don't want. `CODEOWNERS` ships with its rule commented out — see
  the note inside before enabling it (it must reference a real user/team).
- **YAML linting** — `.yamllint.yml` is tuned for GitHub Actions, and the CI
  `yaml-lint` job runs it on every push/PR. Run it locally with `yamllint .` (or
  `py -m yamllint .` on Windows). Delete the file and the job if you don't want it.

## Security hardening (on by default)

- **Pinned actions** — every GitHub Action is pinned to a full commit SHA (with a
  `# vN` comment), not a moving tag. Dependabot bumps the SHA and rewrites the
  comment. This blocks a re-tagged-action supply-chain attack.
- **Dependency auditing** — `Directory.Build.props` sets `NuGetAudit`/`NuGetAuditMode=all`
  so direct *and* transitive packages are checked against the NuGet advisory
  database on restore. Vulnerability findings stay warnings (not build-breaking
  errors) so a freshly disclosed CVE doesn't block every build; promote them per
  project for a hard gate.
- **NuGet Trusted Publishing (OIDC)** — the release workflow uses a long-lived
  `NUGET_API_KEY` by default, but documents how to switch to short-lived OIDC
  tokens (no stored secret). See the comment above the *Push to NuGet.org* step in
  `.github/workflows/release.yml`.
- **Release ordering** — the NuGet publish is the single irreversible step, so the
  workflow treats it as a pivot: build/test/pack and a *local-only* commit+tag run
  first, the publish happens next, and the git push + GitHub Release run after it
  (idempotent and retried). A failure before the publish leaves nothing on the
  remote or registry, so a re-run is safe; a blocked git push after publish is
  recovered by re-running (`--skip-duplicate` makes the republish a no-op). See the
  ordering note at the top of `.github/workflows/release.yml`.
- **No CodeQL** — CodeQL has no F# support, so there is no CodeQL workflow. Static
  hygiene relies on `TreatWarningsAsErrors` and Fantomas; wire up F# analyzers
  (e.g. Ionide analyzers) through `Directory.Build.props` if you want more.

## Recommended add-ons (not enabled by default)

These are intentionally left off so the template stays general; turn them on per
project.

- **AOT / trim safety** — if the library should be Native-AOT and trim friendly,
  add `<IsAotCompatible>true</IsAotCompatible>` to the library `.fsproj`. It turns
  on the trim/AOT/single-file analyzers, so (with warnings-as-errors) reflection or
  other AOT-unsafe patterns become build errors. For end-to-end verification add a
  small `tests/__ProjectName__.AotSmoke` project with `<PublishAot>true</PublishAot>`
  and a CI job that `dotnet publish`es it. (F# leans on reflection more readily than
  C# — printf-family formatting, some equality/comparison paths — so verify with a
  real AOT publish, not just the analyzers.)
- **XML documentation in the package** — add
  `<GenerateDocumentationFile>true</GenerateDocumentationFile>` to ship IntelliSense
  docs with the NuGet package. Unlike C# (CS1591), the F# compiler does not turn
  undocumented public members into warnings, so this is purely additive — it
  generates the doc file without breaking the build.

## Post-setup checklist

- [ ] Agent-instruction files (`AGENTS.md`, `CLAUDE.md`, `.claude/`) git-ignored
      and untracked so they stay local and never reach the remote — done by hand
      before the first push (step 6 above); verify with `git status` / `jj st`.
- [ ] `NUGET_API_KEY` repo secret added (only if publishing to NuGet), or
      NuGet Trusted Publishing (OIDC) configured — see `release.yml`.
- [ ] LICENSE author/year and license choice reviewed.
- [ ] `.fsproj` package metadata (description, tags, URLs) filled in.
- [ ] `SECURITY.md` reporting contact reviewed; `.github/CODEOWNERS` enabled if wanted.
- [ ] GitHub **Settings → Security → Private vulnerability reporting** enabled (for `SECURITY.md`).
- [ ] `CLAUDE.md` "Architecture" section written for your project.
- [ ] Branch protection for `main` configured — require pull requests (plus CI
      status checks). The agent docs (`CLAUDE.md` / `AGENTS.md`) already assume a
      feature-branch + PR flow into `main`. Requiring PRs blocks the release workflow's
      direct push of the release commit. The workflow pushes as a GitHub App when
      configured — add repo variable `RELEASE_APP_ID` + secret `RELEASE_APP_PRIVATE_KEY`,
      install the App, and add it to the ruleset's bypass list (recipe:
      `release-token-bypass.md`).
