# Script Organization Plan

This document describes the planned organization for automation scripts in the repository.

## Current Scripts
```
scripts/
├── aistor-ops.py              # AIStor operations
├── free-tier-cleanup.sh      # Cleanup unused resources to stay within free tier limits
├── free-tier-monitor.sh      # Monitor resource usage for free tier compliance
├── generate-aistor-credentials.sh  # Generate AIStor credentials
├── openclaw-aistor-workflows.py  # OpenClaw AIStor workflows
├── reset-proton-prefixes.sh  # Reset Proton prefixes for gaming
├── setup-aistor-full-capabilities.sh  # Setup AIStor full capabilities
├── setup-minio-cache.sh      # Setup MinIO cache
├── setup-rclone-cloud-backups.sh  # Setup rclone cloud backups
├── setup-rclone.sh           # Setup rclone
├── test-openclaw-tailscale.sh  # Test OpenClaw with Tailscale
├── test-openclaw-workflows.py  # Test OpenClaw workflows
├── validate-openclaw-setup.sh  # Validate OpenClaw setup
├── verify_mining.sh          # Verify mining operations
└── verify-wivrn-lighthouse.sh  # Verify WiVRn Lighthouse
```

## Proposed Organization
```
scripts/
├── setup/                    # Initial setup and configuration
│   ├── aistor-ops.py         # AIStor operations
│   ├── generate-aistor-credentials.sh  # Generate AIStor credentials
│   ├── setup-aistor-full-capabilities.sh  # Setup AIStor full capabilities
│   ├── setup-minio-cache.sh  # Setup MinIO cache
│   ├── setup-rclone-cloud-backups.sh  # Setup rclone cloud backups
│   └── setup-rclone.sh       # Setup rclone
│
├── maintenance/              # Routine maintenance and cleanup
│   ├── free-tier-cleanup.sh  # Cleanup unused resources
│   ├── free-tier-monitor.sh  # Monitor free tier usage
│   ├── reset-proton-prefixes.sh  # Reset Proton prefixes
│   └── validate-openclaw-setup.sh  # Validate OpenClaw setup
│
├── monitoring/               # Performance and status monitoring
│   ├── verify_mining.sh      # Verify mining operations
│   └── verify-wivrn-lighthouse.sh  # Verify WiVRn Lighthouse
│
└── testing/                  # Testing and validation
    ├── openclaw-aistor-workflows.py  # OpenClaw AIStor workflows
    ├── test-openclaw-tailscale.sh  # Test OpenClaw with Tailscale
    └── test-openclaw-workflows.py  # Test OpenClaw workflows
```

## Implementation Steps

### 1. Create Directories
```bash
mkdir -p scripts/setup
mkdir -p scripts/maintenance
mkdir -p scripts/monitoring
mkdir -p scripts/testing
```

### 2. Move Scripts
```bash
# Setup
mv scripts/aistor-ops.py scripts/setup/
mv scripts/generate-aistor-credentials.sh scripts/setup/
mv scripts/setup-aistor-full-capabilities.sh scripts/setup/
mv scripts/setup-minio-cache.sh scripts/setup/
mv scripts/setup-rclone-cloud-backups.sh scripts/setup/
mv scripts/setup-rclone.sh scripts/setup/

# Maintenance
mv scripts/free-tier-cleanup.sh scripts/maintenance/
mv scripts/free-tier-monitor.sh scripts/maintenance/
mv scripts/reset-proton-prefixes.sh scripts/maintenance/
mv scripts/validate-openclaw-setup.sh scripts/maintenance/

# Monitoring
mv scripts/verify_mining.sh scripts/monitoring/
mv scripts/verify-wivrn-lighthouse.sh scripts/monitoring/

# Testing
mv scripts/openclaw-aistor-workflows.py scripts/testing/
mv scripts/test-openclaw-tailscale.sh scripts/testing/
mv scripts/test-openclaw-workflows.py scripts/testing/
```

### 3. Update Justfile
Update justfile to reference new script locations:
```makefile
# Setup
setup-aistor:
	cd scripts/setup && ./aistor-ops.py

setup-rclone:
	cd scripts/setup && ./setup-rclone.sh

# Maintenance
free-tier-cleanup:
	cd scripts/maintenance && ./free-tier-cleanup.sh

free-tier-monitor:
	cd scripts/maintenance && ./free-tier-monitor.sh

# Monitoring
verify-mining:
	cd scripts/monitoring && ./verify_mining.sh

verify-wivrn:
	cd scripts/monitoring && ./verify-wivrn-lighthouse.sh

# Testing
test-openclaw:
	cd scripts/testing && ./test-openclaw-workflows.py

test-tailscale:
	cd scripts/testing && ./test-openclaw-tailscale.sh
```

### 4. Verify Changes
```bash
# Check directory structure
tree scripts/

# Test just commands
just setup-aistor
just free-tier-monitor
just verify-mining
just test-openclaw
```

## Benefits
1. **Better organization**: Scripts grouped by purpose
2. **Easier maintenance**: Clear separation of concerns
3. **Improved discoverability**: Users can find scripts based on their task
4. **Consistent patterns**: Similar scripts grouped together
5. **Easier to extend**: New scripts can be placed in appropriate directories

## Next Steps
1. Implement the directory structure
2. Update the justfile with new script locations
3. Test all scripts to ensure they work with new paths
4. Update documentation to reference new script locations
5. Verify that all cluster management commands still work