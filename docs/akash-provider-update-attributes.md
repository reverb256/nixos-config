# Update Akash Provider Blockchain Attributes

## Problem
The provider attributes stored on the blockchain have issues:
1. `host_uri`: `provider.provider.reverb256.ca` (double "provider")
2. `info.email`: Empty
3. `info.website`: Empty

## Solution: Update Provider Attributes

### Prerequisites
- Akash wallet with provider owner key
- provider-services CLI (available in provider pod)
- AKASH token for transaction fees

### Step 1: Access Provider Pod with CLI

```bash
kubectl exec -it -n akash-services akash-provider-akash-provider-fixed-0 -c akash-provider-fixed -- bash
```

### Step 2: Check Current Attributes

```bash
provider-services query provider get akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
```

### Step 3: Update Provider Attributes

Create a JSON file with corrected attributes:

```json
{
  "info": {
    "email": "admin@reverb256.ca",
    "website": "reverb256.ca"
  },
  "attributes": [
    {"key": "host", "value": "akash"},
    {"key": "tier", "value": "community"},
    {"key": "organization", "value": "Reverb256"},
    {"key": "region", "value": "bc-west"},
    {"key": "country", "value": "Canada"},
    {"key": "hardware-cpu-arch", "value": "x86_64"},
    {"key": "capabilities/gpu/vendor/nvidia", "value": "true"},
    {"key": "capabilities/gpu/vendor/nvidia/model/rtx3060ti", "value": "true"},
    {"key": "capabilities/gpu/vendor/nvidia/model/rtx3090", "value": "true"},
    {"key": "capabilities/gpu/vendor/nvidia/model/rtx4060", "value": "true"},
    {"key": "capabilities/gpu/vendor/nvidia/memory/8gb", "value": "true"},
    {"key": "capabilities/gpu/vendor/nvidia/memory/24gb", "value": "true"},
    {"key": "hardware-gpu", "value": "rtx3060ti,rtx3090,rtx4060"},
    {"key": "console/trials", "value": "true"},
    {"key": "capabilities/storage/1/class", "value": "beta2"},
    {"key": "capabilities/storage/1/persistent", "value": "true"},
    {"key": "capabilities/storage/2/class", "value": "beta3"},
    {"key": "capabilities/storage/2/persistent", "value": "true"},
    {"key": "capabilities/storage/3/class", "value": "ram"},
    {"key": "capabilities/storage/3/persistent", "value": "false"}
  ],
  "host_uri": "https://provider.reverb256.ca:8443"
}
```

### Step 4: Send Update Transaction

```bash
provider-services tx provider update \
  --from <your-key-name> \
  --info.email=admin@reverb256.ca \
  --info.website=reverb256.ca \
  --host-uri=https://provider.reverb256.ca:8443 \
  --chain-id akashnet-2 \
  --node https://rpc.akashnet.net:443 \
  --fees 5000uakt
```

### Step 5: Verify Update

```bash
provider-services query provider get akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
```

Check that:
- `host_uri` is now `https://provider.reverb256.ca:8443`
- `info.email` is `admin@reverb256.ca`
- `info.website` is `reverb256.ca`

## Alternative: Full Provider Re-registration

If update doesn't work, you may need to re-register the provider:

```bash
provider-services tx provider create \
  --from <your-key-name> \
  --info.email=admin@reverb256.ca \
  --info.website=reverb256.ca \
  --host-uri=https://provider.reverb256.ca:8443 \
  --chain-id akashnet-2 \
  --node https://rpc.akashnet.net:443 \
  --fees 5000uakt
```

## After Update

Once blockchain attributes are corrected:
1. Verify DNS resolution from external network
2. Verify port accessibility (80, 443, 8443, 8444)
3. Submit GitHub issue to akash-network/community
4. Wait for auditor (@andy01 on Discord) to verify

## References

- [Akash Provider Documentation](https://akash.network/docs/providers)
- [Audited Attributes](https://akash.network/docs/deployments/audited-attributes/)
- [Community Issues](https://github.com/akash-network/community/issues)
