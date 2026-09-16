#!/usr/bin/env python3
"""Fail CI on any Swift compiler warning in the app, widget, or watch targets.

Swift 6 language mode turns concurrency mistakes into errors, but deprecations,
unused results, and SDK changes still only warn, and a green build hides them.
The app, widget, and watch targets are held to zero warnings. CadenceTests and
CadenceUITests stay on older Swift language modes and are excluded.

Usage: check_warnings.py <xcodebuild.log>

Two shapes of warning show up in an xcodebuild log:
  /path/Cadence/Services/Foo.swift:12:5: warning: ...
  /DerivedData/.../@__swiftmacro_7Cadence...swift:5:22: warning: ...
The second comes from a macro expansion (#Predicate, #expect, ...). Its module is
length-prefixed after `@__swiftmacro_`, and the real source line appears on a
following "expanded code originates here" note, which is what gets annotated.
"""
import os
import re
import sys

EXCLUDED_MODULES = {"CadenceTests", "CadenceUITests"}
EXCLUDED_DIRS = ("/CadenceTests/", "/CadenceUITests/")

WARNING = re.compile(r"^(?P<path>/\S[^:]*\.swift):(?P<line>\d+):(?P<col>\d+): warning: (?P<msg>.+)$")
ORIGIN = re.compile(r"(?P<path>/\S[^:]*\.swift):(?P<line>\d+):(?P<col>\d+): note: expanded code originates here")
MACRO_MODULE = re.compile(r"@__swiftmacro_(\d+)")


def macro_module(path):
    m = MACRO_MODULE.search(path)
    if not m:
        return None
    length = int(m.group(1))
    start = m.end()
    return path[start:start + length]


def is_excluded(path):
    if any(d in path for d in EXCLUDED_DIRS):
        return True
    return macro_module(path) in EXCLUDED_MODULES


def collect(lines):
    found = {}
    for i, raw in enumerate(lines):
        m = WARNING.match(raw.rstrip("\n"))
        if not m:
            continue
        path, line, col, msg = m.group("path"), m.group("line"), m.group("col"), m.group("msg")
        if macro_module(path) is not None:
            # Point the annotation at the source line the macro was written on.
            for follow in lines[i + 1:i + 6]:
                origin = ORIGIN.search(follow)
                if origin:
                    path, line, col = origin.group("path"), origin.group("line"), origin.group("col")
                    break
        if is_excluded(path):
            continue
        found.setdefault((path, int(line), int(col), msg), None)
    return list(found)


def main():
    if len(sys.argv) != 2:
        print("usage: check_warnings.py <xcodebuild.log>", file=sys.stderr)
        return 2
    with open(sys.argv[1], errors="replace") as fh:
        warnings = collect(fh.readlines())
    workspace = os.environ.get("GITHUB_WORKSPACE", os.getcwd()).rstrip("/") + "/"
    for path, line, col, msg in sorted(warnings):
        rel = path[len(workspace):] if path.startswith(workspace) else path
        print(f"::warning file={rel},line={line},col={col}::{msg}")
    if warnings:
        print(f"::error::{len(warnings)} compiler warning(s) in the app, widget, or watch targets.")
        return 1
    print("No compiler warnings in the app, widget, or watch targets.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
