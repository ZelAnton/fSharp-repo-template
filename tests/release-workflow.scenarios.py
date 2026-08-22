#!/usr/bin/env python3
"""Executable, offline release-identity and recovery scenarios."""

from __future__ import annotations

import http.server
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
VERIFIER = ROOT / "scripts" / "verify-nuget-package.py"


def run(command: list[str], cwd: pathlib.Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, check=check, text=True, capture_output=True)


def make_package(
    path: pathlib.Path,
    package_id: str,
    version: str,
    commit: str,
    payload: str,
    signature: bytes | None = None,
) -> None:
    nuspec = f"""<?xml version="1.0" encoding="utf-8"?>
<package>
  <metadata>
    <id>{package_id}</id>
    <version>{version}</version>
    <repository type="git" url="https://example.invalid/repo" commit="{commit}" />
  </metadata>
</package>
"""
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(f"{package_id}.nuspec", nuspec)
        archive.writestr("lib/net10.0/package.txt", payload)
        if signature is not None:
            archive.writestr(".signature.p7s", signature)


class FeedHandler(http.server.BaseHTTPRequestHandler):
    responses: list[tuple[int, bytes]] = []

    def do_GET(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
        if self.responses:
            status, body = self.responses.pop(0)
        else:
            status, body = 500, b"unexpected request"
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args: object) -> None:
        return


class Feed:
    def __init__(self, responses: list[tuple[int, bytes]]) -> None:
        handler = type("ScenarioFeedHandler", (FeedHandler,), {"responses": responses})
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self) -> str:
        self.thread.start()
        return f"http://127.0.0.1:{self.server.server_port}"

    def __exit__(self, *_args: object) -> None:
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()


def verify(
    package: pathlib.Path,
    expected_commit: str,
    feed: str,
    allow_missing: bool = False,
    output: pathlib.Path | None = None,
) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable,
        str(VERIFIER),
        "--package",
        str(package),
        "--package-id",
        "Acme.Widgets",
        "--version",
        "1.2.3",
        "--expected-commit",
        expected_commit,
        "--feed-base-url",
        feed,
    ]
    if allow_missing:
        command.append("--allow-missing")
    if output:
        command.extend(["--github-output", str(output)])
    return run(command, ROOT, check=False)


