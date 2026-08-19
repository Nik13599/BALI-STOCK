from __future__ import annotations

import argparse
import hashlib
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
DIRECTIVE_RE = re.compile(r"^\s*(?:import|export|part)\s+['\"]([^'\"]+)['\"]", re.MULTILINE)
IMPORT_RE = re.compile(r"^\s*import\s+['\"]([^'\"]+)['\"]", re.MULTILINE)
SEED_RE = re.compile(r"SeedProduct\('((?:\\'|[^'])*)',\s*'((?:\\'|[^'])*)',\s*(\d+)(?:,\s*unit:\s*'([^']+)')?\)")
CODE_SUFFIXES = {'.dart', '.js', '.ts', '.py', '.html', '.yml', '.yaml', '.ps1', '.sh', '.iss'}
SKIP_DIRS = {'.git', 'build', '.dart_tool', 'dist', '.idea', '.vscode'}


def dart_files() -> list[Path]:
    return sorted(LIB.rglob("*.dart"))


def code_files() -> list[Path]:
    result: list[Path] = []
    for path in ROOT.rglob('*'):
        if not path.is_file() or path.suffix.lower() not in CODE_SUFFIXES:
            continue
        if any(part in SKIP_DIRS for part in path.relative_to(ROOT).parts):
            continue
        result.append(path)
    return sorted(result)


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


def _is_significant(line: str) -> bool:
    value = line.strip()
    if not value or value in {'{', '}', ');', '],', '),', '];', '};', '(', ')'}:
        return False
    if value.startswith('//') or value.startswith('///') or value.startswith('#'):
        return False
    if re.match(r"^(?:import|export|part)\s+['\"]", value):
        return False
    return len(value) >= 6


def _normalized_lines(path: Path) -> list[tuple[int, str]]:
    try:
        lines = path.read_text(encoding='utf-8').splitlines()
    except UnicodeDecodeError:
        return []
    return [(i, re.sub(r'\s+', ' ', line.strip())) for i, line in enumerate(lines, start=1) if _is_significant(line)]


def _block_fingerprints(path: Path, window: int, min_chars: int) -> list[tuple[str, int, str]]:
    lines = _normalized_lines(path)
    result: list[tuple[str, int, str]] = []
    if len(lines) < window:
        return result
    for index in range(0, len(lines) - window + 1):
        chunk = lines[index:index + window]
        body = '\n'.join(text for _, text in chunk)
        if len(body) < min_chars:
            continue
        digest = hashlib.sha256(body.encode('utf-8')).hexdigest()
        result.append((digest, chunk[0][0], body))
    return result


def duplicate_code_blocks(files: list[Path]) -> list[str]:
    findings: list[str] = []

    # Exact sizeable clones inside one source file.
    for path in files:
        seen: dict[str, tuple[int, str]] = {}
        reported: set[tuple[int, int]] = set()
        for digest, line, body in _block_fingerprints(path, window=12, min_chars=300):
            previous = seen.get(digest)
            if previous is None:
                seen[digest] = (line, body)
                continue
            previous_line, _ = previous
            if abs(line - previous_line) < 12:
                continue
            key = (previous_line, line)
            if key in reported:
                continue
            reported.add(key)
            findings.append(
                f"{relative(path)}: exact duplicated code block near lines {previous_line} and {line} (12 significant lines)"
            )

    # Exact large clones between different source files. This intentionally uses
    # a higher threshold to avoid flagging normal Flutter/HTML boilerplate.
    global_seen: dict[str, tuple[Path, int, str]] = {}
    global_reported: set[tuple[str, str, int, int]] = set()
    for path in files:
        for digest, line, body in _block_fingerprints(path, window=16, min_chars=480):
            previous = global_seen.get(digest)
            if previous is None:
                global_seen[digest] = (path, line, body)
                continue
            previous_path, previous_line, _ = previous
            if previous_path == path:
                continue
            key = (relative(previous_path), relative(path), previous_line, line)
            if key in global_reported:
                continue
            global_reported.add(key)
            findings.append(
                f"cross-file exact clone: {relative(previous_path)}:{previous_line} == {relative(path)}:{line} (16 significant lines)"
            )
    return findings


def duplicate_files(files: list[Path]) -> list[str]:
    groups: dict[tuple[str, int, str], list[Path]] = defaultdict(list)
    for path in files:
        data = path.read_bytes()
        if len(data) < 120:
            continue
        digest = hashlib.sha256(data).hexdigest()
        groups[(path.suffix.lower(), len(data), digest)].append(path)
    return [
        'identical source files: ' + ', '.join(relative(path) for path in paths)
        for paths in groups.values()
        if len(paths) > 1
    ]


def repeated_substantive_lines(path: Path) -> list[str]:
    counts: dict[str, list[int]] = defaultdict(list)
    try:
        lines = path.read_text(encoding='utf-8').splitlines()
    except UnicodeDecodeError:
        return []
    for index, line in enumerate(lines, start=1):
        value = re.sub(r'\s+', ' ', line.strip())
        if len(value) < 80 or not _is_significant(value):
            continue
        counts[value].append(index)
    warnings: list[str] = []
    for value, indexes in counts.items():
        if len(indexes) >= 4:
            warnings.append(f"{relative(path)}: substantive line repeated {len(indexes)} times at {indexes[:8]}")
    return warnings


def main() -> int:
    parser = argparse.ArgumentParser(description="BALI STOCK release code-health audit")
    parser.add_argument("--fail-on-orphans", action="store_true")
    parser.add_argument("--fail-on-clones", action="store_true")
    args = parser.parse_args()

    errors: list[str] = []
    warnings: list[str] = []
    files = dart_files()
    sources = code_files()

    for path in sources:
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()

        if path.suffix == '.dart':
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

        warnings.extend(repeated_substantive_lines(path))

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

    errors.extend(duplicate_files(sources))
    clones = duplicate_code_blocks(sources)
    if clones:
        if args.fail_on_clones:
            errors.extend(clones)
        else:
            warnings.extend(clones)

    for warning in warnings:
        print(f"WARNING: {warning}")
    for error in errors:
        print(f"ERROR: {error}")

    print(
        f"Checked {len(sources)} source files ({len(files)} Dart); "
        f"reachable={len(reachable)}; orphan={len(orphans)}; "
        f"clone_findings={len(clones)}; errors={len(errors)}; warnings={len(warnings)}"
    )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
