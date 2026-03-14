# Akash Provider Module for NixOS
# Decentralized cloud compute marketplace provider
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.akash-provider = {
    enable = lib.mkEnableOption "Akash Network provider - earn AKT/USDC by hosting compute workloads";

    providerAddress = lib.mkOption {
      type = lib.types.str;
      description = "Akash provider wallet address (e.g., akash1abc...)";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "cluster.local";
      description = "Public domain for provider ingress (can use dynamic DNS)";
    };

    clusterPublicHostname = lib.mkOption {
      type = lib.types.str;
      example = "provider.example.com";
      description = "Provider's public hostname for bid engine";
    };

    # GPU pricing configuration (uakt per block)
    pricing = {
      rtx3090 = lib.mkOption {
        type = lib.types.ints.u16;
        default = 20000;
        description = "Price for RTX 3090 (uakt/block)";
      };
      rtx4060 = lib.mkOption {
        type = lib.types.ints.u16;
        default = 18000;
        description = "Price for RTX 4060 (uakt/block)";
      };
      rtx3060ti = lib.mkOption {
        type = lib.types.ints.u16;
        default = 15000;
        description = "Price for RTX 3060 Ti (uakt/block)";
      };
      rx5700xt = lib.mkOption {
        type = lib.types.ints.u16;
        default = 8000;
        description = "Price for RX 5700 XT (uakt/block)";
      };
      rx5600xt = lib.mkOption {
        type = lib.types.ints.u16;
        default = 7000;
        description = "Price for RX 5600 XT (uakt/block)";
      };
    };
  };

  config = lib.mkIf config.services.akash-provider.enable {
    # ============================================================================
    # REQUIRED PACKAGES
    # ============================================================================
    environment.systemPackages = with pkgs; [
      helm
      kubectl
      gnupg # For wallet key operations
      bc # For pricing calculations
      jq # For JSON parsing in bid script
    ];

    # ============================================================================
    # AKASH PROVIDER NAMESPACE
    # ============================================================================
    # Create Kubernetes namespace for Akash services via manifest
    environment.etc."kubernetes/manifests/akash-namespace.yaml".text = builtins.toJSON {
      apiVersion = "v1";
      kind = "Namespace";
      metadata = {
        name = "akash-services";
        labels = {
          "akash.network/name" = "akash-services";
          "akash.network" = "true";
        };
      };
    };

    # ============================================================================
    # STORAGE CLASSES FOR AKASH
    # ============================================================================
    # Akash uses specific storage class names (beta2, beta3, ram)
    environment.etc."kubernetes/manifests/akash-storage-classes.yaml".text = builtins.toJSON {
      apiVersion = "v1";
      kind = "List";
      items = [
        {
          apiVersion = "storage.k8s.io/v1";
          kind = "StorageClass";
          metadata = {
            name = "beta2";
            annotations = {
              "storageclass.kubernetes.io/is-default-class" = "false";
            };
          };
          provisioner = "rancher.io/local-path";
          reclaimPolicy = "Delete";
          volumeBindingMode = "WaitForFirstConsumer";
        }
        {
          apiVersion = "storage.k8s.io/v1";
          kind = "StorageClass";
          metadata = {
            name = "beta3";
          };
          provisioner = "rancher.io/local-path";
          reclaimPolicy = "Delete";
          volumeBindingMode = "WaitForFirstConsumer";
        }
        {
          apiVersion = "storage.k8s.io/v1";
          kind = "StorageClass";
          metadata = {
            name = "ram";
          };
          provisioner = "rancher.io/local-path";
          reclaimPolicy = "Delete";
          volumeBindingMode = "WaitForFirstConsumer";
        }
      ];
    };

    # ============================================================================
    # NGINX INGRESS CONTROLLER (Required for Akash)
    # ============================================================================
    # Akash requires an ingress controller to route tenant HTTP/HTTPS traffic
    environment.etc."kubernetes/manifests/ingress-nginx.yaml".source = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml";
      hash = "sha256:150rf4nrxws31d9a69c5lkq1jyy2nsn20225kpvlqb0lcjjyyz3h";
    };

    # ============================================================================
    # NODE LABELS FOR GPU ATTRIBUTES
    # ============================================================================
    # Label nodes so Akash's inventory operator can detect GPU capabilities
    # Format: akash.network/capabilities.gpu.vendor.<vendor>.model.<model>=true
    systemd.services.akash-node-labels = {
      description = "Label Kubernetes nodes with Akash GPU attributes";
      wantedBy = ["multi-user.target"];
      after = ["kubernetes.target"];
      path = [pkgs.kubectl];
      script = ''
        # Wait for Kubernetes to be ready
        until kubectl get nodes > /dev/null 2>&1; do sleep 5; done

        # Zephyr: RTX 3090 + RTX 3060 Ti (NVIDIA)
        if [ "$(hostname)" = "zephyr" ]; then
          kubectl label node zephyr akash.network/capabilities.gpu.vendor.nvidia.model.rtx3090=true --overwrite 2>/dev/null || true
          kubectl label node zephyr akash.network/capabilities.gpu.vendor.nvidia.model.rtx3060ti=true --overwrite 2>/dev/null || true
        fi

        # Nexus: RTX 3060 Ti (NVIDIA)
        if [ "$(hostname)" = "nexus" ]; then
          kubectl label node nexus akash.network/capabilities.gpu.vendor.nvidia.model.rtx3060ti=true --overwrite 2>/dev/null || true
        fi

        # Forge: 2x RTX 4060 (NVIDIA) + 2x RX 5700 XT (AMD)
        if [ "$(hostname)" = "forge" ]; then
          kubectl label node forge akash.network/capabilities.gpu.vendor.nvidia.model.rtx4060=true --overwrite 2>/dev/null || true
          kubectl label node forge akash.network/capabilities.gpu.vendor.amd.model.rx5700xt=true --overwrite 2>/dev/null || true
        fi

        # Sentry: RX 5600 XT (AMD)
        if [ "$(hostname)" = "sentry" ]; then
          kubectl label node sentry akash.network/capabilities.gpu.vendor.amd.model.rx5600xt=true --overwrite 2>/dev/null || true
        fi

        # Region labels for all nodes
        kubectl label node $(hostname) topology.kubernetes.io/region=us-west --overwrite 2>/dev/null || true
        kubectl label node $(hostname) topology.kubernetes.io/zone=homelab --overwrite 2>/dev/null || true
      '';
    };

    # ============================================================================
    # PROVIDER HELM VALUES (Generated from NixOS config)
    # ============================================================================
    environment.etc."akash-provider-values.yaml".text = lib.generators.toYAML {} {
      # Chain configuration
      chainid = "akashnet-2";
      node = "https://rpc.akashnet.net:443";

      # Provider identity
      inherit (config.services.akash-provider) providerAddress;
      from = "provider-wallet";
      keysecret = "akash-provider-keys";

      # Networking
      inherit (config.services.akash-provider) domain clusterPublicHostname;

      # Withdrawal period (blocks) - 720 blocks = ~72 minutes
      withdrawalperiod = 720;

      # Bid pricing script (generated from node-specific pricing)
      bidpricescript = ''
        #!/bin/bash
        set -e
        data_in=$(jq .)

        # Parse requested resources
        cpu=$(echo "$data_in" | jq -r '.cpu')
        memory=$(echo "$data_in" | jq -r '.memory')
        storage=$(echo "$data_in" | jq -r '.storage')
        gpu=$(echo "$data_in" | jq -r '.gpu')
        gpu_model=$(echo "$data_in" | jq -r '.gpu_model // empty')

        # Calculate base price (uakt per block)
        cpu_price=$(echo "scale=6; $cpu / 1000 * 1.5" | bc)
        memory_price=$(echo "scale=6; $memory / 1073741824 * 0.8" | bc)
        storage_price=$(echo "scale=6; $storage / 1073741824 * 0.02" | bc)

        # GPU pricing by model
        if [ "$gpu" -gt 0 ]; then
          case "$gpu_model" in
            *rtx3090*|*RTX3090*) gpu_price=$(echo "scale=6; $gpu * ${toString config.services.akash-provider.pricing.rtx3090}" | bc) ;;
            *rtx4060*|*RTX4060*) gpu_price=$(echo "scale=6; $gpu * ${toString config.services.akash-provider.pricing.rtx4060}" | bc) ;;
            *rtx3060*|*RTX3060*) gpu_price=$(echo "scale=6; $gpu * ${toString config.services.akash-provider.pricing.rtx3060ti}" | bc) ;;
            *rx5700*|*RX5700*) gpu_price=$(echo "scale=6; $gpu * ${toString config.services.akash-provider.pricing.rx5700xt}" | bc) ;;
            *rx5600*|*RX5600*) gpu_price=$(echo "scale=6; $gpu * ${toString config.services.akash-provider.pricing.rx5600xt}" | bc) ;;
            *) gpu_price=$(echo "scale=6; $gpu * 10000" | bc) ;;  # Default pricing
          esac
        else
          gpu_price=0
        fi

        # Total price with minimum floor
        total=$(echo "scale=6; $cpu_price + $memory_price + $storage_price + $gpu_price" | bc)
        min_price=1
        if (( $(echo "$total < $min_price" | bc -l) )); then
          total=$min_price
        fi

        echo "$total"
      '';

      # Image configuration
      image = {
        repository = "ghcr.io/akash-network/provider";
        tag = "0.6.4";
      };

      # Resource limits for provider pod
      resources = {
        limits = {
          cpu = "2";
          memory = "2Gi";
        };
        requests = {
          cpu = "500m";
          memory = "512Mi";
        };
      };

      # Cluster settings
      cluster = {
        maxDeployments = 100;
        memoryOvercommitPercent = 0;
        cpuOvercommitPercent = 0;
      };

      # Logging
      log = {
        level = "info";
      };

      # Features
      features = {
        ipOperator = false;
        persistentStorage = true;
      };
    };

    # ============================================================================
    # HELM REPOSITORY SETUP
    # ============================================================================
    systemd.services.akash-helm-init = {
      description = "Add Akash Helm repository";
      wantedBy = ["multi-user.target"];
      path = [pkgs.helm];
      script = ''
        # Add Akash Helm repository
        helm repo add akash https://akash-network.github.io/helm-charts || true
        helm repo update
      '';
    };

    # ============================================================================
    # WALLET KEY SECRET (via Agenix)
    # ============================================================================
    # The wallet key is decrypted from /run/agenix/akash-provider-key.pem
    # This secret is then mounted into the Kubernetes cluster
    systemd.services.akash-wallet-secret = {
      description = "Create Akash provider wallet secret from agenix";
      wantedBy = ["multi-user.target"];
      after = ["kubernetes.target" "agenix-rekey.service"];
      path = [pkgs.kubectl pkgs.coreutils pkgs.util-linux];
      script = ''
        # Wait for namespace
        until kubectl get namespace akash-services > /dev/null 2>&1; do sleep 2; done

        # Wait for agenix secret to be decrypted
        # Note: agenix strips the .age extension, so akash-provider-key.age → akash-provider-key
        KEY_FILE="/run/agenix/akash-provider-key"
        TIMEOUT=60
        ELAPSED=0
        while [ ! -f "$KEY_FILE" ] && [ $ELAPSED -lt $TIMEOUT ]; do
          echo "Waiting for $KEY_FILE..."
          sleep 2
          ELAPSED=$((ELAPSED + 2))
        done

        if [ ! -f "$KEY_FILE" ]; then
          echo "ERROR: Akash provider key not found at $KEY_FILE"
          echo "Please run: agenix -e secrets/akash-provider-key.age"
          exit 1
        fi

        # Create secret from decrypted key file
        kubectl create secret generic akash-provider-keys \
          --namespace akash-services \
          --from-file=key.pem="$KEY_FILE" \
          --dry-run=client -o yaml | \
          kubectl apply -f -

        echo "Akash provider wallet secret created"
      '';
    };

    # ============================================================================
    # HELM DEPLOYMENT SERVICE
    # ============================================================================
    # Note: Actual provider deployment done manually via Helm after wallet setup
    # This service ensures prerequisites are met
    systemd.services.akash-provider-prereq = {
      description = "Akash Provider Prerequisites Check";
      wantedBy = ["multi-user.target"];
      after = [
        "kubernetes.target"
        "akash-node-labels.service"
        "akash-wallet-secret.service"
      ];
      path = [pkgs.kubectl];
      script = ''
        # Verify prerequisites
        echo "Checking Akash provider prerequisites..."

        # Check nodes
        kubectl get nodes

        # Check GPU resources (if NVIDIA)
        kubectl describe nodes 2>/dev/null | grep -i "nvidia.com/gpu" || echo "No NVIDIA GPUs detected"

        # Check storage classes
        kubectl get storageclass | grep -E "(beta2|beta3|ram)" || echo "Warning: Akash storage classes not found"

        echo "Akash provider prerequisites checked."
        echo "To deploy the provider, run:"
        echo "  helm upgrade --install akash-provider akash/provider --namespace akash-services --values /etc/akash-provider-values.yaml"
      '';
    };
  };
}
