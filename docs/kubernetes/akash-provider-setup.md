# Akash Provider Setup Guide

## Quick Summary

**Cost to start:** ~$2-5 (5 AKT at current prices)
**Monthly earnings potential:** $300-1,000+ (depending on utilization)
**Time to setup:** ~1-2 hours

## Prerequisites Checklist

Your cluster already has:
- [x] Kubernetes v1.35.0 running on 4 nodes
- [x] containerd runtime
- [x] Flannel CNI networking
- [x] Local path provisioner
- [x] NVIDIA GPU device plugin (partial)
- [ ] Ingress controller (we'll add)
- [ ] Akash provider software (we'll add)
- [ ] Provider wallet with AKT (you'll create)

## Step 1: Install Akash CLI

```bash
# Install Go first
nix-shell -p go

# Install Akash CLI
go install github.com/ovrclk/akash@latest

# Verify
akash version
```

## Step 2: Create Provider Wallet

```bash
# Create new wallet (SAVE THE MNEMONIC!)
akash keys add my-cluster-provider

# Output will show:
# - name: my-cluster-provider
# - mnemonic: (SAVE THIS SECURELY!)
# - address: akash1abc...xyz (your provider address)

# Get your address
akash keys show my-cluster-provider -a
```

**Copy your provider address** - you'll need it for the NixOS configuration.

## Step 3: Fund Wallet with AKT

**Minimum required:** 5 AKT (~$2.20 at current prices)

```bash
# Buy AKT from:
# - Osmosis DEX (https://osmosis.zone)
# - Keplr wallet connection
# - Centralized exchanges (check if listed)

# Send to your provider address from exchange
# Or use Osmosis to transfer from OSMO to AKT
```

## Step 4: Encode Wallet Key for Kubernetes

```bash
# Export wallet key (base64 encoded for Kubernetes secret)
akash keys export my-cluster-provider --unarmored-hex --unsafe 2>/dev/null | base64 -w 0

# Copy the output - this is your walletKey for NixOS config
```

## Step 5: Configure NixOS Module

Add to your host configuration (e.g., `hosts/zephyr/configuration.nix`):

```nix
{config, pkgs, ...}: {
  # Enable Kubernetes (if not already enabled)
  services.kubernetes-module.enable = true;
  services.kubernetes-module.roles = ["master" "node"];

  # Enable Akash Provider
  services.akash-provider = {
    enable = true;

    # From Step 2
    providerAddress = "akash1abc...xyz";  # Your address

    # From Step 4 (base64 encoded key)
    walletKey = "BASE64_ENCODED_KEY_HERE";

    # Your provider hostname (can use dynamic DNS like duckdns.org)
    domain = "your-cluster.duckdns.org";
    clusterPublicHostname = "provider.your-cluster.duckdns.org";

    # Pricing (uakt per block) - adjust as needed
    pricing = {
      rtx3090 = 20000;    # ~$8.70/month per GPU
      rtx4060 = 18000;
      rtx3060ti = 15000;
      rx5700xt = 8000;
      rx5600xt = 7000;
    };
  };
}
```

## Step 6: Apply Configuration

```bash
# Apply to Zephyr (control plane)
sudo nixos-rebuild switch --flake .#zephyr

# Verify services started
systemctl status akash-node-labels
systemctl status akash-helm-init
```

## Step 7: Deploy Provider via Helm

```bash
# Add Akash Helm repo (done by module, but verify)
helm repo add akash https://akash-network.github.io/helm-charts
helm repo update

# Deploy provider
helm upgrade --install akash-provider akash/provider \
  --namespace akash-services \
  --values /etc/akash-provider-values.yaml \
  --create-namespace

# Verify deployment
kubectl get pods -n akash-services
kubectl logs -n akash-services -l app=akash-provider -f
```

## Step 8: Register Provider On-Chain

```bash
# Create provider registration YAML
cat > provider.yaml <<EOF
host: https://provider.your-cluster.duckdns.org:8443
attributes:
  - key: region
    value: us-west
  - key: host
    value: akash
  - key: tier
    value: community
  - key: organization
    value: homelab
info:
  email: your-email@example.com
  website: https://your-cluster.duckdns.org
EOF

# Register on-chain
akash tx provider create provider.yaml \
  --from my-cluster-provider \
  --chain-id akashnet-2 \
  --node https://rpc.akashnet.net:443

# Verify registration
akash query provider get $(akash keys show my-cluster-provider -a) \
  --node https://rpc.akashnet.net:443
```

## Step 9: Verify GPU Detection

```bash
# Check node resources
kubectl describe nodes | grep -A 5 "nvidia.com/gpu"

# Check allocatable GPUs per node
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable."nvidia\.com/gpu"

# Expected output:
# NAME     GPU
# forge    2
# nexus    1
# sentry   0
# zephyr   2
```

## Troubleshooting

### Provider not bidding on leases

```bash
# Check provider logs
kubectl logs -n akash-services -l app=akash-provider -f

# Common issues:
# - Insufficient AKT for bid fees (add more AKT)
# - GPU not detected (check device plugin)
# - Incorrect attributes (verify labels)
```

### GPU not detected

```bash
# Verify NVIDIA driver
nvidia-smi

# Check device plugin pods
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

# Describe node for GPU info
kubectl describe node zephyr | grep -i gpu
```

### Certificate issues

```bash
# List certificates
akash query cert list --owner $(akash keys show my-cluster-provider -a)

# Create new certificate if needed
akash tx cert create server provider.your-cluster.duckdns.org \
  --from my-cluster-provider \
  --chain-id akashnet-2
```

## Earnings & Withdrawals

```bash
# Check pending earnings
akash query market lease list --state active \
  --owner $(akash keys show my-cluster-provider -a) \
  --node https://rpc.akashnet.net:443

# Withdraw earnings to wallet
akash tx provider withdraw-all \
  --from my-cluster-provider \
  --chain-id akashnet-2 \
  --node https://rpc.akashnet.net:443

# Check wallet balance
akash query bank balances $(akash keys show my-cluster-provider -a)
```

## Pricing Strategy

Current competitive pricing (uakt per block):

| GPU Model | VRAM | Price (uakt/block) | Monthly (AKT) | Est. USD |
|-----------|------|-------------------|--------------|----------|
| RTX 3090 | 24GB | 20,000 | 8,760 | $40-90 |
| RTX 4060 | 8GB | 18,000 | 7,884 | $35-80 |
| RTX 3060 Ti | 8GB | 15,000 | 6,570 | $30-65 |
| RX 5700 XT | 8GB | 8,000 | 3,504 | $15-35 |
| RX 5600 XT | 4GB | 7,000 | 3,066 | $13-30 |

**Tips:**
- Start with higher prices to test demand
- Monitor `akash query market lease list` for accepted bids
- Lower prices if getting no leases
- Raise prices if consistently fully utilized

## Next Steps

1. Get 5 AKT (~$2-5)
2. Create provider wallet
3. Deploy on Zephyr first (control plane node)
4. Expand to other nodes after successful testing
5. Monitor earnings for 1-2 weeks
6. Adjust pricing based on demand

## Resources

- **Akash Docs:** https://akash.network/docs
- **Provider Discord:** https://discord.akash.network (#providers)
- **Console:** https://console.akash.network
- **Provider Explorer:** https://provider.explorer.akash.network
