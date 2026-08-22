#!/usr/bin/env python3
"""Validate the committed yamllint requirements contract and CI wiring."""

from __future__ import annotations

import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
REQUIREMENTS = ROOT / "tests" / "ci-tooling" / "requirements.in"
CONSTRAINTS = ROOT / "tests" / "ci-tooling" / "constraints.txt"


def pinned_packages(path: pathlib.Path) -> dict[str, str]:
    packages: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = re.fullmatch(r"([A-Za-z0-9_.-]+)==([0-9]+(?:\.[0-9]+)+)", stripped)
        if match is None:
            raise AssertionError(f"{path} contains a non-exact requirement: {stripped!r}")
        packages[match.group(1).lower().replace("_", "-")] = match.group(2)
    return packages


class YamllintContractTests(unittest.TestCase):
    def test_direct_input_and_runtime_constraints_are_exact(self) -> None:
        self.assertEqual(pinned_packages(REQUIREMENTS), {"yamllint": "1.38.0"})
        self.assertEqual(
            pinned_packages(CONSTRAINTS),
            {
                "yamllint": "1.38.0",
                "pathspec": "1.1.1",
                "pyyaml": "6.0.3",
            },
        )

    def test_ci_installs_the_contract_and_not_a_top_level_only_pin(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        install = re.search(
            r"(?ms)^\s*- name: Install yamllint\s+run: >-\s+(.*?)(?=^\s*- name:|^\s*#|\Z)",
            workflow,
        )
        self.assertIsNotNone(install, "CI must have an Install yamllint step")
        install_text = " ".join(install.group(1).split())
        self.assertIn("--requirement tests/ci-tooling/requirements.in", install_text)
        self.assertIn("--constraint tests/ci-tooling/constraints.txt", install_text)
        self.assertNotRegex(workflow, r"(?m)^\s*run:\s*pip install yamllint\s*$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
