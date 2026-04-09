#!/usr/bin/env python3
"""Generate agent instruction files from Jinja2 templates.

This script generates AGENTS.md, CLAUDE.md, and QWEN.md from the base template,
eliminating duplication and ensuring consistent structure.

Usage:
    python3 generate-agent-instructions.py
"""

import jinja2
from pathlib import Path
from datetime import datetime
import sys

# Configuration
SCRIPT_DIR = Path(__file__).parent
TEMPLATE_DIR = SCRIPT_DIR / "templates"
OUTPUT_DIR = Path("/etc/nixos")

# File metadata
TITLES = {
    'universal': 'NixOS Configuration - Agent Guidelines',
    'claude': 'NixOS Configuration - Claude Code Agent Patterns',
    'qwen': 'NixOS Configuration - Qwen-Agent Patterns'
}

PURPOSES = {
    'universal': '''This document provides guidelines for AI agents (OpenCode, Cursor, Copilot, Qwen-Agent, etc.) working on this NixOS configuration. It focuses on universal workflows, testing strategies, and common patterns.

**For Claude Code-specific patterns**, see `CLAUDE.md`.''',

    'claude': '''This document contains Claude Code-specific patterns and workflows for this NixOS configuration. It extends the universal guidelines in `AGENTS.md` with Claude Code features like Serena semantic tools and async agent launching.

**Read AGENTS.md first** for universal cluster patterns, build commands, and deployment workflows.''',

    'qwen': '''This document contains Qwen-Agent-specific patterns and workflows for this NixOS configuration. It extends the universal guidelines in `AGENTS.md` with Qwen framework features like function calling, code interpreter, and Qwen MCP integration.

**Read AGENTS.md first** for universal cluster patterns, build commands, and deployment workflows.'''
}

def create_environment() -> jinja2.Environment:
    """Create Jinja2 environment with custom configuration."""
    # Create template loader with include extension
    loader = jinja2.FileSystemLoader(TEMPLATE_DIR)

    # Create environment
    env = jinja2.Environment(
        loader=loader,
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True
    )

    # Add custom include function that works with our directory structure
    def include_shared(filename):
        """Include a shared content block."""
        shared_path = TEMPLATE_DIR / "shared" / filename
        if shared_path.exists():
            return shared_path.read_text()
        return f"<!-- MISSING: {filename} -->"

    env.globals['include'] = include_shared

    return env

def generate_file(agent_type: str, env: jinja2.Environment) -> tuple[Path, int, str]:
    """Generate a specific agent instruction file.

    Args:
        agent_type: Type of agent ('universal', 'claude', or 'qwen')
        env: Jinja2 environment

    Returns:
        tuple: (output_path, line_count, content)
    """
    # Load template
    template = env.get_template('base-template.md.j2')

    # Render template
    content = template.render(
        agent_type=agent_type,
        title=TITLES[agent_type],
        purpose=PURPOSES[agent_type],
        version="1.0",
        date=datetime.now().strftime("%Y-%m-%d")
    )

    # Determine output filename
    if agent_type == 'universal':
        output_path = OUTPUT_DIR / "AGENTS.md"
    elif agent_type == 'claude':
        output_path = OUTPUT_DIR / "CLAUDE.md"
    elif agent_type == 'qwen':
        output_path = OUTPUT_DIR / "QWEN.md"
    else:
        raise ValueError(f"Unknown agent type: {agent_type}")

    # Write output
    output_path.write_text(content)

    # Count lines
    line_count = len(content.split('\n'))

    return output_path, line_count, content

def validate_output(output_path: Path, line_count: int, agent_type: str) -> list[str]:
    """Validate generated file against requirements.

    Args:
        output_path: Path to generated file
        line_count: Number of lines in generated file
        agent_type: Type of agent file

    Returns:
        list: Validation errors (empty if valid)
    """
    errors = []

    # Check length targets
    MAX_LINES = {
        'universal': 500,
        'claude': 200,
        'qwen': 200
    }

    if line_count > MAX_LINES[agent_type]:
        errors.append(
            f"❌ File too long: {line_count}/{MAX_LINES[agent_type]} lines "
            f"(exceeds by {line_count - MAX_LINES[agent_type]} lines)"
        )

    # Check required sections
    content = output_path.read_text()

    REQUIRED_SECTIONS = {
        'universal': ['Purpose', 'Quick Start', 'Build & Test Commands'],
        'claude': ['Purpose', 'Claude Code-Specific Features'],
        'qwen': ['Purpose', 'Qwen-Agent-Specific Features']
    }

    for section in REQUIRED_SECTIONS[agent_type]:
        if f"## {section}" not in content:
            errors.append(f"❌ Missing required section: {section}")

    # Check for template artifacts
    artifacts = [
        '{{',
        '}}',
        '{%',
        '%}',
        '{#',
        '#}'
    ]

    for artifact in artifacts:
        if artifact in content:
            errors.append(f"⚠️  Template artifact found: {artifact}")

    return errors

def main():
    """Generate all agent instruction files."""
    print("🔨 Generating agent instruction files from templates...\n")

    try:
        # Create Jinja2 environment
        env = create_environment()

        # Generate each file
        results = {}
        for agent_type in ['universal', 'claude', 'qwen']:
            print(f"Generating {agent_type} agent file...")

            try:
                output_path, line_count, content = generate_file(agent_type, env)
                errors = validate_output(output_path, line_count, agent_type)

                results[agent_type] = {
                    'path': output_path,
                    'lines': line_count,
                    'errors': errors,
                    'success': len(errors) == 0
                }

                # Print result
                status = "✅" if results[agent_type]['success'] else "❌"
                print(f"  {status} {output_path.name}: {line_count} lines")

                if errors:
                    for error in errors:
                        print(f"    {error}")

            except Exception as e:
                print(f"  ❌ Error: {e}")
                results[agent_type] = {
                    'path': None,
                    'lines': 0,
                    'errors': [str(e)],
                    'success': False
                }

        # Summary
        print("\n" + "="*60)
        success_count = sum(1 for r in results.values() if r['success'])
        total_count = len(results)

        if success_count == total_count:
            print(f"✅ Successfully generated all {total_count} files")
            print("\nGenerated files:")
            for agent_type, result in results.items():
                if agent_type == 'universal':
                    print(f"  • AGENTS.md ({result['lines']} lines)")
                elif agent_type == 'claude':
                    print(f"  • CLAUDE.md ({result['lines']} lines)")
                elif agent_type == 'qwen':
                    print(f"  • QWEN.md ({result['lines']} lines)")
            print("\nNext steps:")
            print("  1. Review generated files")
            print("  2. Run 'just test' to verify configuration")
            print("  3. Commit changes to git")
            return 0
        else:
            print(f"❌ Generated {success_count}/{total_count} files with errors")
            return 1

    except Exception as e:
        print(f"\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == '__main__':
    sys.exit(main())
