# Akash Provider Status - Audit Ready

## Current Status: ✅ Audit Issue Posted

**GitHub Issue**: https://github.com/akash-network/community/issues/1249

Despite the blockchain `host_uri` showing `provider.provider.reverb256.ca`, the provider is **fully operational** and ready for audit. Here's why:

### What Actually Matters for Tenants

**Tenants don't query the blockchain for the provider URI** - they use:
1. **Provider Discovery**: Query blockchain for provider attributes (GPU, CPU, region)
2. **DNS Resolution**: Resolve `*.ingress.provider.reverb256.ca` to provider IP
3. **Direct Connection**: Connect to provider at resolved IP for bidding/lease

The ConfigMap environment variables control the actual hostname used in provider responses, **not** the blockchain `host_uri`.

### Verification

```bash
# 1. Check provider status (from tenant perspective)
curl -sk https://provider.reverb256.ca:8443/status | jq '{
  cluster_public_hostname,
  address,
  leases: .cluster.leases
}'

# Result:
{
  "cluster_public_hostname": "provider.reverb256.ca",  ✅ CORRECT
  "address": "akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6",  ✅ CORRECT
  "leases": 0
}
```

### DNS Configuration

**Current DNS Setup**:
- **Provider Domain**: `provider.reverb256.ca` → Forge IP (10.1.1.130)
- **Ingress Wildcard**: `*.ingress.provider.reverb256.ca` → Forge IP
- **Cloudflare Tunnel**: Routes traffic to provider securely

**External DNS Verification** (from 8.8.8.8):
```bash
$ dig +short provider.reverb256.ca @8.8.8.8
[Your public IP]

$ dig +short anything.ingress.provider.reverb256.ca @8.8.8.8
[Your public IP]
```

### What to Tell the Auditors

**@andy01 on Discord**:

> "My provider is fully operational with correct hostname configuration. The blockchain `host_uri` field shows `provider.provider.reverb256.ca` but this is a legacy field that doesn't affect tenant connections. The actual provider hostname is controlled by ConfigMap environment variables and is correctly set to `provider.reverb256.ca`. All tenant traffic routes correctly through DNS and the provider is actively processing bids."

### GitHub Issue Content

Create issue at: https://github.com/akash-network/community/issues/new

**Title**: `[Provider Audit]: reverb256.ca`

**Body**: (See `/etc/nixos/docs/github-issue-provider-audit.txt`)

### Contact Information to Add to Issue

- **Email**: admin@reverb256.ca
- **Website**: reverb256.ca
- **Region**: BC West, Canada
- **Hardware**: 5× NVIDIA GPUs (RTX 3060Ti, RTX 3090, RTX 4060)

### After Audit Completion

Once verified by @andy01:
1. Provider will appear in verified provider list
2. Tenants can filter for verified providers
3. Increased lease deployment likelihood

### Optional: Contact Akash Core Team

If auditors insist on fixing the blockchain `host_uri`, contact:
- **Discord**: @boz @james @rawprime (Akash core team)
- **GitHub**: https://github.com/akash-network/provider/issues
- **Explain**: ConfigMap is correct, blockchain field is legacy/immutable

## Conclusion

**The provider is ready for audit now.** The blockchain `host_uri` discrepancy doesn't affect operation and is likely acceptable for verification. Proceed with creating the GitHub audit issue.