class ReleaseWorkflowScenarios(unittest.TestCase):
    def test_metadata_preflight_rejects_all_template_defaults_before_build(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text()
        checkout = workflow.index("      - uses: actions/checkout")
        preflight_start = workflow.index("      - name: Preflight ", checkout)
        setup_dotnet = workflow.index("      - uses: actions/setup-dotnet", preflight_start)
        build = workflow.index("      - name: Build")
        pack = workflow.index("      - name: Pack")
        publish = workflow.index("      - name: Push to NuGet.org (irreversible pivot)")
        preflight = workflow[preflight_start:setup_dotnet]
        self.assertLess(preflight_start, setup_dotnet)
        self.assertLess(setup_dotnet, build)
        self.assertLess(build, pack)
        self.assertLess(pack, publish)
        markers = (
            "__ProjectName__",
            "__GitHubOwner__",
            "__Author__",
            "__AuthorEmail__",
            "__Description__",
            "your-org",
            "Your Name",
            "TODO: project description",
        )
        for marker in markers:
            self.assertIn(marker, preflight)

        run_start = preflight.index("        run: |\n") + len("        run: |\n")
        script = []
        for line in preflight[run_start:].splitlines():
            if line.strip() == "":
                script.append("")
            elif not line.startswith("          "):
                break
            else:
                script.append(line[10:])
        script = "\n".join(script).replace("\r", "") + "\n"
        python_start = script.index("python3 <<'PY'\n") + len("python3 <<'PY'\n")
        python_script = script[python_start : script.index("\nPY\n", python_start)]

        with tempfile.TemporaryDirectory() as directory:
            fixture = pathlib.Path(directory)
            for relative in (
                "README.md",
                "CHANGELOG.md",
                "LICENSE",
                ".github/CODEOWNERS",
                ".github/workflows/release.yml",
                "Directory.Build.props",
                "Directory.Packages.props",
                "Acme.slnx",
                "src/Acme/Acme.fsproj",
            ):
                path = fixture / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("Acme\n", encoding="utf-8")
            passed = subprocess.run(
                [sys.executable], cwd=fixture, input=python_script, text=True, capture_output=True, check=False
            )
            self.assertEqual(passed.returncode, 0, passed.stderr)

            contaminated = fixture / "README.md"
            contaminated.write_text("description: TODO: project description\n", encoding="utf-8")
            failed = subprocess.run(
                [sys.executable], cwd=fixture, input=python_script, text=True, capture_output=True, check=False
            )
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("TODO: project description", failed.stdout)

    def test_first_release_uses_full_history_without_synthetic_tag(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text()

        self.assertNotIn("Ensure previous tag exists", workflow)
        self.assertNotIn('CURRENT="0.0.0"', workflow)
        self.assertIn('echo "previous_tag=$LATEST_TAG" >> "$GITHUB_OUTPUT"', workflow)

        auto_fill_start = workflow.index("      - name: Auto-fill [Unreleased] from git log if empty")
        auto_fill_end = workflow.index("\n      - name:", auto_fill_start + 1)
        auto_fill = workflow[auto_fill_start:auto_fill_end]
        self.assertIn('PREV_TAG: ${{ steps.version.outputs.previous_tag }}', auto_fill)
        self.assertIn('command = ["git-cliff", "--config", "cliff.toml", "--strip", "all"]', auto_fill)
        self.assertIn('if prev_tag:', auto_fill)
        self.assertIn('command.append(f"{prev_tag}..HEAD")', auto_fill)
        self.assertIn('generating from the full git history for the first release', auto_fill)

    def test_first_release_applies_selected_bump_to_project_seed(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text()
        version_start = workflow.index("      - name: Determine next version")
        version_end = workflow.index("\n      - name: Verify tag does not exist", version_start)
        version_step = workflow[version_start:version_end]
        run_start = version_step.index("        run: |\n") + len("        run: |\n")
        script_lines = []
        for line in version_step[run_start:].splitlines():
            if not line.startswith("          "):
                break
            script_lines.append(line[10:])
        script = "\n".join(script_lines).replace("${{ inputs.bump }}", "$INPUT_BUMP") + "\n"
        bash = shutil.which("bash")
        self.assertIsNotNone(bash, "bash is required to execute the first-release version selector")

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            project = root / "src" / "__ProjectName__"
            project.mkdir(parents=True)
            (project / "__ProjectName__.fsproj").write_text(
                "<Project><PropertyGroup><Version>0.1.0</Version></PropertyGroup></Project>\n",
                encoding="utf-8",
            )
            run(["git", "init", "-q"], root)
            run(["git", "config", "user.email", "test@example.invalid"], root)
            run(["git", "config", "user.name", "Release Test"], root)
            run(["git", "add", "."], root)
            run(["git", "commit", "-qm", "seed"], root)

            for bump, expected in (("patch", "0.1.1"), ("minor", "0.2.0"), ("major", "1.0.0")):
                output_name = f"{bump}-output.txt"
                output = root / output_name
                invocation = (
                    f"INPUT_BUMP={shlex.quote(bump)} GITHUB_OUTPUT={shlex.quote(output_name)}\n"
                    f"{script}"
                )
                result = subprocess.run(
                    [bash],
                    cwd=root,
                    check=False,
                    input=invocation.encode(),
                    capture_output=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                self.assertIn(f"version={expected}", output.read_text())
                self.assertIn(f"{bump} bump -> {expected}", result.stdout.decode())

    def test_git_cliff_uses_an_exact_verified_release_pin(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text()
        source_identity = workflow.index("      - name: Capture release source identity")
        install_start = workflow.index("      - name: Install git-cliff")
        auto_fill = workflow.index("      - name: Auto-fill [Unreleased] from git log if empty")
        commit = workflow.index("      - name: Commit and tag the release (local only)")
        pivot = workflow.index("      - name: Push to NuGet.org (irreversible pivot)")
        install = workflow[install_start:auto_fill]

        self.assertLess(source_identity, install_start)
        self.assertLess(install_start, auto_fill)
        self.assertLess(install_start, commit)
        self.assertLess(install_start, pivot)
        self.assertIn("tool: git-cliff@2.13.1", install)
        self.assertNotRegex(install, r"tool:\s+git-cliff@2(?:\s|$)")
        self.assertEqual(len(re.findall(r"tool:\s+git-cliff@\S+", install)), 1)

    def test_first_release_changelog_link_points_to_published_tag(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text()
        promote_start = workflow.index("      - name: Promote Unreleased section in CHANGELOG.md")
        promote_end = workflow.index("\n      # Create the release commit", promote_start)
        promote = workflow[promote_start:promote_end]

        self.assertIn('PREV_TAG: ${{ steps.version.outputs.previous_tag }}', promote)
        self.assertIn('f"[{version}]: {repo}/releases/tag/{tag}"', promote)
        self.assertIn('f"[{version}]: {repo}/compare/{prev_tag}...{tag}"', promote)
        self.assertNotIn("compare/{prev_tag}...{tag}\"\n\"", promote)

    def test_final_changelog_is_packed_after_promotion(self) -> None:
        project = (ROOT / "src" / "__ProjectName__" / "__ProjectName__.fsproj").read_text()
        workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text()

        self.assertIn(
            '<None Include="$(RepoRoot)CHANGELOG.md" Pack="true" PackagePath="\\" />',
            project,
        )

        promote = workflow.index("      - name: Promote Unreleased section in CHANGELOG.md")
        commit = workflow.index("      - name: Commit and tag the release (local only)")
        pack = workflow.index("      - name: Pack")
        verify = workflow.index("      - name: Verify packed final CHANGELOG")
        checksums = workflow.index("      - name: Generate SHA256SUMS")
        pivot = workflow.index("      - name: Push to NuGet.org (irreversible pivot)")
        self.assertLess(promote, commit)
        self.assertLess(commit, pack)
        self.assertLess(pack, verify)
        self.assertLess(verify, checksums)
        self.assertLess(checksums, pivot)

        verification = workflow[verify:checksums]
        self.assertIn('glob("*.nupkg")', verification)
        self.assertIn('archive.read("CHANGELOG.md")', verification)
        self.assertIn('pathlib.Path("CHANGELOG.md").read_bytes()', verification)
        self.assertIn('f"## [{version}] - ".encode()', verification)
        self.assertIn("packed != expected", verification)

    def test_release_notes_are_an_explicit_pack_input(self) -> None:
        project = (ROOT / "src" / "__ProjectName__" / "__ProjectName__.fsproj").read_text()
        workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text()

        self.assertIn(
            '<PackageReleaseNotes Condition="\'$(PackageReleaseNotesFile)\' != \'\'">'
            "$([System.IO.File]::ReadAllText('$(PackageReleaseNotesFile)'))"
            "</PackageReleaseNotes>",
            project,
        )
        self.assertNotIn("Exists('$(RepoRoot)release-notes.md')", project)
        self.assertNotIn("ReadAllText('$(RepoRoot)release-notes.md')", project)
        self.assertIn(
            "/p:PackageReleaseNotesFile=release-notes.md",
            workflow,
        )

    def test_release_tag_selection_is_strict_and_reachable(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text()
        selection_start = workflow.index('          LATEST_TAG=""')
        selection_end = workflow.index('          if [[ -n "$LATEST_TAG" ]]', selection_start)
        selection = workflow[selection_start:selection_end]
        selection = "set -euo pipefail\n" + re.sub(r"^ {10}", "", selection, flags=re.MULTILINE)
        selection += 'printf \'%s\\n\' "$LATEST_TAG"\n'

        bash = shutil.which("bash")
        self.assertIsNotNone(bash, "bash is required to execute the release workflow selector")

        with tempfile.TemporaryDirectory() as directory:
            repository = pathlib.Path(directory)
            run(["git", "init", "-q"], repository)
            run(["git", "config", "user.email", "test@example.invalid"], repository)
            run(["git", "config", "user.name", "Release Test"], repository)

            (repository / "source.txt").write_text("root\n")
            run(["git", "add", "source.txt"], repository)
            run(["git", "commit", "-qm", "root"], repository)
            root_commit = run(["git", "rev-parse", "HEAD"], repository).stdout.strip()
            run(["git", "tag", "v1.9.9", root_commit], repository)

            (repository / "source.txt").write_text("main\n")
            run(["git", "commit", "-qam", "main"], repository)
            main_commit = run(["git", "rev-parse", "HEAD"], repository).stdout.strip()
            run(["git", "tag", "v1.10.0", main_commit], repository)
            run(["git", "tag", "v100.0.0-rc.1", main_commit], repository)
            run(["git", "tag", "v01.20.30", main_commit], repository)
            run(["git", "tag", "v1.10.0.1", main_commit], repository)

            run(["git", "checkout", "-qb", "unreleased", root_commit], repository)
            (repository / "source.txt").write_text("unreleased\n")
            run(["git", "commit", "-qam", "unreleased"], repository)
            unreachable_commit = run(["git", "rev-parse", "HEAD"], repository).stdout.strip()
            run(["git", "tag", "v999.0.0", unreachable_commit], repository)
            run(["git", "checkout", "-q", "-B", "main", main_commit], repository)

            result = subprocess.run(
                [bash],
                cwd=repository,
                check=False,
                input=selection.encode(),
                capture_output=True,
            )

        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(result.stdout.decode().strip(), "v1.10.0")

    def test_release_ref_guard_treats_ref_as_environment_data(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text()
        guard_start = workflow.index("      - name: Guard ")
        guard_end = workflow.index("\n      - name:", guard_start + 1)
        guard = workflow[guard_start:guard_end]
        run_start = guard.index("        run: |\n") + len("        run: |\n")
        run_lines = []
        for line in guard[run_start:].splitlines():
            if not line.startswith("          "):
                break
            run_lines.append(line[10:])
        script = "\n".join(run_lines) + "\n"

        self.assertIn("        env:\n          RELEASE_REF: ${{ github.ref }}", guard)
        self.assertNotIn("${{ github.ref }}", script)
        self.assertIn('[[ "$RELEASE_REF" != "refs/heads/main" ]]', script)

        bash = shutil.which("bash")
        self.assertIsNotNone(bash, "bash is required to execute the release ref guard")

        malicious_ref = "refs/heads/evil$(printf injected >&2)"
        rejected = subprocess.run(
            [bash],
            cwd=ROOT,
            check=False,
            input=(f"RELEASE_REF={shlex.quote(malicious_ref)}\n{script}").encode(),
            capture_output=True,
        )

        self.assertNotEqual(rejected.returncode, 0)
        self.assertNotIn("injected", rejected.stderr.decode())
        self.assertIn(malicious_ref, rejected.stdout.decode())

        accepted = subprocess.run(
            [bash],
            cwd=ROOT,
            check=False,
            input=(f"RELEASE_REF={shlex.quote('refs/heads/main')}\n{script}").encode(),
            capture_output=True,
        )

        self.assertEqual(accepted.returncode, 0, accepted.stderr.decode())
        self.assertIn("Dispatched from main.", accepted.stdout.decode())

    def test_package_identity_and_retry_recovery(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            package = root / "Acme.Widgets.1.2.3.nupkg"
            published = root / "published.nupkg"
            make_package(package, "Acme.Widgets", "1.2.3", "a" * 40, "release")
            make_package(
                published,
                "Acme.Widgets",
                "1.2.3",
                "a" * 40,
                "release",
                signature=b"NuGet.org repository signature",
            )
            output = root / "first-output.txt"
            with Feed([(404, b""), (200, published.read_bytes())]) as feed:
                first = verify(package, "a" * 40, feed, allow_missing=True, output=output)
                second = verify(package, "a" * 40, feed, output=output)

            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertIn("existing=false", output.read_text())
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertIn("existing=true", output.read_text())

    def test_mismatch_fails_closed_before_release_continuation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            local = root / "local.nupkg"
            remote = root / "remote.nupkg"
            make_package(local, "Acme.Widgets", "1.2.3", "b" * 40, "release")
            make_package(
                remote,
                "Acme.Widgets",
                "1.2.3",
                "b" * 40,
                "different",
                signature=b"NuGet.org repository signature",
            )
            with Feed([(200, remote.read_bytes())]) as feed:
                result = verify(local, "b" * 40, feed)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("expected", result.stderr)

    def test_shifted_main_cannot_reuse_the_published_identity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            repository = root / "repo"
            repository.mkdir()
            run(["git", "init", "-q"], repository)
            run(["git", "config", "user.email", "test@example.invalid"], repository)
            run(["git", "config", "user.name", "Release Test"], repository)
            (repository / "source.txt").write_text("release source\n")
            run(["git", "add", "source.txt"], repository)
            run(["git", "commit", "-qm", "source"], repository)
            original = run(["git", "rev-parse", "HEAD"], repository).stdout.strip()
            (repository / "source.txt").write_text("shifted main\n")
            run(["git", "commit", "-qam", "shift main"], repository)
            shifted = run(["git", "rev-parse", "HEAD"], repository).stdout.strip()
            package = root / "published.nupkg"
            make_package(package, "Acme.Widgets", "1.2.3", original, "release")

            with Feed([(404, b"")]) as feed:
                accepted = verify(package, original, feed, allow_missing=True)
            with Feed([(404, b"")]) as feed:
                rejected = verify(package, shifted, feed, allow_missing=True)

            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("does not match", rejected.stderr)

    def test_occupied_version_with_different_commit_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            local = root / "local.nupkg"
            occupied = root / "occupied.nupkg"
            make_package(local, "Acme.Widgets", "1.2.3", "c" * 40, "release")
            make_package(
                occupied,
                "Acme.Widgets",
                "1.2.3",
                "d" * 40,
                "release",
                signature=b"NuGet.org repository signature",
            )
            with Feed([(200, occupied.read_bytes())]) as feed:
                result = verify(local, "c" * 40, feed)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("expected", result.stderr)

    def test_partial_vcs_github_completion_retains_exact_recovery_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            repository = root / "repo"
            repository.mkdir()
            run(["git", "init", "-q"], repository)
            run(["git", "config", "user.email", "test@example.invalid"], repository)
            run(["git", "config", "user.name", "Release Test"], repository)
            (repository / "release.txt").write_text("exact release\n")
            run(["git", "add", "release.txt"], repository)
            run(["git", "commit", "-qm", "release"], repository)
            release_commit = run(["git", "rev-parse", "HEAD"], repository).stdout.strip()
            run(["git", "tag", "v1.2.3"], repository)
            bundle = root / "release-recovery.bundle"
            run(["git", "bundle", "create", str(bundle), "HEAD", "v1.2.3"], repository)
            run(["git", "bundle", "verify", str(bundle)], repository)

            seed = root / "seed"
            seed.mkdir()
            run(["git", "init", "-q"], seed)
            run(["git", "config", "user.email", "test@example.invalid"], seed)
            run(["git", "config", "user.name", "Release Test"], seed)
            (seed / "remote.txt").write_text("remote moved main\n")
            run(["git", "add", "remote.txt"], seed)
            run(["git", "commit", "-qm", "move main"], seed)
            run(["git", "branch", "-M", "main"], seed)
            remote = root / "origin.git"
            run(["git", "clone", "-q", "--bare", str(seed), str(remote)], root)
            run(["git", "remote", "add", "origin", str(remote)], repository)
            push = run(
                ["git", "push", "--atomic", "origin", "HEAD:refs/heads/main", "v1.2.3"],
                repository,
                check=False,
            )
            self.assertNotEqual(push.returncode, 0)
            remote_main = run(["git", "--git-dir", str(remote), "rev-parse", "refs/heads/main"], root)
            self.assertEqual(remote_main.stdout.strip(), run(["git", "rev-parse", "HEAD"], seed).stdout.strip())
            missing_tag = run(
                ["git", "--git-dir", str(remote), "show-ref", "--verify", "refs/tags/v1.2.3"],
                root,
                check=False,
            )
            self.assertNotEqual(missing_tag.returncode, 0)

            recovered = root / "recovered"
            run(["git", "clone", "-q", str(bundle), str(recovered)], root)
            recovered_commit = run(["git", "rev-parse", "v1.2.3"], recovered).stdout.strip()
            self.assertEqual(recovered_commit, release_commit)
            self.assertEqual((recovered / "release.txt").read_text(), "exact release\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
