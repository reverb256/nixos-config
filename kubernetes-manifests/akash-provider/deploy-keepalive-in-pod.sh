#!/bin/bash
set -e

echo "=== Akash Provider Keepalive Deployment (Pod Version) ==="
echo "This script runs inside the provider pod where provider-services CLI is available"
echo ""

# Configuration
WALLET_NAME="provider-wallet"
CHAIN_ID="akashnet-2"
SDL_FILE="/config/keepalive-deployment.yaml"
PROVIDER_ADDRESS="akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6"

# Copy SDL file to pod location
echo "=== Preparing SDL File ==="
kubectl cp /etc/nixos/kubernetes-manifests/akash-provider/keepalive-deployment.yaml akash-services/akash-provider-0:/config/keepalive-deployment.yaml
echo "✓ SDL file copied to pod"
echo ""

# Execute deployment commands inside provider pod
echo "=== Executing Deployment Inside Provider Pod ==="
kubectl exec -it akash-provider-0 -n akash-services -- bash -c "
set -e
echo '=== Step 1: Query Provider Address ==='
provider-services keys show $WALLET_NAME -a
echo ''

echo '=== Step 2: Create Deployment on Blockchain ==='
DEPLOYMENT_OUTPUT=\$(provider-services tx deployment create $SDL_FILE --from $WALLET_NAME --yes 2>&1)
echo \"\$DEPLOYMENT_OUTPUT\"
echo ''

DSEQ=\$(echo \"\$DEPLOYMENT_OUTPUT\" | grep -oP 'dseq: \K\d+' || echo '')
if [ -z \"\$DSEQ\" ]; then
    echo '❌ ERROR: Failed to create deployment'
    exit 1
fi
echo \"✓ Deployment created: DSEQ \$DSEQ\"
echo ''

echo '=== Step 3: Wait for Bids (10 seconds) ==='
sleep 10
echo ''

echo '=== Step 4: Query Bids ==='
BIDS=\$(provider-services query market bid get --dseq \$DSEQ --state open --output json 2>/dev/null || echo '[]')
BID_COUNT=\$(echo \"\$BIDS\" | jq '.bids | length' 2>/dev/null || echo '0')
echo \"Bids found: \$BID_COUNT\"
echo ''

if [ \"\$BID_COUNT\" -eq 0 ]; then
    echo '⚠️  WARNING: No bids yet. Waiting 30 more seconds...'
    sleep 30
    BIDS=\$(provider-services query market bid get --dseq \$DSEQ --state open --output json 2>/dev/null || echo '[]')
    BID_COUNT=\$(echo \"\$BIDS\" | jq '.bids | length' 2>/dev/null || echo '0')
    echo \"Bids after wait: \$BID_COUNT\"
    if [ \"\$BID_COUNT\" -eq 0 ]; then
        echo '❌ ERROR: Provider did not bid. Checking pricing...'
        provider-services query market bid get --dseq \$DSEQ --state open --output json || true
        exit 1
    fi
fi
echo '✓ Provider bid received!'
echo ''

echo '=== Step 5: Get Bid Details ==='
FIRST_BID=\$(echo \"\$BIDS\" | jq '.bids[0]')
GSEQ=\$(echo \"\$FIRST_BID\" | jq -r '.bid.id.gseq')
OSEQ=\$(echo \"\$FIRST_BID\" | jq -r '.bid.id.oseq')
PROVIDER=\$(echo \"\$FIRST_BID\" | jq -r '.bid.id.provider')
echo \"  DSEQ: \$DSEQ\"
echo \"  GSEQ: \$GSEQ\"
echo \"  OSEQ: \$OSEQ\"
echo \"  Provider: \$PROVIDER\"
echo ''

echo '=== Step 6: Create Lease ==='
LEASE_OUTPUT=\$(provider-services tx market lease create --dseq \$DSEQ --gseq \$GSEQ --oseq \$OSEQ --from $WALLET_NAME --yes 2>&1)
echo \"\$LEASE_OUTPUT\"
echo ''

if echo \"\$LEASE_OUTPUT\" | grep -q 'Lease created'; then
    echo '✓ Lease created successfully!'
elif echo \"\$LEASE_OUTPUT\" | grep -q 'raw_log'; then
    echo '✓ Lease created (raw format)'
else
    echo '⚠️  WARNING: Check output above'
fi
echo ''

echo '=== Step 7: Send Manifest ==='
MANIFEST_OUTPUT=\$(provider-services send-manifest $SDL_FILE --dseq \$DSEQ --provider $PROVIDER_ADDRESS --from $WALLET_NAME 2>&1)
echo \"\$MANIFEST_OUTPUT\"
echo ''

if echo \"\$MANIFEST_OUTPUT\" | grep -q 'manifest sent'; then
    echo '✓ Manifest sent successfully!'
elif echo \"\$MANIFEST_OUTPUT\" | grep -q 'raw_log'; then
    echo '✓ Manifest sent (raw format)'
else
    echo '⚠️  WARNING: Check output above'
fi
echo ''

echo '=== Step 8: Verify Lease Status ==='
sleep 5
LEASE_STATUS=\$(provider-services query market lease get --dseq \$DSEQ --state active --output json 2>/dev/null || echo '[]')
LEASE_COUNT=\$(echo \"\$LEASE_STATUS\" | jq '.leases | length' 2>/dev/null || echo '0')
echo \"Active Leases: \$LEASE_COUNT\"
echo ''

if [ \"\$LEASE_COUNT\" -gt 0 ]; then
    echo '✅ SUCCESS: Keepalive deployment is active!'
    echo ''
    echo 'The provider should now stay running with an active lease.'
    echo 'Expected provider behavior:'
    echo '  - Manifest manager will have 1 active deployment'
    echo '  - 5-minute shutdown timer will NOT start'
    echo '  - Provider will continue running and bidding on new orders'
else
    echo '❌ ERROR: Lease not active'
    exit 1
fi
"

echo ""
echo "=== Deployment Summary ==="
echo "Check provider status:"
echo "  kubectl logs -f akash-provider-0 -n akash-services --tail=50"
echo ""
echo "Check active deployments:"
echo "  kubectl exec -it akash-provider-0 -n akash-services -- provider-services status"
echo ""
echo "View keepalive pod (once deployed):"
echo "  kubectl get pods -n akash-services"
echo ""
