"""Verify that the pinned SDK and FSharp.Core versions stay in lockstep."""

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    print(f"SDK alignment check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


global_json = json.loads((ROOT / "global.json").read_text(encoding="utf-8"))
sdk = global_json.get("sdk", {})
sdk_version = sdk.get("version")
if not isinstance(sdk_version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", sdk_version):
    fail("global.json must contain a semantic SDK version")
if sdk.get("rollForward") != "disable":
    fail("global.json must disable SDK roll-forward when FSharp.Core is pinned")

sdk_major, sdk_minor, sdk_patch = (int(part) for part in sdk_version.split("."))
expected_fsharp_core = f"{sdk_major}.{sdk_minor + 1}.{sdk_patch}"
packages = ET.parse(ROOT / "Directory.Packages.props").getroot()
fsharp_core = next(
    (
        item.attrib.get("Version")
        for item in packages.iter("PackageVersion")
        if item.attrib.get("Include") == "FSharp.Core"
    ),
    None,
)
if fsharp_core != expected_fsharp_core:
    fail(
        "Directory.Packages.props pins "
        f"FSharp.Core {fsharp_core!r}, expected {expected_fsharp_core!r} "
        f"for SDK {sdk_version}"
    )

ci = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
ci_versions = re.findall(r"^\s+dotnet-version:\s*'([^']+)'\s*$", ci, re.MULTILINE)
if not ci_versions:
    fail("CI must select the pinned SDK explicitly")
if any(version != sdk_version for version in ci_versions):
    fail(f"CI SDK selections {ci_versions!r} do not all match {sdk_version!r}")

print(f"SDK alignment passed: SDK {sdk_version}, FSharp.Core {fsharp_core}")
