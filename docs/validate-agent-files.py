#!/usr/bin/env python3
"""Validate generated agent instruction files.

This script validates AGENTS.md, CLAUDE.md, and QWEN.md against
specification requirements.

Usage:
    python3 validate-agent-files.py
"""

import re
from pathlib import Path
from typing import List, Dict, Tuple

# Configuration
OUTPUT_DIR = Path("/etc/nixos")

# Validation criteria
MAX_LINES = {
    'AGENTS.md': 500,
    'CLAUDE.md': 200,
    'QWEN.md': 200
}

REQUIRED_SECTIONS = {
    'AGENTS.md': ['Purpose', 'Quick Start', 'Build & Test Commands'],
    'CLAUDE.md': ['Purpose', 'Claude Code-Specific Features'],
    'QWEN.md': ['Purpose', 'Qwen-Agent-Specific Features']
}

def validate_file(file_path: Path) -> Tuple[bool, List[str]]:
    """Validate a single agent instruction file.

    Args:
        file_path: Path to the file to validate

    Returns:
        tuple: (is_valid, list of errors)
    """
    if not file_path.exists():
        return False, [f"❌ File does not exist: {file_path}"]

    content = file_path.read_text()
    lines = content.split('\n')

    errors = []
    warnings = []

    # Check length
    line_count = len(lines)
    max_lines = MAX_LINES.get(file_path.name, 500)

    if line_count > max_lines:
        errors.append(
            f"❌ File too long: {line_count}/{max_lines} lines "
            f"(exceeds by {line_count - max_lines} lines)"
        )
    elif line_count > max_lines * 0.9:
        warnings.append(
            f"⚠️  File approaching limit: {line_count}/{max_lines} lines "
            f"({max_lines - line_count} lines remaining)"
        )

    # Check required sections
    for section in REQUIRED_SECTIONS.get(file_path.name, []):
        if f"## {section}" not in content:
            errors.append(f"❌ Missing required section: {section}")

    # Check for duplicate sections (indicates template error)
    section_counts = {}
    for line in lines:
        if line.startswith("## "):
            section = line[3:].strip()
            section_counts[section] = section_counts.get(section, 0) + 1

    for section, count in section_counts.items():
        if count > 1:
            errors.append(f"❌ Duplicate section: '{section}' ({count} times)")

    # Check for template artifacts
    artifacts = {
        '{{': 'Template opening brace',
        '}}': 'Template closing brace',
        '{%': 'Template statement opening',
        '%}': 'Template statement closing',
        '{#': 'Template comment opening',
        '#}': 'Template comment closing'
    }

    for artifact, description in artifacts.items():
        if artifact in content:
            errors.append(f"❌ Template artifact found: {description} ({artifact})")

    # Check for TODO/FIXME markers
    todo_pattern = re.compile(r'{{\s*(TODO|FIXME|XXX)\s*}}', re.IGNORECASE)
    todos = todo_pattern.findall(content)
    if todos:
        warnings.append(f"⚠️  Found {len(todos)} TODO/FIXME markers in generated file")

    # Check for common markdown issues
    if content.count('```') % 2 != 0:
        errors.append("❌ Unclosed code block (odd number of ``` markers)")

    # Check for empty sections
    for i, line in enumerate(lines):
        if line.startswith("## ") and i + 1 < len(lines):
            # Check if next non-empty line is another section heading
            j = i + 1
            while j < len(lines) and not lines[j].strip():
                j += 1
            if j < len(lines) and lines[j].startswith("## "):
                section_name = line[3:].strip()
                warnings.append(f"⚠️  Empty section: {section_name}")

    is_valid = len(errors) == 0

    # Combine errors and warnings for output
    all_messages = errors + warnings

    return is_valid, all_messages

def check_duplication(files: List[Path]) -> List[str]:
    """Check for duplicate content across files.

    Args:
        files: List of file paths to check

    Returns:
        list: Duplication warnings
    """
    warnings = []

    # Load file contents
    content_map = {}
    for file_path in files:
        if file_path.exists():
            content_map[file_path.name] = file_path.read_text()

    # Check for duplicate sections (20+ consecutive identical lines)
    for i, (file1, content1) in enumerate(content_map.items()):
        for file2, content2 in list(content_map.items())[i+1:]:
            lines1 = content1.split('\n')
            lines2 = content2.split('\n')

            # Find duplicate blocks
            duplicate_blocks = 0
            total_duplicate_lines = 0

            for start_idx in range(len(lines1) - 20):
                block1 = '\n'.join(lines1[start_idx:start_idx+20])

                for start_idx2 in range(len(lines2) - 20):
                    block2 = '\n'.join(lines2[start_idx2:start_idx2+20])

                    if block1 == block2 and block1.strip():
                        duplicate_blocks += 1
                        total_duplicate_lines += 20

            if duplicate_blocks > 5:
                warnings.append(
                    f"⚠️  Potential duplication between {file1} and {file2}: "
                    f"~{total_duplicate_lines} lines in {duplicate_blocks} blocks"
                )

    return warnings

def main():
    """Validate all agent instruction files."""
    print("🔍 Validating agent instruction files...\n")

    files = [
        OUTPUT_DIR / "AGENTS.md",
        OUTPUT_DIR / "CLAUDE.md",
        OUTPUT_DIR / "QWEN.md"
    ]

    all_errors = []
    all_warnings = []

    # Validate each file
    for file_path in files:
        filename = file_path.name

        if not file_path.exists():
            print(f"⚠️  {filename} does not exist yet (skipping)")
            continue

        print(f"Validating {filename}...")

        is_valid, messages = validate_file(file_path)

        for message in messages:
            if message.startswith("❌"):
                all_errors.append(message)
                print(f"  {message}")
            else:
                all_warnings.append(message)
                print(f"  {message}")

        if is_valid:
            line_count = len(file_path.read_text().split('\n'))
            print(f"  ✅ {filename} is valid ({line_count} lines)")

        print()

    # Check for cross-file duplication
    if len([f for f in files if f.exists()]) > 1:
        print("Checking for cross-file duplication...")
        dup_warnings = check_duplication([f for f in files if f.exists()])

        for warning in dup_warnings:
            all_warnings.append(warning)
            print(f"  {warning}")

        print()

    # Summary
    print("="*60)

    if all_errors:
        print(f"❌ Validation failed: {len(all_errors)} error(s)")
        if all_warnings:
            print(f"⚠️  {len(all_warnings)} warning(s)")
        return 1
    else:
        print("✅ All files validated successfully")
        if all_warnings:
            print(f"⚠️  {len(all_warnings)} warning(s) - review above")

        # Show summary
        print("\nFile summary:")
        for file_path in files:
            if file_path.exists():
                line_count = len(file_path.read_text().split('\n'))
                max_lines = MAX_LINES.get(file_path.name, 500)
                pct = (line_count / max_lines) * 100
                print(f"  • {file_path.name}: {line_count}/{max_lines} lines ({pct:.1f}%)")

        return 0

if __name__ == '__main__':
    import sys
    sys.exit(main())
