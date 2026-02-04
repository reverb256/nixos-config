# Contributing

We welcome contributions to this NixOS cluster configuration! This document outlines the guidelines for contributing.

## Getting Started

### 1. Prerequisites
- NixOS 26.05 or later with flakes enabled
- Git for version control
- SSH access to cluster nodes with key-based authentication
- Basic understanding of Nix and NixOS

### 2. Development Environment
```bash
# Clone the repository
git clone <repository-url> /etc/nixos
cd /etc/nixos

# Allow direnv to automatically load the development environment
direnv allow

# Verify environment is working
which alejandra statix colmena agenix
```

## Code Standards

### 1. Formatting
All Nix code must be formatted with **alejandra**:
```bash
# Format all files
just format

# Check if formatting is needed
git status
```

### 2. Linting
Use **statix** to lint Nix code:
```bash
# Lint all files
just lint

# Auto-fix issues
statix fix .
```

### 3. Dead Code Detection
Use **deadnix** to find unused code:
```bash
# Check for dead code
deadnix .
```

### 4. Commit Messages
Follow **Conventional Commits** format:
```
type(scope): description

body (optional)

footer (optional)
```

**Examples**:
```
feat(gaming): add WiVRn support
fix(mining): correct API endpoint
docs: update setup guide
refactor(openclaw): merge overlays
```

**Allowed types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `style`: Formatting changes
- `test`: Adding/updating tests
- `chore`: Maintenance tasks

## Branching Strategy

### 1. Branch Types
- **main**: Production branch (deployable to all hosts)
- **feature/***: New features or improvements
- **fix/***: Bug fixes
- **docs/***: Documentation updates
- **refactor/***: Code refactoring

### 2. Branch Protection
- Main branch requires:
  - CI checks passing
  - At least one reviewer approval
  - No secret leaks detected

## Development Workflow

### 1. Create a Branch
```bash
# Create and checkout branch
git checkout -b feature/my-new-feature

# Push to remote
git push -u origin feature/my-new-feature
```

### 2. Make Changes
```bash
# Edit files
vim modules/my-module.nix
vim hosts/zephyr/configuration.nix

# Format and lint
just format
just lint
```

### 3. Test Changes
```bash
# Test local changes on your host
just switch

# Test cluster deployment
just cluster-build
```

### 4. Commit Changes
```bash
# Stage changes
git add modules/my-module.nix hosts/zephyr/configuration.nix

# Commit with conventional message
git commit -m "feat(my-module): add new functionality"
```

### 5. Push Changes
```bash
git push
```

### 6. Create Pull Request
1. Go to the repository on GitHub
2. Click "New Pull Request"
3. Select your feature branch as the head branch
4. Add a title and description
5. Request a review

## Pull Request Guidelines

### 1. Title
Use conventional commits format: `type(scope): description`

### 2. Description
Include:
- What changes were made
- Why the changes are needed
- How the changes were tested
- Screenshots (if applicable)

### 3. Testing
Include:
- `just cluster-build` passes
- `just lint` and `just format` pass
- Tests for new functionality
- Deployment tested on at least one host

## Review Process

### 1. Reviewer Checklist
- [ ] Code follows standards (formatted, linted)
- [ ] Changes are well-documented
- [ ] No secret leaks
- [ ] Commit messages are clear
- [ ] Changes tested and work as intended

### 2. Review Comments
- Be respectful and constructive
- Focus on code quality and functionality
- Avoid nitpicking on trivial issues

## Releasing

### 1. Prepare Release
```bash
# Checkout main branch
git checkout main
git pull

# Verify all changes are committed
git status

# Create release tag
git tag v1.0.0
git push origin v1.0.0
```

### 2. Deploy to Production
```bash
# Deploy to all hosts
just cluster-deploy

# Verify deployment
just cluster-status
```

### 3. Update Documentation
- Update `docs/CHANGELOG.md`
- Update version in `README.md`
- Add release notes

## Bug Reports

### 1. Create Issue
- Use clear and concise title
- Describe the bug in detail
- Include steps to reproduce
- Add relevant logs and screenshots

### 2. Priority Levels
- **Critical**: System is unusable, security issue
- **High**: Major functionality broken, affects multiple users
- **Medium**: Minor functionality broken, affects single user
- **Low**: Cosmetic issue, enhancement request

## Feature Requests

### 1. Create Issue
- Clearly describe the feature
- Explain why it's needed
- Include use cases
- Add any relevant examples

### 2. Implementation
- Fork the repository
- Create feature branch
- Implement the feature
- Add tests and documentation
- Create pull request

## Community Guidelines

### 1. Code of Conduct
- Be respectful and inclusive
- Avoid offensive language
- Listen to others' opinions
- Focus on problem-solving

### 2. Communication
- Use GitHub issues for bugs and feature requests
- Use pull requests for code changes
- Use discussions for questions and ideas
- Be responsive to comments and reviews

### 3. Help Others
- Answer questions in discussions
- Review pull requests
- Report bugs you find
- Suggest improvements

---

## Resources

- **NixOS Manual**: https://nixos.org/manual/nixos/stable/
- **Nix Pills**: https://nixos.org/guides/nix-pills/
- **Writing NixOS Modules**: https://nixos.org/manual/nixos/stable/#sec-writing-modules
- **Conventional Commits**: https://www.conventionalcommits.org/