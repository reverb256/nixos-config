# Changelog

All notable changes to the Akash Assistant skill will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-21

### Added
- Provider health checks (pod status, restart count, blockchain sync)
- Hardware discovery (CPU, memory, GPU inventory)
- Issue prioritization system with severity scoring
- Explanation generator with ASCII topology diagrams
- Auto-fix module with permission system
- Knowledge base with pattern detection
- Integration testing suite
- Comprehensive documentation

### Features
- Quick health check command
- Full cluster audit with prioritized issues
- Automatic fixes for low-risk issues
- Permission-required fixes for high-risk operations
- Topic-based explanations (GPU, leases, provider, blockchain, network)
- Continuous monitoring mode
- JSON and Markdown output formats

### Testing
- 152 tests across 6 modules
- Integration tests for complete workflows
- Mock kubectl for safe testing

### Security
- Safe kubectl execution using execFileSync
- Permission system for high-risk operations
- Input validation for all user inputs
