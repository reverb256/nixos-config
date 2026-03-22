# Akash Provider Wallet Backup Procedure

## CRITICAL INFORMATION

**Wallet Address**: `akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6`

**Mnemonic** (STORE SECURELY):
```
zebra unknown capital train decide glue sphere acid actual focus lounge green ancient never visual either glimpse vault verb athlete tiger lamp catch jewel
```

**Expected Address**: `akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6`

## Backup Locations

### 1. Persistent Volume (Automatic)
- **PVC**: `home-akash-provider-akash-provider-fixed-0`
- **PV**: `pvc-e49e21b9-d441-4502-b1da-bb9fe20cb0d6`
- **Mount**: `/root/.akash`
- **Keyring**: `/root/.akash/keyring-test/provider-wallet/*`
- **Backup**: Weekly snapshots of the PV

### 2. Offline Backup (Manual - REQUIRED)
Store this information in a secure location:
- Password manager (1Password, Bitwarden, etc.)
- Encrypted USB drive (stored in safe/physical vault)
- Bank safety deposit box
- Secure note in encrypted storage (Cryptomator, encrypted ZIP)

**NEVER store in:**
- ❌ Git repository
- ❌ Unencrypted files
- ❌ Shared drives
- ❌ Cloud storage without encryption
- ❌ Plain text notes

### 3. Kubernetes ConfigMap (Current - NOT SECURE)
- **Name**: `akash-provider-akash-provider-fixed-script`
- **File**: `init.sh`
- **Status**: ⚠️ **MOVE TO ENCRYPTED SECRET** (TODO)

## Recovery Procedure

### Scenario 1: Pod Failure (Data Intact)
```bash
# Delete pod, StatefulSet will recreate it
kubectl delete pod akash-provider-akash-provider-fixed-0 -n akash-services

# Wait for recovery
kubectl wait --for=condition=Ready pod/akash-provider-akash-provider-fixed-0 -n akash-services

# Verify wallet address
curl -sk https://10.0.0.63:8443/status | jq '.address'
```

### Scenario 2: PVC Loss/Corruption (Full Recovery)
```bash
# 1. Delete old PVC (data is gone anyway)
kubectl delete pvc home-akash-provider-akash-provider-fixed-0 -n akash-services

# 2. Create new PVC with same name
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: home-akash-provider-akash-provider-fixed-0
  namespace: akash-services
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: akash-provider-akash-provider-fixed-local-storage
  resources:
    requests:
      storage: 10Gi
EOF

# 3. Delete pod to trigger re-initialization
kubectl delete pod akash-provider-akash-provider-fixed-0 -n akash-services

# 4. Init container will import key from mnemonic automatically
# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/akash-provider-akash-provider-fixed-0 -n akash-services --timeout=300s

# 5. Verify wallet recovered
curl -sk https://10.0.0.63:8443/status | jq '.address'
# Should output: "akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6"
```

### Scenario 3: Complete Cluster Loss (Worst Case)
```bash
# 1. Rebuild cluster from scratch
# 2. Re-deploy Akash provider using manifests
# 3. Ensure init.sh has the correct mnemonic
# 4. Provider will auto-import the key on first startup
# 5. Verify address matches: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
```

## Verification Commands

### Check Wallet Balance
```bash
# Query blockchain (requires akash CLI)
akash-query query bank balances akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
```

### Check Provider Status
```bash
# Internal cluster
curl -sk https://10.0.0.63:8443/status | jq '.'

# External endpoint
curl -sk https://provider.reverb256.ca/status | jq '.'
```

### Check Keyring in Pod
```bash
kubectl exec -n akash-services akash-provider-akash-provider-fixed-0 -- \
  provider-services keys list

# Should show:
# - name: provider-wallet
#   type: local
#   address: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
```

## Security Checklist

- [ ] Mnemonic stored in password manager
- [ ] Mnemonic stored on encrypted USB (offline backup)
- [ ] PVC snapshots configured (weekly)
- [ ] Recovery procedure tested (quarterly)
- [ ] This document printed and stored securely
- [ ] Emergency contact knows how to recover wallet

## Emergency Contacts

- **Primary**: [Your Name]
- **Secondary**: [Backup Contact]
- **Provider Docs**: https://docs.akash.network
- **Akash Discord**: https://discord.gg/akashnetwork

## Important Notes

⚠️ **NEVER share the mnemonic with anyone**
⚠️ **The mnemonic gives FULL CONTROL of the wallet**
⚠️ **If mnemonic is compromised, move funds immediately**
✅ **The provider only needs the mnemonic to recover**
✅ **Keyring data in PVC can be regenerated from mnemonic**

---

**Last Updated**: 2026-03-22
**Next Review**: 2026-04-22
