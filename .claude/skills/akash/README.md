# Akash Network Provider Assistant

Intelligent Kubernetes assistant for Akash Network providers.

## Overview

The Akash assistant diagnoses provider issues, explains cluster state,
and automatically fixes common problems.

## Installation

Already installed in `.claude/skills/akash/`

## Usage

### Basic Commands

- `/akash` - Quick health check
- `/akash check` - Full provider diagnostics
- `/akash audit` - Complete cluster audit with prioritized issues
- `/akash fix` - Attempt automatic fixes (with --auto-fix flag)
- `/akash explain <topic>` - Explain topic (gpu, leases, provider, blockchain, network)
- `/akash monitor` - Continuous monitoring mode

### Examples

```bash
# Quick health check
/akash

# Full diagnostics
/akash check

# Get GPU allocation explanation
/akash explain gpu

# Attempt automatic fixes
/akash fix --auto-fix=true

# Continuous monitoring
/akash monitor --continuous=true
```

## Output Formats

- **JSON** (for AI agents): `--json=true`
- **Markdown** (for humans): default

## Features

- **Provider Health Checks**: Pod status, restart count, blockchain sync
- **Hardware Discovery**: CPU, memory, GPU inventory
- **Pattern Detection**: Learns from recurring issues
- **Auto-Fix**: Automatic resolution for common problems
- **Documentation**: Built-in Akash Network knowledge base

## Architecture

- Diagnostics Engine: Health checks and issue detection
- Prioritization System: Ranks issues by severity and impact
- Explanation Generator: Plain-language reports with ASCII topology
- Auto-Fix Module: Safe, permission-gated fixes
- Knowledge Base: Learning system with pattern detection

## Requirements

- Node.js 18+ (for local development)
- kubectl configured and working
- Access to Akash provider cluster

## Development

```bash
cd .claude/skills/akash
npm install
npm test
npm run lint
```

## License

MIT

## Version

1.0.0
