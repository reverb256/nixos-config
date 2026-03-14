# Akash Provider Setup - Quick Start

## What's Been Configured

✅ **NixOS Module Created:** `modules/services/akash-provider.nix`
  - Automated GPU node labeling
  - Kubernetes storage classes (beta2, beta3, ram)
  - Helm values generation with pricing script
  - Agenix integration for secure key storage

✅ **Agenix Secret Setup:** `secrets/akash-provider-key.age`
  - Encrypted wallet key storage
  - Auto-decryption at boot
  - Integrated with Kubernetes secrets

✅ **Zephyr Configuration Updated:**
  - Akash provider module imported
  - GPU pricing configured for your specific cards
  - Placeholder wallet address (needs updating)

## What You Need to Do

### Step 1: Create Akash Wallet

#### Option A: Use Akash Console (Easiest)

1. Go to https://console.akash.network
2. Click "Connect Wallet"
3. Create new wallet or use existing (Keplr/Leap)
4. **SAVE YOUR MNEMONIC PHRASE** - write it down on paper!
5. Copy your wallet address (starts with `akash1...`)

#### Option B: Use Cosmostation (Desktop Wallet)

1. Download: https://cosmostation.io/
2. Install and open the app
3. Create new wallet
4. Select "Akash Network" from chains
5. **SAVE YOUR MNEMONIC PHRASE**
6. Copy your address

#### Option C: Use Leap Wallet (Browser Extension)

1. Install Leap extension for Chrome/Firefox
2. Create new wallet
3. Add Akash Network
4. **SAVE YOUR MNEMONIC PHRASE**
5. Copy your address

### Step 2: Fund Your Wallet with AKT

**Minimum needed:** 5 AKT (~$2-5)

**Where to buy AKT:**
- **Osmosis DEX:** https://osmosis.zone (swap OSMO/USDT for AKT)
- **Keplr Wallet:** Built-in Osmosis swap
- **Exchanges:** Check if AKT is listed (Gate.io, etc.)

**Send to your address:** Use the address from Step 1

### Step 3: Export Private Key

**IMPORTANT:** Only do this on a secure machine!

#### From Keplr:
1. Open Keplr extension
2. Go to "Account" → "Export Private Key"
3. Enter password
4. Copy the private key

#### From Leap:
1. Open Leap extension
2. Go to Settings → Export Account
3. Copy the private key

### Step 4: Encrypt and Store Key

```bash
# Navigate to nixos directory
cd /etc/nixos

# Encrypt your private key with agenix
# Paste your private key when prompted
agenix -e secrets/akash-provider-key.age

# Verify encrypted file was created
ls -la secrets/akash-provider-key.age
```

### Step 5: Update NixOS Configuration

Edit `hosts/zephyr/configuration.nix`:

```nix
services.akash-provider.providerAddress = "akash1YOUR_ADDRESS_HERE";
```

### Step 6: Deploy and Test

```bash
# Test configuration (won't apply yet)
just test

# If test passes, deploy
just deploy

# Verify provider pod started
kubectl get pods -n akash-services

# Check logs
kubectl logs -n akash-services -l app=akash-provider -f
```

### Step 7: Register Provider

```bash
# Create provider registration YAML
cat > provider.yaml <<EOF
host: https://provider.your-domain.com:8443
attributes:
  - key: region
    value: us-west
  - key: host
    value: akash
info:
  email: your-email@example.com
EOF

# Register on-chain (requires AKT for gas)
# First, install akash CLI or use Docker:
docker run --rm -v $(pwd):/work -w /work golang:latest bash -c '
  git clone https://github.com/ovrclk/akash.git
  cd akash
  go build -o akash ./cmd/akash
'

# Then register:
./akash tx provider create provider.yaml \
  --from cluster-provider \
  --chain-id akashnet-2 \
  --node https://rpc.akashnet.net:443
```

## Your GPU Inventory

| Node | GPUs | Models | Status |
|------|------|--------|--------|
| **Zephyr** | 2x | RTX 3090, RTX 3060 Ti | Control plane |
| **Nexus** | 1x | RTX 3060 Ti | Worker |
| **Forge** | 4x | 2x RTX 4060, 2x RX 5700 XT | Worker |
| **Sentry** | 1x | RX 5600 XT | Worker |

**Total: 8 GPUs (5x NVIDIA, 3x AMD)**

## Estimated Earnings

At 50% utilization:

| GPU | Monthly (AKT) | Monthly (USD) |
|-----|---------------|---------------|
| RTX 3090 | 8,760 | $40-90 |
| RTX 4060 | 7,884 | $35-80 |
| RTX 3060 Ti | 6,570 | $30-65 |
| RX 5700 XT | 3,504 | $15-35 |
| RX 5600 XT | 3,066 | $13-30 |

**Potential total: $400-700/month**

## Next Steps After Setup

1. **Monitor first deployments:** Watch logs for successful lease acceptance
2. **Adjust pricing:** If no leases after 24h, lower prices
3. **Check earnings:** Withdraw after accumulating ~10 AKT
4. **Expand to other nodes:** Add provider config to Forge/Nexus/Sentry

## Troubleshooting

### Key not decrypting
```bash
# Check agenix service
systemctl status agenix-rekey

# Verify key file exists
ls -la /run/agenix/akash-provider-key.pem
```

### Provider not starting
```bash
# Check Kubernetes is running
kubectl get nodes

# Check provider pod status
kubectl get pods -n akash-services

# View provider logs
kubectl logs -n akash-services -l app=akash-provider
```

### GPU not detected
```bash
# Check GPU resources on node
kubectl describe node zephyr | grep -i gpu

# Check NVIDIA device plugin
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
```

## Security Notes

- ✅ Private key encrypted with agenix
- ✅ Only decrypted on authorized hosts
- ✅ Never stored in git
- ⚠️ Keep mnemonic phrase backed up offline
- ⚠️ Consider separate wallet for mainnet funds

## Resources

- **Akash Docs:** https://akash.network/docs
- **Provider Discord:** https://discord.akash.net (#providers)
- **Console:** https://console.akash.network
- **Status:** https://provider.explorer.akash.network
