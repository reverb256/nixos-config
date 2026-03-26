#!/usr/bin/env python3
"""
Restore AUTO-KEEPALIVE section to init.sh by removing the early exit.
"""

import yaml
import json
import subprocess
import sys

# Get current ConfigMap
result = subprocess.run(
    ['kubectl', 'get', 'configmap', 'akash-provider-script', '-n', 'akash-services', '-o', 'json'],
    capture_output=True,
    text=True,
    check=False
)

if result.returncode != 0:
    print(f"❌ Error getting ConfigMap: {result.stderr}")
    sys.exit(1)

configmap = json.loads(result.stdout)

# Get current init.sh
init_sh = configmap['data']['init.sh']

# Find and replace the early exit section
early_exit_marker = """    # === KEEPALIVE DEPLOYMENT ===
    echo "=== AUTO-KEEPALIVE: Creating minimal deployment ==="
    echo "AUTO-KEEPALIVE skipped (provider will start without self-deployment)"
    exit 0
else
    echo "✗ Address mismatch!"
    exit 1
fi"""

full_keepalive_section = """    # === KEEPALIVE DEPLOYMENT ===
    echo "=== AUTO-KEEPALIVE: Creating minimal deployment ==="
    echo "Wallet: $AKASH_FROM"
    PROVIDER_ADDRESS="akash1c6h804ky08tdpnxrv72vum783xuey09qzt2p6"
    SDL_FILE="/scripts/keepalive-deployment.yaml"
    echo "Provider: $PROVIDER_ADDRESS"
    echo ""

    # Check if deployment already exists
    echo "Checking for existing deployments..."
    EXISTING_DEPLOYMENTS=$(provider-services query market deployment list --owner=$AKASH_FROM --output=json 2>/dev/null | jq -r '.deployments | length' || echo "0")
    echo "Existing deployments: $EXISTING_DEPLOYMENTS"

    if [ "$EXISTING_DEPLOYMENTS" -gt "0" ]; then
        echo "Deployment already exists, checking for active leases..."
        ACTIVE_LEASES=$(provider-services query market lease list --provider=$PROVIDER_ADDRESS --state=active --output=json 2>/dev/null | jq -r '.leases | length' || echo "0")
        echo "Active leases: $ACTIVE_LEASES"

        if [ "$ACTIVE_LEASES" -gt "0" ]; then
            echo "✓ Active lease found - provider will stay running!"
            exit 0
        fi
    fi

    echo "Creating new keepalive deployment..."

    # Create deployment WITHOUT deposit flag (per official Akash documentation)
    # Blockchain handles deposit automatically via escrow
    DEPLOYMENT_OUTPUT=$(provider-services tx deployment create $SDL_FILE --from $AKASH_FROM --yes 2>&1)
    echo "$DEPLOYMENT_OUTPUT"

    DSEQ=$(echo "$DEPLOYMENT_OUTPUT" | grep -oP 'dseq: \\K\\d+' || echo '')
    if [ -z "$DSEQ" ]; then
        echo "❌ ERROR: Failed to create deployment"
        exit 1
    fi
    echo "✓ Deployment created: DSEQ $DSEQ"
    echo ""

    # Wait for bids
    echo "Waiting for provider to bid (10 seconds)..."
    sleep 10

    BIDS=$(provider-services query market bid get --dseq $DSEQ --state open --output json 2>/dev/null || echo '[]')
    BID_COUNT=$(echo "$BIDS" | jq '.bids | length' 2>/dev/null || echo '0')
    echo "Bids found: $BID_COUNT"

    if [ "$BID_COUNT" -eq "0" ]; then
        echo "⚠️  No bids yet, waiting 30 more seconds..."
        sleep 30
        BIDS=$(provider-services query market bid get --dseq $DSEQ --state open --output json 2>/dev/null || echo '[]')
        BID_COUNT=$(echo "$BIDS" | jq '.bids | length' 2>/dev/null || echo '0')
        echo "Bids after wait: $BID_COUNT"

        if [ "$BID_COUNT" -eq "0" ]; then
            echo "❌ ERROR: Provider did not bid on own deployment"
            echo "This might indicate a pricing or inventory issue"
            exit 1
        fi
    fi

    echo "✓ Provider bid received!"
    echo ""

    # Get bid details
    FIRST_BID=$(echo "$BIDS" | jq '.bids[0]')
    GSEQ=$(echo "$FIRST_BID" | jq -r '.bid.id.gseq')
    OSEQ=$(echo "$FIRST_BID" | jq -r '.bid.id.oseq')
    BID_PROVIDER=$(echo "$FIRST_BID" | jq -r '.bid.id.provider')

    echo "Bid details:"
    echo "  DSEQ: $DSEQ"
    echo "  GSEQ: $GSEQ"
    echo "  OSEQ: $OSEQ"
    echo "  Provider: $BID_PROVIDER"
    echo ""

    # Create lease
    echo "Creating lease..."
    LEASE_OUTPUT=$(provider-services tx market lease create --dseq $DSEQ --gseq $GSEQ --oseq $OSEQ --from $AKASH_FROM --yes 2>&1)
    echo "$LEASE_OUTPUT"
    echo ""

    # Send manifest
    echo "Sending manifest..."
    MANIFEST_OUTPUT=$(provider-services send-manifest $SDL_FILE --dseq $DSEQ --provider $PROVIDER_ADDRESS --from $AKASH_FROM 2>&1)
    echo "$MANIFEST_OUTPUT"
    echo ""

    # Verify lease
    echo "Verifying lease status..."
    sleep 5
    LEASE_STATUS=$(provider-services query market lease get --dseq $DSEQ --state active --output json 2>/dev/null || echo '[]')
    LEASE_COUNT=$(echo "$LEASE_STATUS" | jq '.leases | length' 2>/dev/null || echo '0')
    echo "Active leases: $LEASE_COUNT"

    if [ "$LEASE_COUNT" -gt "0" ]; then
        echo ""
        echo "✅ SUCCESS: KEEPALIVE DEPLOYMENT ACTIVE"
        echo "Provider should now stay running with active lease!"
        exit 0
    else
        echo "❌ ERROR: Lease not active"
        exit 1
    fi
else
    echo "✗ Address mismatch!"
    exit 1
fi"""

if early_exit_marker in init_sh:
    # Replace early exit with full keepalive section
    new_init_sh = init_sh.replace(early_exit_marker, full_keepalive_section)

    # Update ConfigMap
    configmap['data']['init.sh'] = new_init_sh

    # Apply to Kubernetes
    result = subprocess.run(
        ['kubectl', 'patch', 'configmap', 'akash-provider-script', '-n', 'akash-services',
         '--type=strategic', '--patch=-'],
        input=json.dumps({"data": {"init.sh": new_init_sh}}),
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print(f"❌ Error patching ConfigMap: {result.stderr}")
        sys.exit(1)

    print("✅ AUTO-KEEPALIVE restored to init.sh")
    print("✅ Removed early exit, full deployment logic enabled")
    print("\n🔄 Provider pod will restart and attempt to create keepalive deployment")
else:
    print("⚠️  Early exit marker not found - init.sh may already have keepalive logic")
    sys.exit(1)
