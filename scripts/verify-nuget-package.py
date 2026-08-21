#!/usr/bin/env python3
"""Verify that a NuGet version still identifies the package built by this run."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from typing import NoReturn
from xml.etree import ElementTree


def fail(message: str) -> NoReturn:
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def content_sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    try:
        with zipfile.ZipFile(path) as archive:
            for name in sorted(archive.namelist()):
                canonical_name = re.sub(
                    r"package/services/metadata/core-properties/[0-9a-f]+\.psmdcp$",
                    "package/services/metadata/core-properties/IDENTITY.psmdcp",
                    name,
                    flags=re.IGNORECASE,
                )
                if name == "_rels/.rels":
                    content = re.sub(
                        rb"/package/services/metadata/core-properties/[0-9a-f]+\.psmdcp",
                        b"/package/services/metadata/core-properties/IDENTITY.psmdcp",
                        archive.read(name),
                        flags=re.IGNORECASE,
                    )
                    content = re.sub(
                        rb'(<Relationship[^>]*metadata/core-properties[^>]*\bId=")R[0-9A-F]+(")',
                        rb'\1RCOREPROPERTIES\2',
                        content,
                        flags=re.IGNORECASE,
                    )
                else:
                    content = archive.read(name)
                digest.update(canonical_name.encode("utf-8"))
                digest.update(b"\0")
                digest.update(len(content).to_bytes(8, "big"))
                digest.update(content)
    except (OSError, zipfile.BadZipFile) as error:
        fail(f"Could not hash package contents from {path}: {error}")
    return digest.hexdigest()


def repository_commit(path: pathlib.Path) -> str:
    try:
        with zipfile.ZipFile(path) as archive:
            nuspecs = [name for name in archive.namelist() if name.lower().endswith(".nuspec")]
            if len(nuspecs) != 1:
                fail(f"Expected exactly one nuspec in {path}, found {len(nuspecs)}")
            root = ElementTree.fromstring(archive.read(nuspecs[0]))
    except (OSError, zipfile.BadZipFile, ElementTree.ParseError) as error:
        fail(f"Could not read package metadata from {path}: {error}")

    for element in root.iter():
        if element.tag.rsplit("}", 1)[-1] == "repository":
            commit = element.attrib.get("commit", "").strip()
            if commit:
                return commit

    fail(f"Package {path} has no repository commit metadata")


def write_output(path: str | None, key: str, value: str) -> None:
    if path:
        with pathlib.Path(path).open("a", encoding="utf-8") as output:
            output.write(f"{key}={value}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True, type=pathlib.Path)
    parser.add_argument("--package-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--allow-missing", action="store_true")
    parser.add_argument(
        "--feed-base-url",
        default="https://api.nuget.org/v3-flatcontainer",
        help=argparse.SUPPRESS,
    )
    parser.add_argument("--github-output")
    args = parser.parse_args()

    if not args.package.is_file():
        fail(f"Expected package does not exist: {args.package}")

    expected_sha = content_sha256(args.package)
    local_commit = repository_commit(args.package)
    if local_commit.lower() != args.expected_commit.lower():
        fail(
            f"Local package repository commit {local_commit} does not match "
            f"release commit {args.expected_commit}"
        )

    package_id = urllib.parse.quote(args.package_id.lower(), safe="")
    version = urllib.parse.quote(args.version.lower(), safe="")
    url = (
        f"{args.feed_base_url.rstrip('/')}/{package_id}/{version}/"
        f"{package_id}.{version}.nupkg"
    )

    downloaded_path: pathlib.Path | None = None
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            with tempfile.NamedTemporaryFile(suffix=".nupkg", delete=False) as downloaded:
                downloaded_path = pathlib.Path(downloaded.name)
                while chunk := response.read(1024 * 1024):
                    downloaded.write(chunk)
                downloaded.flush()
            actual_sha = content_sha256(downloaded_path)
            if actual_sha != expected_sha:
                fail(
                    f"NuGet package {args.package_id} {args.version} has content digest "
                    f"{actual_sha}, expected {expected_sha}"
                )
            remote_commit = repository_commit(downloaded_path)
    except urllib.error.HTTPError as error:
        if error.code == 404 and args.allow_missing:
            print(f"No existing NuGet package found for {args.package_id} {args.version}.")
            write_output(args.github_output, "existing", "false")
            write_output(args.github_output, "content-sha256", expected_sha)
            write_output(args.github_output, "commit", args.expected_commit)
            return
        fail(f"NuGet package lookup failed with HTTP {error.code}; refusing to continue")
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        fail(f"NuGet package lookup failed; refusing to continue: {error}")
    finally:
        if downloaded_path is not None:
            try:
                downloaded_path.unlink(missing_ok=True)
            except OSError:
                pass

    if remote_commit.lower() != args.expected_commit.lower():
        fail(
            f"NuGet package repository commit {remote_commit} does not match "
            f"release commit {args.expected_commit}"
        )

    print(
        f"Verified NuGet package {args.package_id} {args.version}: "
        f"commit {args.expected_commit}, content digest {expected_sha}."
    )
    write_output(args.github_output, "existing", "true")
    write_output(args.github_output, "content-sha256", expected_sha)
    write_output(args.github_output, "commit", args.expected_commit)


if __name__ == "__main__":
    main()
