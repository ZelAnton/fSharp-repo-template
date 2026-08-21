#!/usr/bin/env python3
"""Executable, offline release-identity and recovery scenarios."""

from __future__ import annotations

import http.server
import pathlib
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


def make_package(path: pathlib.Path, package_id: str, version: str, commit: str, payload: str) -> None:
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
    def test_package_identity_and_retry_recovery(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            package = root / "Acme.Widgets.1.2.3.nupkg"
            make_package(package, "Acme.Widgets", "1.2.3", "a" * 40, "release")
            output = root / "first-output.txt"
            with Feed([(404, b""), (200, package.read_bytes())]) as feed:
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
            make_package(remote, "Acme.Widgets", "1.2.3", "b" * 40, "different")
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
            make_package(occupied, "Acme.Widgets", "1.2.3", "d" * 40, "release")
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
