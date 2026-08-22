#!/usr/bin/env python3
"""Fail when a VSTest run did not execute any NUnit tests."""

from __future__ import annotations

import argparse
import pathlib
import sys
import xml.etree.ElementTree as ET


NUNIT_ADAPTER = "executor://nunit3testexecutor/"


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def fail(message: str) -> int:
    print(f"Test result verification failed: {message}", file=sys.stderr)
    return 1


def verify_report(path: pathlib.Path) -> tuple[int, int] | str:
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError) as error:
        return f"could not parse {path}: {error}"

    definitions = [element for element in root.iter() if local_name(element.tag) == "UnitTest"]
    nunit_definitions = {
        element.attrib["id"]
        for element in definitions
        if any(
            local_name(method.tag) == "TestMethod"
            and method.attrib.get("adapterTypeName", "").lower() == NUNIT_ADAPTER
            for method in element
        )
        and "id" in element.attrib
    }
    if not nunit_definitions:
        return f"{path} contains no NUnit test definitions"

    counters = next(
        (element for element in root.iter() if local_name(element.tag) == "Counters"),
        None,
    )
    if counters is None:
        return f"{path} has no test summary counters"

    try:
        total = int(counters.attrib["total"])
        executed = int(counters.attrib["executed"])
    except (KeyError, ValueError) as error:
        return f"{path} has invalid test summary counters: {error}"

    results = [element for element in root.iter() if local_name(element.tag) == "UnitTestResult"]
    nunit_results = [result for result in results if result.attrib.get("testId") in nunit_definitions]
    if total <= 0 or executed <= 0 or not nunit_results:
        return (
            f"{path} reports no executed NUnit tests "
            f"(total={total}, executed={executed}, results={len(nunit_results)})"
        )

    return total, executed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results-directory", type=pathlib.Path, required=True)
    args = parser.parse_args()

    if not args.results_directory.is_dir():
        return fail(f"results directory does not exist: {args.results_directory}")

    reports = sorted(args.results_directory.rglob("*.trx"))
    if not reports:
        return fail(f"no .trx files found in {args.results_directory}")

    totals = 0
    executed = 0
    for report in reports:
        result = verify_report(report)
        if isinstance(result, str):
            return fail(result)
        report_total, report_executed = result
        totals += report_total
        executed += report_executed

    print(f"Verified {len(reports)} TRX report(s): total={totals}, executed={executed} NUnit tests.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
