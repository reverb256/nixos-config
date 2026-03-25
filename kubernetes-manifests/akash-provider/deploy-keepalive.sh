#!/bin/bash
set -e

echo "=== Akash Provider Keepalive Deployment ==="
echo "Purpose: Create minimal deployment to keep provider alive (test idle shutdown issue)"
echo ""

# Configuration
WALLET_NAME="provider-wallet"
RPC_NODE="https://akash-rpc.polkachu.com:443"
CHAIN_ID="akashnet-2"
SDL_FILE="/etc/nixos/kubernetes-manifests/akash-provider/keepalive-deployment.yaml"
PROVIDER_ADDRESS="akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6"

# Check if provider-services CLI is available
if ! command -v provider-services &> /dev/null; then
    echo "❌ ERROR: provider-services CLI not found"
    echo "Need to run this from inside the provider pod or install provider-services CLI"
    echo ""
    echo "Option 1: Run from provider pod:"
    echo "  kubectl exec -it akash-provider-0 -n akash-services -- bash"
    echo ""
    echo "Option 2: Install provider-services CLI locally"
    exit 1
fi

echo "✓ provider-services CLI found"
echo ""

# Step 1: Query provider address
echo "=== Step 1: Query Provider Address ==="
PROVIDER_ADDR=$(provider-services keys show $WALLET_NAME -a)
echo "Provider Address: $PROVIDER_ADDR"
echo ""

# Step 2: Create deployment on-chain
echo "=== Step 2: Create Deployment on Blockchain ==="
echo "SDL File: $SDL_FILE"
echo "Wallet: $WALLET_NAME"
echo "Chain: $CHAIN_ID"
echo ""

DEPLOYMENT_OUTPUT=$(provider-services tx deployment create \
    "$SDL_FILE" \
    --from "$WALLET_NAME" \
    --node "$RPC_NODE" \
    --chain-id "$CHAIN_ID" \
    --yes 2>&1)

echo "$DEPLOYMENT_OUTPUT"
echo ""

# Extract DSEQ from output
DSEQ=$(echo "$DEPLOYMENT_OUTPUT" | grep -oP 'dseq: \K\d+' || echo "")

if [ -z "$DSEQ" ]; then
    echo "❌ ERROR: Failed to create deployment or extract DSEQ"
    echo "Check the output above for errors"
    exit 1
fi

echo "✓ Deployment created successfully"
echo "DSEQ: $DSEQ"
echo ""

# Step 3: Wait for bids (our provider should auto-bid)
echo "=== Step 3: Query Bids (waiting for provider to bid) ==="
echo "Waiting 10 seconds for bids..."
sleep 10

BIDS=$(provider-services query market bid get \
    --dseq "$DSEQ" \
    --state open \
    --node "$RPC_NODE" \
    --output json 2>/dev/null || echo "[]")

BID_COUNT=$(echo "$BIDS" | jq '.bids | length' 2>/dev/null || echo "0")

echo "Bids found: $BID_COUNT"
echo ""

if [ "$BID_COUNT" -eq 0 ]; then
    echo "⚠️  WARNING: No bids found yet"
    echo "This could mean:"
    echo "  1. Provider hasn't bid yet (wait longer)"
    echo "  2. Provider pricing is too high"
    echo "  3. Provider inventory doesn't match requirements"
    echo ""
    echo "Querying bids again in 30 seconds..."
    sleep 30

    BIDS=$(provider-services query market bid get \
        --dseq "$DSEQ" \
        --state open \
        --node "$RPC_NODE" \
        --output json 2>/dev/null || echo "[]")

    BID_COUNT=$(echo "$BIDS" | jq '.bids | length' 2>/dev/null || echo "0")
    echo "Bids found after wait: $BID_COUNT"
    echo ""

    if [ "$BID_COUNT" -eq 0 ]; then
        echo "❌ ERROR: Still no bids. Check provider logs:"
        echo "  kubectl logs akash-provider-0 -n akash-services"
        exit 1
    fi
