# Anonymizing Your NixOS Infrastructure for Public Repository

## 🔍 Sensitive Information Identified

The following types of private information were found in your configuration:

### 1. Internal IP Addresses
- **Static IPs**: `192.168.100.X`, `192.168.100.X`, `192.168.100.X`, `192.168.100.X`
- **Network range**: `192.168.100.X/24`
- **Gateway**: `192.168.100.X`

### 2. Tailscale IPs
- **Node IPs**: `100.YYY.YYY.YYY`, `100.YYY.YYY.YYY`, `100.YYY.YYY.YYY`, `100.YYY.YYY.YYY`

### 3. Hostnames
- **Machine names**: `zephyr`, `nexus`, `forge`, `sentry`

### 4. Mining Wallet IDs
- **Wallet addresses**: `WALLET_PREFIX.NODE_NAME`, `WALLET_PREFIX.NODE_NAME`, `WALLET_PREFIX.NODE_NAME`, `WALLET_PREFIX.NODE_NAME`

### 5. SSH Keys
- **Public keys** with hostname identifiers

## 🛡️ Recommended Obscuration Strategy

### 1. Environment Variable Approach

Replace hardcoded values with environment variables in your configurations:

**Example:**
```nix
# Before:
services.mining.lolminer.wallet = "WALLET_PREFIX.NODE_NAME";

# After:
services.mining.lolminer.wallet = config.secrets.mining.wallet;
```

### 2. Overlay System for Sensitive Data

Create an overlay system that adds sensitive data locally:

**In your main repo:**
```nix
# modules/mining.nix (public version)
{ config, lib, pkgs, ... }:
let cfg = config.services.mining;
in {
  options.services.mining.wallet = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Mining wallet address (null = use default for development)";
  };
}
```

**Locally in /etc/nixos/private-secrets.nix (not in repo):**
```nix
{ config, pkgs, ... }: {
  services.mining.wallet = "WALLET_PREFIX.NODE_NAME";  # Your actual wallet
  networking.privateIP = "192.168.100.X";
}
```

### 3. Host-Specific Configuration Files

Use a system where base configuration is public but host-specific values are local:

**Public:**
```nix
# hosts/base-template.nix
{ config, lib, ... }: {
  networking.hostName = config.myPrivate.hostname or "template";
  networking.interfaces.enp38s0.ipv4.addresses = [{
    address = config.myPrivate.nodeIP or "192.168.101.X";
    prefixLength = 24;
  }];
}
```

**Local:**
```nix
# /etc/nixos/local-overrides.nix (not in repo)
{ 
  myPrivate.hostname = "WORKER_X";
  myPrivate.nodeIP = "192.168.100.X";
}
```

### 4. File Filtering Strategy

### Option 1: Git Filter (Recommended)
Use git attributes to filter files during commit:

Create `.gitattributes`:
```
*.private.filter diff=private filter=private
```

### Option 2: Template System
Use templates with placeholders:

**Template file (in repo):**
```nix
# hosts/config-template.nix
{
  services.mining.lolminer.wallet = "YOUR_WALLET_ID_HERE";
  networking.hostName = "YOUR_HOSTNAME_HERE";
  networking.interfaces.enp38s0.ipv4.addresses = [{
    address = "INTERNAL_IP_PLACEHOLDER";
    prefixLength = 24;
  }];
}
```

**Local processing script:**
```bash
#!/usr/bin/env bash
# Fill template with real values locally
sed -e "s/YOUR_WALLET_ID_HERE/$MINING_WALLET/" \
    -e "s/YOUR_HOSTNAME_HERE/$HOSTNAME/" \
    -e "s/INTERNAL_IP_PLACEHOLDER/$NODE_IP/" \
    hosts/config-template.nix > /tmp/real-config.nix
```

## 🛠️ Practical Implementation Steps

### 1. Immediate Action Items

1. **Move secrets to agenix**: Ensure all sensitive data is in agenix-managed secrets
2. **Replace hardcoded IPs**: Use config options with defaults for documentation
3. **Anonymize documentation**: Replace specific IPs and hostnames with generic examples

### 2. Create a "Masking" Script

```bash
#!/usr/bin/env bash
# mask-sensitive-data.sh - For preparing public commits

# Make backup first
cp -r hosts hosts-backup

# Mask internal IPs
find hosts -name "*.nix" -exec sed -i 's/10\.1\.1\.[0-9]\+/192.168.1.X/g' {} \;
find hosts -name "*.nix" -exec sed -i 's/100\.[0-9]\+.[0-9]\+.[0-9]\+/100.YYY.YYY.YYY/g' {} \;

# Mask hostnames
find hosts -name "*.nix" -exec sed -i 's/zephyr/worker-01/g' {} \;
find hosts -name "*.nix" -exec sed -i 's/nexus/worker-02/g' {} \;
find hosts -name "*.nix" -exec sed -i 's/forge/worker-03/g' {} \;
find hosts -name "*.nix" -exec sed -i 's/sentry/worker-04/g' {} \;

echo "Sensitive data masked for public repository"
```

### 3. Create Documentation Guidelines

**In README.md, add a section:**
```
## 🚧 Private Configuration Values

This public repository contains anonymized versions of the configuration. To use in your environment, you will need to substitute:

- `192.168.1.X` → Your internal IP range
- `worker-XX` → Your hostname scheme  
- `YOUR_WALLET_ID` → Your actual mining wallet IDs
- Update network configurations for your environment
```

## 📁 Recommended Repository Structure

```
/etc/nixos/
├── public/                 # Public, anonymized configs (in repo)
│   ├── modules/
│   ├── hosts/template/
│   └── flake.nix
├── private/                # Local, sensitive configs (not in repo)
│   ├── secrets/
│   ├── local-overrides.nix
│   └── network-config.nix
├── scripts/
│   └── mask-sensitive-data.sh  # For preparing public versions
└── flake.nix              # Imports both public and private
```

## 🔄 Work Process

1. **Development**: Work normally with full, real configurations
2. **Before public commits**: Run masking script or use template system
3. **Deployment**: Use full, unmasked configurations from local system
4. **Documentation**: Use anonymized examples in public docs

## ⚠️ Security Considerations

- Never commit `.age` secret files to public repos
- Use `.gitignore` for local override files
- Consider if your mining wallet addresses are truly sensitive (they're often public on pools anyway)
- Internal IP ranges like `192.168.101.X/8` are RFC1918 private addresses but still reveal network structure

This approach allows you to maintain a public repository while keeping your private network information secure.