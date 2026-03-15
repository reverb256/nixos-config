# GPU Resource Marketplace Module
# Unified auction engine for GPU resource allocation
# Bidders: Mining, Kubernetes, Akash, Gaming (priority override)
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.compute-market = {
    enable = lib.mkEnableOption "GPU Resource Marketplace - unified auction engine for GPU allocation";

    auctionInterval = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Auction interval in seconds";
    };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/run/compute-market";
      description = "Directory for auction state and bidding information";
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/compute-market.log";
      description = "Path to log file";
    };

    # Mining bidder configuration
    bidders.mining = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable mining as baseline bidder";
      };

      hourlyRevenue = lib.mkOption {
        type = lib.types.float;
        default = 0.10;
        description = "Hourly revenue per GPU in USD (baseline bid)";
      };

      services = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["lolminer-nvidia" "lolminer-amd" "xmrig"];
        description = "Mining services to manage";
      };
    };

    # Kubernetes bidder configuration
    bidders.kubernetes = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Kubernetes workload bidder";
      };

      baseBid = lib.mkOption {
        type = lib.types.float;
        default = 2.50;
        description = "Base hourly bid per GPU in USD for K8s workloads";
      };

      urgencyMultiplier = lib.mkOption {
        type = lib.types.float;
        default = 2.0;
        description = "Multiplier for jobs with deadlines";
      };

      namespace = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "Kubernetes namespace to monitor for GPU workloads";
      };
    };

    # Akash bidder configuration
    bidders.akash = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Akash Network lease bidder";
      };

      profitMargin = lib.mkOption {
        type = lib.types.float;
        default = 0.90;
        description = "Percentage of market price to bid (0.90 = bid 90% of market rate)";
      };

      namespace = lib.mkOption {
        type = lib.types.str;
        default = "akash-services";
        description = "Akash provider namespace";
      };
    };

    # Gaming override configuration
    bidders.gaming = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable gaming as priority override (always wins)";
      };

      processes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "steam" "steamwebhelper" "steamapps"
          "lutris" "heroic" "Lutris" "HeroicGamesLauncher"
          "wine" "proton"
        ];
        description = "Process names that indicate gaming activity";
      };
    };

    # Prometheus metrics
    prometheus = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Prometheus metrics exporter";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 9200;
        description = "Port for Prometheus metrics";
      };
    };
  };

  config = lib.mkIf config.services.compute-market.enable {
    # ============================================================================
    # REQUIRED PACKAGES
    # ============================================================================
    environment.systemPackages = with pkgs; [
      procps           # pgrep for process detection
      systemd          # systemctl for service control
      kubernetes       # kubectl for K8s queries
      kubectl          # Explicit kubectl
      bc               # Floating-point arithmetic
      curl             # HTTP API calls
      jq               # JSON parsing for Akash bids
      coreutils        # Basic utilities
      util-linux       # For various utilities
    ];

    # ============================================================================
    # STATE DIRECTORY
    # ============================================================================
    systemd.tmpfiles.rules = [
      "d ${config.services.compute-market.stateDirectory} 0755 root root -"
      "d ${config.services.compute-market.stateDirectory}/bidders 0755 root root -"
    ];

    # ============================================================================
    # AUCTION ENGINE DAEMON
    # ============================================================================
    systemd.services.compute-market = {
      description = "GPU Resource Marketplace Auction Engine";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "kubernetes.target"];
      wants = ["prometheus-node-exporter.service"];

      path = with pkgs; [
        procps systemd kubernetes kubectl bc curl jq coreutils util-linux
      ];

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "10s";
        Environment = [
          "PATH=${lib.makeBinPath (with pkgs; [procps systemd kubernetes kubectl bc curl jq coreutils util-linux])}:/run/current-system/sw/bin"
          "STATE_DIR=${config.services.compute-market.stateDirectory}"
          "LOG_FILE=${config.services.compute-market.logFile}"
        ];
        ExecStart = "${pkgs.writeShellScriptBin "compute-market-engine" ''
          # ============================================================================
          # GPU RESOURCE MARKETPLACE - AUCTION ENGINE
          # ============================================================================
          # Coordinates GPU allocation between competing bidders:
          # - Mining (baseline passive income)
          # - Kubernetes (AI/ML workloads)
          # - Akash Network (decentralized compute marketplace)
          # - Gaming (priority override, always wins)
          # ============================================================================

          set -euo pipefail

          STATE_DIR="''${STATE_DIR:-/run/compute-market}"
          LOG_FILE="''${LOG_FILE:-/var/log/compute-market.log}"
          AUCTION_INTERVAL=''${AUCTION_INTERVAL:-30}
          PROMETHEUS_PORT=''${PROMETHEUS_PORT:-9200}

          # Bidder configurations from NixOS
          MINING_ENABLE=''${MINING_ENABLE:-true}
          MINING_HOURLY=''${MINING_HOURLY:-0.10}
          MINING_SERVICES="''${MINING_SERVICES:-lolminer-nvidia xmrig}"

          K8S_ENABLE=''${K8S_ENABLE:-true}
          K8S_BASE_BID=''${K8S_BASE_BID:-2.50}
          K8S_URGENCY_MULT=''${K8S_URGENCY_MULT:-2.0}
          K8S_NAMESPACE=''${K8S_NAMESPACE:-default}

          AKASH_ENABLE=''${AKASH_ENABLE:-true}
          AKASH_MARGIN=''${AKASH_MARGIN:-0.90}
          AKASH_NAMESPACE=''${AKASH_NAMESPACE:-akash-services}

          GAMING_ENABLE=''${GAMING_ENABLE:-true}
          GAMING_PROCESSES="''${GAMING_PROCESSES:-steam lutris heroic wine proton}"

          # ============================================================================
          # LOGGING FUNCTIONS
          # ============================================================================
          log() {
              local level="''${1:-INFO}"
              shift
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
          }

          log_debug() { log "DEBUG" "$@"; }
          log_info() { log "INFO" "$@"; }
          log_warn() { log "WARN" "$@"; }
          log_error() { log "ERROR" "$@"; }
          log_auction() { log "AUCTION" "$@"; }

          # ============================================================================
          # PROMETHEUS METRICS
          # ============================================================================
          update_metrics() {
              local winner=''${1:-none}
              local winning_bid=''${2:-0}
              local mining_bid=''${3:-0}
              local k8s_bid=''${4:-0}
              local akash_bid=''${5:-0}
              local gaming_active=''${6:-false}

              cat > "$STATE_DIR/metrics.prom" << EOF
          # HELP compute_market_auction_winner The current auction winner
          # TYPE compute_market_auction_winner gauge
          compute_market_auction_winner{winner="$winner"} 1

          # HELP compute_market_winning_bid_usd The winning bid amount in USD
          # TYPE compute_market_winning_bid_usd gauge
          compute_market_winning_bid_usd ''${winning_bid}

          # HELP compute_market_bid_current Current bid by bidder type
          # TYPE compute_market_bid_current gauge
          compute_market_bid_current{bidder="mining"} ''${mining_bid}
          compute_market_bid_current{bidder="kubernetes"} ''${k8s_bid}
          compute_market_bid_current{bidder="akash"} ''${akash_bid}
          compute_market_bid_current{bidder="gaming"} 999.99

          # HELP compute_market_gaming_active Whether gaming is currently active
          # TYPE compute_market_gaming_active gauge
          compute_market_gaming_active ''${gaming_active}

          # HELP compute_market_auction_total Total auctions run
          # TYPE compute_market_auction_total counter
          compute_market_auction_total $(cat "$STATE_DIR/auction_count" 2>/dev/null || echo 0)
          EOF
          }

          # ============================================================================
          # BIDDER IMPLEMENTATIONS
          # ============================================================================

          # Mining Bidder - Returns baseline hourly revenue
          bid_mining() {
              if [ "$MINING_ENABLE" != "true" ]; then
                  echo 0
                  return
              fi

              # Check if any mining service is active
              for service in $MINING_SERVICES; do
                  if systemctl is-active --quiet "$service"; then
                      echo "$MINING_HOURLY"
                      return
                  fi
              done

              # Mining not active, but could be started
              echo "$MINING_HOURLY"
          }

          # Kubernetes Bidder - Calculates value based on pending jobs
          bid_kubernetes() {
              if [ "$K8S_ENABLE" != "true" ]; then
                  echo 0
                  return
              fi

              # Check if kubectl is available
              if ! command -v kubectl >/dev/null 2>&1; then
                  log_debug "kubectl not available"
                  echo 0
                  return
              fi

              # Check if cluster is accessible
              if ! kubectl get nodes >/dev/null 2>&1; then
                  log_debug "Kubernetes cluster not accessible"
                  echo 0
                  return
              fi

              local hostname=$(hostname)
              local total_bid=0

              # Get GPU pods on this node
              local gpu_pods=$(kubectl get pods --all-namespaces \
                  --field-selector=spec.nodeName="$hostname" \
                  -o jsonpath='{range .items[?(@.spec.containers[*].resources.limits.nvidia\\.com/gpu)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
                  2>/dev/null || echo "")

              if [ -z "$gpu_pods" ]; then
                  echo 0
                  return
              fi

              # Calculate bid for each running GPU pod
              while IFS= read -r pod; do
                  [ -z "$pod" ] && continue
                  local namespace=$(echo "$pod" | cut -d'/' -f1)
                  local name=$(echo "$pod" | cut -d'/' -f2)

                  # Check if pod is running
                  if kubectl get pod "$name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; then
                      # Check for priority class (higher priority = higher bid)
                      local priority_class=$(kubectl get pod "$name" -n "$namespace" \
                          -o jsonpath='{.spec.priorityClassName}' 2>/dev/null || echo "")

                      local bid=$K8S_BASE_BID

                      # Urgency multiplier for jobs with deadlines or high priority
                      if [[ "$priority_class" =~ (high|urgent|critical) ]]; then
                          bid=$(echo "$bid * $K8S_URGENCY_MULT" | bc)
                      fi

                      total_bid=$(echo "$total_bid + $bid" | bc)
                  fi
              done <<< "$gpu_pods"

              echo "$total_bid"
          }

          # Akash Bidder - Returns current market rate for active leases
          bid_akash() {
              if [ "$AKASH_ENABLE" != "true" ]; then
                  echo 0
                  return
              fi

              # Check if Akash provider is running
              if ! kubectl get pods -n "$AKASH_NAMESPACE" -l app=akash-provider >/dev/null 2>&1; then
                  echo 0
                  return
              fi

              # Get active leases for this node
              local hostname=$(hostname)
              local active_leases=$(kubectl get leases -n "$AKASH_NAMESPACE" \
                  -o jsonpath='{range .items[?(@.status.currentState == "active")]}{.metadata.name}{"\n"}{end}' \
                  2>/dev/null || echo "")

              if [ -z "$active_leases" ]; then
                  echo 0
                  return
              fi

              # For each active lease, calculate bid based on escrowed payment
              local total_bid=0
              while IFS= read -r lease; do
                  [ -z "$lease" ] && continue

                  # Get lease price (in uakt per block)
                  local price=$(kubectl get lease "$lease" -n "$AKASH_NAMESPACE" \
                      -o jsonpath='{.spec.price}' 2>/dev/null || echo "0")

                  # Convert to USD/hour (rough approximation: 1 AKT ≈ $0.50, blocks ≈ 6s)
                  # uakt/block * AKT_price * (3600 / 6) / 1_000_000
                  local usd_hourly=$(echo "scale=4; $price * 0.50 * 600 / 1000000" | bc)

                  # Apply profit margin (we bid slightly less than full market value)
                  local our_bid=$(echo "$usd_hourly * $AKASH_MARGIN" | bc)

                  total_bid=$(echo "$total_bid + $our_bid" | bc)
              done <<< "$active_leases"

              echo "$total_bid"
          }

          # Gaming Bidder - Priority override (returns sentinel value)
          check_gaming() {
              if [ "$GAMING_ENABLE" != "true" ]; then
                  echo "false"
                  return
              fi

              for proc in $GAMING_PROCESSES; do
                  if pgrep -fi "$proc" >/dev/null 2>&1; then
                      echo "true"
                      return
                  fi
              done

              echo "false"
          }

          # ============================================================================
          # AUCTION ENGINE
          # ============================================================================
          run_auction() {
              # Increment auction counter
              local count=$(($(cat "$STATE_DIR/auction_count" 2>/dev/null || echo 0) + 1))
              echo "$count" > "$STATE_DIR/auction_count"

              # Get current state
              local current_winner=$(cat "$STATE_DIR/current_winner" 2>/dev/null || echo "none")
              local gaming_active=$(check_gaming)

              # Gaming override - always wins
              if [ "$gaming_active" = "true" ]; then
                  log_auction "GAMING OVERRIDE - Gaming detected, pausing all GPU workloads"
                  update_metrics "gaming" 999.99 0 0 0 "true"
                  echo "gaming" > "$STATE_DIR/current_winner"
                  apply_gaming_profile
                  return
              fi

              # Collect bids
              local mining_bid=$(bid_mining)
              local k8s_bid=$(bid_kubernetes)
              local akash_bid=$(bid_akash)

              log_auction "Auction #$count - Mining: \$$mining_bid/hr | K8s: \$$k8s_bid/hr | Akash: \$$akash_bid/hr"

              # Determine winner
              local winner="mining"
              local winning_bid=$mining_bid

              if (( $(echo "$k8s_bid > $winning_bid" | bc -l) )); then
                  winner="kubernetes"
                  winning_bid=$k8s_bid
              fi

              if (( $(echo "$akash_bid > $winning_bid" | bc -l) )); then
                  winner="akash"
                  winning_bid=$akash_bid
              fi

              # Check if winner changed
              if [ "$winner" != "$current_winner" ]; then
                  log_auction "WINNER CHANGED: $current_winner → $winner (\$$winning_bid/hr)"
                  echo "$winner" > "$STATE_DIR/current_winner"
                  apply_winner_profile "$winner"
              else
                  log_debug "Winner unchanged: $winner (\$$winning_bid/hr)"
              fi

              update_metrics "$winner" "$winning_bid" "$mining_bid" "$k8s_bid" "$akash_bid" "false"
          }

          # ============================================================================
          # PROFILE APPLICATION
          # ============================================================================
          apply_gaming_profile() {
              log_info "Applying GAMING profile - all GPU workloads paused"
              pause_all_mining
          }

          apply_winner_profile() {
              local winner="''${1:-mining}"

              case "$winner" in
                  mining)
                      log_info "Applying MINING profile - resuming mining operations"
                      resume_mining
                      ;;
                  kubernetes)
                      log_info "Applying KUBERNETES profile - pausing mining for K8s workloads"
                      pause_all_mining
                      ;;
                  akash)
                      log_info "Applying AKASH profile - pausing mining for Akash leases"
                      pause_all_mining
                      ;;
                  *)
                      log_warn "Unknown winner: $winner"
                      ;;
              esac
          }

          pause_all_mining() {
              for service in $MINING_SERVICES; do
                  if systemctl is-active --quiet "$service"; then
                      log_info "Pausing $service (CPUQuota=0%)"
                      systemctl set-property "$service.service" CPUQuota="0%" --runtime
                      echo "$service" >> "$STATE_DIR/paused_services"
                  fi
              done
          }

          resume_mining() {
              # Read paused services and resume them
              if [ -f "$STATE_DIR/paused_services" ]; then
                  while IFS= read -r service; do
                      [ -z "$service" ] && continue
                      log_info "Resuming $service (CPUQuota=100%)"
                      systemctl set-property "$service.service" CPUQuota="100%" --runtime
                  done < "$STATE_DIR/paused_services"
                  rm -f "$STATE_DIR/paused_services"
              fi
          }

          # ============================================================================
          # PROMETHEUS METRICS SERVER
          # ============================================================================
          start_metrics_server() {
              # Simple HTTP server for Prometheus scraping
              while true; do
                  {
                      echo "HTTP/1.1 200 OK"
                      echo "Content-Type: text/plain"
                      echo ""
                      cat "$STATE_DIR/metrics.prom" 2>/dev/null || echo "# No metrics yet"
                  } | nc -l -p "$PROMETHEUS_PORT" > /dev/null 2>&1 || true
              done &
          }

          # ============================================================================
          # MAIN LOOP
          # ============================================================================
          main() {
              log_info "=== GPU Resource Marketplace Starting ==="
              log_info "State directory: $STATE_DIR"
              log_info "Auction interval: $AUCTION_INTERVAL seconds"

              # Initialize state
              echo "0" > "$STATE_DIR/auction_count"
              echo "none" > "$STATE_DIR/current_winner"
              update_metrics "none" 0 0 0 0 "false"

              # Start metrics server in background
              # start_metrics_server  # Disabled: nc may not be available

              # Main auction loop
              while true; do
                  run_auction
                  sleep "$AUCTION_INTERVAL"
              done
          }

          # Run main function
          main "$@"
        ''}";
      };
    };

    # ============================================================================
    # PROMETHEUS SCRAPE CONFIG
    # ============================================================================
    services.prometheus.scrapeConfigs = lib.mkIf config.services.compute-market.prometheus.enable [
      {
        job_name = "compute-market";
        static_configs = [{
          targets = ["127.0.0.1:${toString config.services.compute-market.prometheus.port}"];
        }];
      }
    ];
  };
}
