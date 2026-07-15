#!/usr/bin/env python3
"""YAML validator tolerant of Nix/SOPS/Helm output conventions.

PyYAML enforces YAML 1.1, which forbids tabs in indentation. Nix's
``toJSON``, SOPS-encrypted YAML, and Helm templates commonly emit
JSON-with-tabs (or YAML-with-tabs) that PyYAML rejects but Kubernetes,
SOPS, and Helm parse fine via YAML 1.2 / lenient JSON.

This script tries (in order):
  1. ``ruamel.yaml`` (YAML 1.2) when available — preferred for real YAML
  2. PyYAML with tab→2-space preprocessing (handles tab-indented YAML/JSON)
  3. ``json.loads`` with tab→2-space preprocessing (handles JSON-with-tabs)

Multi-document YAML (``---`` separated) is handled by ``safe_load_all`` /
``json.loads`` per document.

Usage::

    scripts/yaml-validate.py [PATH ...]

If no PATH given, scans the repository for ``*.yaml`` and ``*.yml``
files (excluding ``.git/``, ``.stversions/``, ``node_modules/``,
``.ruff_cache/``).

Exit code 0 if all files parse, 1 otherwise.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Iterable

EXCLUDE_DIRS = {".git", ".stversions", "node_modules", ".ruff_cache"}
YAML_EXTENSIONS = {".yaml", ".yml"}

# Prefer ruamel.yaml if installed (YAML 1.2 compliant).
try:
    from ruamel.yaml import YAML as RuamelYAML

    _ruamel = RuamelYAML(typ="safe", pure=True)
    HAVE_RUAMEL = True
except ImportError:
    HAVE_RUAMEL = False

# PyYAML may not be installed either; the JSON fallback covers that case.
try:
    import yaml as _pyyaml

    HAVE_PYYAML = True
except ImportError:
    HAVE_PYYAML = False


def _looks_like_json(text: str) -> bool:
    stripped = text.lstrip()
    return stripped.startswith("{") or stripped.startswith("[")


def _preprocess_tabs(text: str) -> str:
    """Replace tab characters with two spaces to satisfy YAML 1.1 indentation rules."""
    return text.replace("\t", "  ")


def parse_yaml(path: Path) -> tuple[bool, str]:
    """Attempt to parse *path*. Returns (ok, error_message)."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        return False, f"read error: {exc}"

    # 1) ruamel.yaml — handles YAML 1.2 + multi-doc natively.
    if HAVE_RUAMEL:
        try:
            for _ in _ruamel.load_all(text):
                pass
            return True, ""
        except Exception:
            pass  # fall through to PyYAML / json

    # 2) PyYAML with tab preprocessing.
    yaml_err = ""
    if HAVE_PYYAML:
        try:
            for _ in _pyyaml.safe_load_all(_preprocess_tabs(text)):
                pass
            return True, ""
        except Exception as exc:
            yaml_err = f"{type(exc).__name__}: {exc}"
        # If file looks like JSON, fall through to json.
        if not _looks_like_json(text):
            return False, yaml_err

    # 3) JSON fallback (per-document for multi-doc JSON streams).
    if _looks_like_json(text):
        try:
            decoder = json.JSONDecoder(strict=False)
            idx = 0
            n = len(text)
            while idx < n:
                stripped = text[idx:].lstrip()
                if not stripped:
                    break
                offset = idx + (len(text[idx:]) - len(stripped))
                # Skip leading whitespace before next document.
                doc, end = decoder.raw_decode(stripped)
                idx = offset + end
            return True, ""
        except Exception as exc:
            return False, f"json error: {type(exc).__name__}: {exc}"

    return False, yaml_err if HAVE_PYYAML else "no YAML parser available (install pyyaml or ruamel.yaml)"


def iter_targets(args: list[str]) -> Iterable[Path]:
    """Yield files to validate based on CLI args (or full repo scan)."""
    if args:
        for arg in args:
            p = Path(arg)
            if p.is_dir():
                yield from _walk(p)
            elif p.is_file():
                yield p
            else:
                print(f"warning: {arg} does not exist", file=sys.stderr)
    else:
        repo_root = Path(__file__).resolve().parent.parent
        yield from _walk(repo_root)


def _walk(root: Path) -> Iterable[Path]:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for name in filenames:
            if Path(name).suffix in YAML_EXTENSIONS:
                yield Path(dirpath) / name


def main(argv: list[str]) -> int:
    targets = list(iter_targets(argv[1:]))
    if not targets:
        print("no YAML files to validate", file=sys.stderr)
        return 0

    failures: list[tuple[Path, str]] = []
    for path in targets:
        ok, err = parse_yaml(path)
        status = "PASS" if ok else "FAIL"
        line = f"{status}  {path}"
        if not ok:
            line += f"  ({err})"
            failures.append((path, err))
        print(line)

    total = len(targets)
    passed = total - len(failures)
    print(f"\n{passed}/{total} YAML files valid")
    if failures:
        print(f"  {len(failures)} FAIL:", file=sys.stderr)
        for path, err in failures[:20]:
            print(f"    {path}: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))