fi

echo "✓ Provider bid received!"
echo ""

# Step 4: Get bid details and create lease
echo "=== Step 4: Create Lease from Winning Bid ==="

# Get first bid details
FIRST_BID=$(echo "$BIDS" | jq '.bids[0]' 2>/dev/null)

GSEQ=$(echo "$FIRST_BID" | jq -r '.bid.id.gseq')
OSEQ=$(echo "$FIRST_BID" | jq -r '.bid.id.oseq')
PROVIDER=$(echo "$FIRST_BID" | jq -r '.bid.id.provider')

echo "Bid Details:"
echo "  DSEQ: $DSEQ"
echo "  GSEQ: $GSEQ"
echo "  OSEQ: $OSEQ"
echo "  Provider: $PROVIDER"
echo ""

# Create lease
LEASE_OUTPUT=$(provider-services tx market lease create \
    --dseq "$DSEQ" \
    --gseq "$GSEQ" \
    --oseq "$OSEQ" \
    --from "$WALLET_NAME" \
    --node "$RPC_NODE" \
    --chain-id "$CHAIN_ID" \
    --yes 2>&1)

echo "$LEASE_OUTPUT"
echo ""

# Extract lease success
if echo "$LEASE_OUTPUT" | grep -q "Lease created"; then
    echo "✓ Lease created successfully!"
elif echo "$LEASE_OUTPUT" | grep -q "raw_log"; then
    echo "✓ Lease created successfully (raw format)"
else
    echo "⚠️  WARNING: Lease creation unclear. Check output above."
fi
echo ""

# Step 5: Send manifest to provider
echo "=== Step 5: Send Manifest to Provider ==="
echo "This tells the provider what to deploy for this lease"
echo ""

MANIFEST_OUTPUT=$(provider-services send-manifest \
    "$SDL_FILE" \
    --dseq "$DSEQ" \
    --provider "$PROVIDER_ADDRESS" \
    --from "$WALLET_NAME" 2>&1)

echo "$MANIFEST_OUTPUT"
echo ""

if echo "$MANIFEST_OUTPUT" | grep -q "manifest sent"; then
    echo "✓ Manifest sent successfully!"
elif echo "$MANIFEST_OUTPUT" | grep -q "raw_log"; then
    echo "✓ Manifest sent (raw format)"
else
    echo "⚠️  WARNING: Manifest sending unclear. Check output above."
fi
echo ""

# Step 6: Verify lease status
echo "=== Step 6: Verify Lease Status ==="
sleep 5

LEASE_STATUS=$(provider-services query market lease get \
    --dseq "$DSEQ" \
    --state active \
    --node "$RPC_NODE" \
    --output json 2>/dev/null || echo "[]")

LEASE_COUNT=$(echo "$LEASE_STATUS" | jq '.leases | length' 2>/dev/null || echo "0")

echo "Active Leases: $LEASE_COUNT"

if [ "$LEASE_COUNT" -gt 0 ]; then
    echo "✓ SUCCESS: Keepalive deployment is active!"
    echo ""
    echo "The provider should now have an active lease and stay running."
    echo ""
    echo "Monitor provider logs:"
    echo "  kubectl logs -f akash-provider-0 -n akash-services"
    echo ""
    echo "Check provider status:"
    echo "  kubectl exec -it akash-provider-0 -n akash-services -- provider-services status"
else
    echo "❌ ERROR: Lease not active. Check:"
    echo "  1. Provider logs for errors"
    echo "  2. Deployment status on blockchain"
    echo "  3. Lease creation transaction"
fi
echo ""

echo "=== Deployment Complete ==="
echo "DSEQ: $DSEQ"
echo "Provider: $PROVIDER_ADDRESS"
echo ""
echo "To clean up later:"
echo "  provider-services tx market lease close --dseq $DSEQ --gseq $GSEQ --oseq $OSEQ --from $WALLET_NAME"
