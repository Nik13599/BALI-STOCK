from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
DIRECTIVE_RE = re.compile(r"^\s*(?:import|export|part)\s+['\"]([^'\"]+)['\"]", re.MULTILINE)
IMPORT_RE = re.compile(r"^\s*import\s+['\"]([^'\"]+)['\"]", re.MULTILINE)
SEED_RE = re.compile(r"SeedProduct\('((?:\\'|[^'])*)',\s*'((?:\\'|[^'])*)',\s*(\d+)(?:,\s*unit:\s*'([^']+)')?\)")


def dart_files() -> list[Path]:
    return sorted(LIB.rglob("*.dart"))


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def resolve_directive(source: Path, target: str) -> Path | None:
    if target.startswith("dart:"):
        return None
    if target.startswith("package:bali_stock/"):
        return LIB / target.removeprefix("package:bali_stock/")
    if target.startswith("package:"):
        return None
    return (source.parent / target).resolve()


def reachable_dart_files(files: list[Path]) -> set[Path]:
    known = {path.resolve() for path in files}
    start = (LIB / "main.dart").resolve()
    reachable: set[Path] = set()
    stack = [start]
    while stack:
        current = stack.pop()
        if current in reachable or current not in known:
            continue
        reachable.add(current)
        text = current.read_text(encoding="utf-8")
        for target in DIRECTIVE_RE.findall(text):
            resolved = resolve_directive(current, target)
            if resolved is not None and resolved in known and resolved not in reachable:
                stack.append(resolved)
    return reachable


def main() -> int:
    parser = argparse.ArgumentParser(description="BALI STOCK release code-health audit")
    parser.add_argument("--fail-on-orphans", action="store_true")
    args = parser.parse_args()

    errors: list[str] = []
    warnings: list[str] = []
    files = dart_files()

    for path in files:
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()

        imports = IMPORT_RE.findall(text)
        seen: set[str] = set()
        for item in imports:
            if item in seen:
                errors.append(f"{relative(path)}: duplicate import {item}")
            seen.add(item)

        for index, line in enumerate(lines, start=1):
            if line.rstrip() != line:
                errors.append(f"{relative(path)}:{index}: trailing whitespace")
            if index > 1 and line.strip() and line == lines[index - 2]:
                errors.append(f"{relative(path)}:{index}: consecutive duplicate line")

        blank_run = 0
        for index, line in enumerate(lines, start=1):
            if not line.strip():
                blank_run += 1
                if blank_run == 3:
                    warnings.append(f"{relative(path)}:{index}: 3+ consecutive blank lines")
            else:
                blank_run = 0

    seed = LIB / "data" / "seed_catalog.dart"
    if seed.exists():
        seen_skus: dict[str, str] = {}
        for category, name, package_size, unit in SEED_RE.findall(seed.read_text(encoding="utf-8")):
            normalized_name = name.replace("\\'", "'").strip().casefold()
            normalized_unit = unit or "ml"
            key = f"{normalized_name}|{normalized_unit}|{package_size}"
            current = f"{category} / {name} / {package_size} / {normalized_unit}"
            if key in seen_skus:
                errors.append(f"duplicate seed SKU: {seen_skus[key]} == {current}")
            seen_skus[key] = current

    reachable = reachable_dart_files(files)
    orphans = [path for path in files if path.resolve() not in reachable]
    if orphans:
        message = "orphan Dart files not reachable from lib/main.dart: " + ", ".join(relative(path) for path in orphans)
        if args.fail_on_orphans:
            errors.append(message)
        else:
            warnings.append(message)

    for warning in warnings:
        print(f"WARNING: {warning}")
    for error in errors:
        print(f"ERROR: {error}")

    print(f"Checked {len(files)} Dart files; reachable={len(reachable)}; orphan={len(orphans)}; errors={len(errors)}; warnings={len(warnings)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
