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
2. Run the init script once to stamp your project name in:

   ```pwsh
   pwsh ./scripts/init.ps1 -ProjectName Acme.Widgets -Author "Jane Doe" -GitHubOwner acme -Description "Widget toolkit"
   ```

   `-ProjectName` is required; the rest are optional and fall back to sensible
   defaults (`git config user.name`, `your-org`, a TODO description, the current
   year). The script:
   - replaces the placeholder tokens in every file's contents;
   - renames the token-named files and folders (`src/__ProjectName__`,
     `tests/__ProjectName__.Tests`, the `.fsproj`/`.slnx`/`.sln.DotSettings`);
   - activates `.claude/settings.json` from its shipped `.template` form
     (sane shared permissions for `dotnet` commands);
   - deletes `TEMPLATE.md`, `docs/AGENT-INIT-GUIDE.md`, and (unless
     `-KeepScript`) itself.
3. Verify:

   ```pwsh
   dotnet tool restore
   dotnet build Acme.Widgets.slnx
   dotnet test  Acme.Widgets.slnx
   ```

4. Replace the placeholder `Greeter` module in `src/...` with your real API and
   delete the sample test.

## Placeholder tokens

| Token | Meaning |
|---|---|
| `__ProjectName__` | project / namespace / assembly / package id + file & folder names |
| `__Author__` | author (LICENSE, `<Authors>`, `<Copyright>`) |
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
  `.github/workflows/release.yml` and the packaging properties in the `.fsproj`
  (`PackageId`, `Authors`, `Description`, URLs, symbols, SourceLink, the README/
  CHANGELOG `Pack` items). Keep `Directory.Build.props` and CI.
- **Linux testing from Windows** — delete `scripts/test-linux.ps1` and
  `docs/linux-testing.md` if you don't need to run the Linux code path locally.
- **Rider settings** — delete `__ProjectName__.sln.DotSettings` if you don't use
  Rider/ReSharper.

## Post-setup checklist

- [ ] `NUGET_API_KEY` repo secret added (only if publishing to NuGet).
- [ ] LICENSE author/year and license choice reviewed.
- [ ] `.fsproj` package metadata (description, tags, URLs) filled in.
- [ ] `CLAUDE.md` "Architecture" section written for your project.
- [ ] Branch protection / required checks configured for `main` (CI).
