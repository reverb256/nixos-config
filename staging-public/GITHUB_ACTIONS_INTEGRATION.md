# GitHub Actions Integration for Public/Private Mirror

## Current CI/CD Workflow Enhancement

Your current CI/CD workflow in `.github/workflows/nix.yml` can be enhanced to automatically publish sanitized content to a public mirror while maintaining your private functionality.

## Enhanced GitHub Actions Workflow

Replace your current `.github/workflows/nix.yml` with this enhanced version:

```yaml
name: Nix CI + GitOps + Public Mirror

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@v4

      - name: Magic Nix Cache
        uses: DeterminateSystems/magic-nix-cache-action@v13

      - name: Check Nix flake
        run: nix flake check

      - name: Build all configurations
        run: |
          nix build .#nixosConfigurations.zephyr.config.system.build.toplevel --no-link
          nix build .#nixosConfigurations.nexus.config.system.build.toplevel --no-link
          nix build .#nixosConfigurations.forge.config.system.build.toplevel --no-link
          nix build .#nixosConfigurations.sentry.config.system.build.toplevel --no-link

  publish-public-mirror:
    needs: validate
    if: github.event_name == 'push' && (github.ref == 'refs/heads/main' || github.ref == 'refs/heads/master')
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Checkout private repo
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Setup Git for public mirror
        run: |
          git config --global user.name "github-actions[bot]"
          git config --global user.email "github-actions[bot]@users.noreply.github.com"

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y rsync sed

      - name: Generate sanitized public mirror
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          # Create temporary directory for public mirror
          TEMP_PUBLIC=$(mktemp -d)
          
          # Copy all .nix files and sanitize them
          find . -name "*.nix" -type f -exec cp --parents {} "$TEMP_PUBLIC/" \;
          
          # Sanitize the copied files
          find "$TEMP_PUBLIC" -name "*.nix" -type f -exec sed -i \
            -e 's/10\.1\.1\.[0-9]\+/192.168.100.X/g' \
            -e 's/100\.[0-9]\+\.[0-9]\+\.[0-9]\+/100.YYY.YYY.YYY/g' \
            -e 's/krxXVNVMM7\.[a-z0-9.-]*/WALLET_PREFIX.NODE_NAME/g' \
            -e 's/"WORKER_X"\|"WORKER_X"\|"WORKER_X"\|"WORKER_X"/"WORKER_X"/g' \
            -e 's/USERNAME@HOST[a-zA-Z0-9-]*/USERNAME@HOST/g' \
            -e 's/ssh-ed25519 [A-Za-z0-9+/=]* [^@]*@[a-zA-Z0-9-]*/ssh-ed25519 XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX USERNAME@HOST/g' \
            '{}' \;
          
          # Copy other important files
          cp -f README.md "$TEMP_PUBLIC/" 2>/dev/null || true
          cp -f flake.nix "$TEMP_PUBLIC/" 2>/dev/null || true
          cp -f LICENSE "$TEMP_PUBLIC/" 2>/dev/null || true
          
          # Create usage documentation for public mirror
          cat > "$TEMP_PUBLIC/USAGE_PUBLIC.md" << 'EOT'
          # Public Infrastructure Patterns
          
          This repository contains infrastructure patterns extracted from a private deployment.
          
          ## Parameterization
          
          Replace these placeholders with your values:
          - `192.168.100.X` → Your internal IP addresses
          - `WALLET_PREFIX.NODE_NAME` → Your mining wallet IDs
          - `WORKER_X` → Your hostnames
          - `USERNAME@HOST` → Your SSH settings
          
          See PARAMETERIZATION_BEST_PRACTICES.md for full documentation.
          EOT
          
          # Create the sanitized public repository
          cd "$TEMP_PUBLIC"
          git init
          git add .
          git commit -m "Auto-sanitized release: $(date -Iseconds)"
          
          # Push to a public repository (this assumes you have a public repo set up)
          # Replace with your actual public repo URL
          git remote add origin https://${{ secrets.GITHUB_TOKEN }}@github.com/YOUR_USERNAME/public-nixos-patterns.git
          
          # Force push to the public repo (warning: this will overwrite the public repo)
          git push -f origin main
          
          echo "Public mirror updated successfully!"

  merge-to-infra:
    needs: [validate, publish-public-mirror]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Checkout repo
        uses: actions/checkout@v4

      - name: Setup Git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Merge main → infra
        run: |
          git fetch origin infra
          git checkout infra
          git merge main --no-edit
          git push origin infra

      - name: Trigger deployment  
        run: |
          # Your existing deployment webhook here
          curl -X POST "${{ secrets.DEPLOY_WEBHOOK_URL }}" \
            -H "Content-Type: application/json" \
            -d '{"ref": "infra", "repository": "${{ github.repository }}"}'
        continue-on-error: true
```

## Alternative: Local Mirror Management (More Secure)

If you don't want to expose the sanitization in your public Actions workflow, you can manage this manually:

1. **Keep your current CI/CD** (it works with private values)
2. **Add a local script** that generates sanitized versions
3. **Manually push sanitized versions** to a public repo when you want to share
4. **Maintain the same functionality** for your private use

## Key Benefits

1. **No workflow disruption**: Your current deployment continues unchanged
2. **Automatic sanitization**: Private data is automatically removed when publishing
3. **Dual purpose**: One repo for private use, sanitized version for public sharing
4. **Full functionality**: All your existing CI/CD and deployment features maintained

This approach lets you keep exactly one private repo with full functionality while optionally publishing sanitized versions to a public repo for others to learn from.