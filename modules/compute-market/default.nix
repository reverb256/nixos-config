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
        default = 0.014;
        description = "Hourly revenue per GPU in USD (actual: ~$96/month ÷ 7 GPUs ÷ 730 hrs)";
      };

      services = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "lolminer-nvidia"
          "lolminer-amd"
          "xmrig"
        ];
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
          # More specific patterns to avoid false positives (e.g., steam-run wrapper)
          "steam\\.exe"
          "steamwebhelper"
          "steamapps"
          "/Steam/"
          "lutris\\.bin"
          "heroic"
          "HeroicGamesLauncher"
          "wine(32|64)\\.exe"
          "proton:"
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

  config = let
    cfg = config.services.compute-market;
  in
    lib.mkIf cfg.enable {
    # ============================================================================
    # ASSERTIONS
    # ============================================================================
    assertions = [
      {
        assertion = cfg.auctionInterval > 0;
        message = ''
          GPU Marketplace requires a positive auction interval.

          Current value: ${toString cfg.auctionInterval}

          Recommended minimum: 30 (seconds)
          Recommended maximum: 300 (5 minutes)
        '';
      }
      {
        assertion = cfg.bidders.mining.hourlyRevenue >= 0.0;
        message = ''
          Mining hourly revenue cannot be negative.

          Current value: ${toString cfg.bidders.mining.hourlyRevenue}

          This represents the baseline revenue per GPU per hour that mining generates.
          Set to 0.0 if unknown, or calculate: monthly_revenue / 730 hours / num_gpus
        '';
      }
      {
        assertion = cfg.bidders.kubernetes.baseBid >= 0.0;
        message = ''
          Kubernetes base bid cannot be negative.

          Current value: ${toString cfg.bidders.kubernetes.baseBid}

          This represents the minimum hourly bid per GPU for Kubernetes workloads.
          Typical range: $2.00-$5.00 per GPU per hour
        '';
      }
      {
        assertion = cfg.bidders.kubernetes.urgencyMultiplier >= 1.0;
        message = ''
          Kubernetes urgency multiplier must be at least 1.0.

          Current value: ${toString cfg.bidders.kubernetes.urgencyMultiplier}

          This multiplier is applied to the base bid for urgent jobs.
          Range: 1.0 (no urgency) to 5.0 (high urgency)
        '';
      }
      {
        assertion = cfg.bidders.akash.profitMargin > 0.0 && cfg.bidders.akash.profitMargin <= 1.0;
        message = ''
          Akash profit margin must be between 0.0 and 1.0.

          Current value: ${toString cfg.bidders.akash.profitMargin}

          This represents the percentage of market price to bid.
          Example: 0.90 = bid 90% of market rate (10% margin)
        '';
      }
      {
        assertion = lib.any (bidder: bidder.enable) (lib.attrValues cfg.bidders);
        message = ''
          GPU Marketplace requires at least one bidder to be enabled.

          Currently enabled bidders: none

          Enable at least one bidder:
            services.compute-market.bidders.mining.enable = true;
            services.compute-market.bidders.kubernetes.enable = true;
            services.compute-market.bidders.akash.enable = true;
            services.compute-market.bidders.gaming.enable = true;
        '';
      }
      {
        assertion = cfg.prometheus.port > 0 && cfg.prometheus.port < 65536;
        message = ''
          Invalid Prometheus metrics port: ${toString cfg.prometheus.port}

          Port must be between 1 and 65535.
          Default: 9200
        '';
      }
    ];
    # ============================================================================
    # REQUIRED PACKAGES
    # ============================================================================
    environment.systemPackages = with pkgs; [
      procps # pgrep for process detection
      systemd # systemctl for service control
      kubernetes # kubectl for K8s queries
      kubectl # Explicit kubectl
      bc # Floating-point arithmetic
      curl # HTTP API calls
      jq # JSON parsing for Akash bids
      coreutils # Basic utilities
      util-linux # For various utilities
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
      after = [
        "network.target"
        "kubernetes.target"
      ];
      wants = ["prometheus-node-exporter.service"];

      path = with pkgs; [
        procps
        systemd
        kubernetes
        kubectl
        bc
        curl
        jq
        coreutils
        util-linux
      ];

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "10s";
        Environment = [
          "PATH=${
            lib.makeBinPath (
              with pkgs; [
                procps
                systemd
                kubernetes
                kubectl
                bc
                curl
                jq
                coreutils
                util-linux
              ]
            )
          }:/run/current-system/sw/bin"
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
          # Whitelist of specific game executables (regex patterns, separated by spaces)
          # Only matches exact process names, not launchers or helper processes
          #
          # Examples (configure via NixOS or environment variable):
          #   GAMING_GAMES="Cyberpunk2077.exe eldenring.exe Dota2.exe"
          #   GAMING_GAMES="steam_app_*.exe"  # Match all Steam games
          #   GAMING_GAMES=".*\.exe"  # Match all executables (NOT RECOMMENDED)
          #
          # Default: empty (opt-in) to avoid false positives
          # To enable gaming detection, add your games to /etc/nixos/hosts/*/configuration.nix:
          #   systemd.services.compute-market.environment.GAMING_GAMES = "Game1.exe Game2.exe";
          GAMING_GAMES="''${GAMING_GAMES:-}"

           # ============================================================================
           # GPU DETECTION
           # ============================================================================
          list_available_gpus() {
              # Detect available NVIDIA GPUs
              if command -v nvidia-smi >/dev/null 2>&1; then
                  nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null || echo "0"
              else
                  echo "0"  # No GPUs detected
              fi
          }

          # ============================================================================
          # PER-GPU STATE INITIALIZATION
          ============================================================================
          init_per_gpu_state() {
              local gpu_count=$(list_available_gpus | wc -l)

              for ((gpu_id=0; gpu_id<gpu_count; gpu_id++)); do
                  local gpu_state_dir="$STATE_DIR/gpu$gpu_id"
                  mkdir -p "$gpu_state_dir"

                  # Initialize state files
                  echo "idle" > "$gpu_state_dir/state"
                  echo "0" > "$gpu_state_dir/workload_pid"
                  echo "0.00" > "$gpu_state_dir/current_bid"
                  echo "$(date +%s)" > "$gpu_state_dir/last_auction"
              done

              log_info "Initialized per-GPU state for $gpu_count GPUs"
          }

          # ============================================================================
          # LOGGING FUNCTIONS
          # ============================================================================
          log() {
              local level="''${1:-INFO}"
              shift
              local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
              echo "$msg" | tee -a "$LOG_FILE" >&2
          }

          log_debug() { log "DEBUG" "$@"; }
          log_info() { log "INFO" "$@"; }
          log_warn() { log "WARN" "$@"; }
          log_error() { log "ERROR" "$@"; }
          log_auction() { log "AUCTION" "$@" >&2; }

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
              local auction_count=$(cat "$STATE_DIR/auction_count" 2>/dev/null || echo 0)

              # Get GPU memory metrics
              local gpu_mem_free=$(gpu_memory_available)
              local gpu_mem_total=$(gpu_memory_total)
              local gpu_mem_util=$(gpu_utilization)

              # Write Prometheus metrics file
              {
                  echo "# HELP compute_market_auction_winner The current auction winner"
                  echo "# TYPE compute_market_auction_winner gauge"
                  echo "compute_market_auction_winner{winner=\"''${winner}\"} 1"
                  echo ""
                  echo "# HELP compute_market_winning_bid_usd The winning bid amount in USD"
                  echo "# TYPE compute_market_winning_bid_usd gauge"
                  echo "compute_market_winning_bid_usd ''${winning_bid}"
                  echo ""
                  echo "# HELP compute_market_bid_current Current bid by bidder type"
                  echo "# TYPE compute_market_bid_current gauge"
                  echo "compute_market_bid_current{bidder=\"mining\"} ''${mining_bid}"
                  echo "compute_market_bid_current{bidder=\"kubernetes\"} ''${k8s_bid}"
                  echo "compute_market_bid_current{bidder=\"akash\"} ''${akash_bid}"
                  echo "compute_market_bid_current{bidder=\"gaming\"} 999.99"
                  echo ""
                  echo "# HELP compute_market_gaming_active Whether gaming is currently active"
                  echo "# TYPE compute_market_gaming_active gauge"
                  echo "compute_market_gaming_active ''${gaming_active}"
                  echo ""
                  echo "# HELP compute_market_auction_total Total auctions run"
                  echo "# TYPE compute_market_auction_total counter"
                  echo "compute_market_auction_total ''${auction_count}"
                  echo ""
                  echo "# HELP compute_market_gpu_memory_free_mb GPU memory free in MB"
                  echo "# TYPE compute_market_gpu_memory_free_mb gauge"
                  echo "compute_market_gpu_memory_free_mb ''${gpu_mem_free}"
                  echo ""
                  echo "# HELP compute_market_gpu_memory_total_mb Total GPU memory in MB"
                  echo "# TYPE compute_market_gpu_memory_total_mb gauge"
                  echo "compute_market_gpu_memory_total_mb ''${gpu_mem_total}"
                  echo ""
                  echo "# HELP compute_market_gpu_utilization GPU memory utilization ratio (0-1)"
                  echo "# TYPE compute_market_gpu_utilization gauge"
                  echo "compute_market_gpu_utilization ''${gpu_mem_util}"
              } > "$STATE_DIR/metrics.prom"
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

              # Get GPU pods on this node (NVIDIA and AMD)
              # NVIDIA GPUs: nvidia.com/gpu resource
              local nvidia_pods=$(kubectl get pods --all-namespaces \
                  --field-selector=spec.nodeName="$hostname" \
                  -o jsonpath='{range .items[?(@.spec.containers[*].resources.limits.nvidia\\.com/gpu)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
                  2>/dev/null || echo "")

              # AMD GPUs: amd.com/gpu resource
              local amd_pods=$(kubectl get pods --all-namespaces \
                  --field-selector=spec.nodeName="$hostname" \
                  -o jsonpath='{range .items[?(@.spec.containers[*].resources.limits.amd\\.com/gpu)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
                  2>/dev/null || echo "")

              # Combine both lists
              local gpu_pods="$([ -n "$nvidia_pods" ] && echo "$nvidia_pods")$([ -n "$amd_pods" ] && echo "$amd_pods")"

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

          # ============================================================================
          # DYNAMIC PRICING FUNCTIONS
          # ============================================================================
          # Time-based pricing adjustments
          get_time_multiplier() {
              local hour=$(date +%H)
              local multiplier=1.0

              # Night (00-06): 10% discount (low demand)
              if [ "$hour" -ge 0 ] && [ "$hour" -lt 6 ]; then
                  multiplier=0.9
              # Morning (06-12): Standard rate
              elif [ "$hour" -ge 6 ] && [ "$hour" -lt 12 ]; then
                  multiplier=1.0
              # Afternoon (12-18): 20% premium (high demand)
              elif [ "$hour" -ge 12 ] && [ "$hour" -lt 18 ]; then
                  multiplier=1.2
              # Evening (18-24): 10% premium (moderate demand)
              else
                  multiplier=1.1
              fi

              echo "$multiplier"
          }

          # Demand-based pricing adjustments
          get_demand_multiplier() {
              local gpu_util=$1
              local multiplier=1.0

              # Low utilization: Bid 15% less to attract workloads
              if (( $(echo "$gpu_util < 0.3" | bc -l) )); then
                  multiplier=0.85
              # High utilization: Bid 15% more (scarcity pricing)
              elif (( $(echo "$gpu_util > 0.7" | bc -l) )); then
                  multiplier=1.15
              # Medium utilization: Standard rate
              else
                  multiplier=1.0
              fi

              echo "$multiplier"
          }

          # Detect workload type from lease attributes
          detect_workload_type() {
              local lease_name=$1

              # Check for workload indicators in lease name or labels
              if echo "$lease_name" | grep -qiE "(llm|inference|language|model)"; then
                  echo "ai/inference"
              elif echo "$lease_name" | grep -qiE "(training|ml|machine-learn|neural)"; then
                  echo "ai/training"
              elif echo "$lease_name" | grep -qiE "(video|transcod|ffmpeg|encode)"; then
                  echo "video/transcoding"
              elif echo "$lease_name" | grep -qiE "(render|blender|cycles|3d)"; then
                  echo "rendering/gpu"
              elif echo "$lease_name" | grep -qiE "(postgres|mongodb|redis|neo4j|mysql|database)"; then
                  echo "database"
              elif echo "$lease_name" | grep -qiE "(jupyter|vscode|ide|dev|workspace)"; then
                  echo "development/workspace"
              elif echo "$lease_name" | grep -qiE "(cicd|runner|pipeline|build|docker)"; then
                  echo "cicd/runner"
              else
                  echo "default"
              fi
          }

          # Workload-specific pricing
          get_workload_multiplier() {
              local workload=$1
              local multiplier=1.0

              case "$workload" in
                  "ai/inference")
                      multiplier=1.3  # LLM inference: 30% premium
                      ;;
                  "ai/training")
                      multiplier=1.2  # ML training: 20% premium
                      ;;
                  "video/transcoding")
                      multiplier=1.25  # Video: 25% premium
                      ;;
                  "rendering/gpu")
                      multiplier=1.2  # Rendering: 20% premium
                      ;;
                  "development/workspace")
                      multiplier=1.1  # Dev workloads: 10% premium
                      ;;
                  "cicd/runner")
                      multiplier=1.15  # CI/CD: 15% premium
                      ;;
                  "database")
                      multiplier=1.0  # Databases: standard
                      ;;
                  *)
                      multiplier=1.0  # Default: standard
                      ;;
              esac

              echo "$multiplier"
          }

          # ============================================================================
          # GPU MEMORY TRACKING
          # ============================================================================
          gpu_memory_available() {
              # Get free GPU memory in MB using nvidia-smi
              if command -v nvidia-smi >/dev/null 2>&1; then
                  nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | \
                      awk '{s+=$1} END {print s}'
              else
                  # Fallback: assume 24GB free if nvidia-smi not available
                  echo "24000"
              fi
          }

          gpu_memory_total() {
              # Get total GPU memory in MB
              if command -v nvidia-smi >/dev/null 2>&1; then
                  nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | \
                      awk '{s+=$1} END {print s}'
              else
                  # Fallback: assume 24GB total
                  echo "24000"
              fi
          }

          gpu_utilization() {
              # Get GPU memory utilization (0.0 to 1.0)
              local mem_free=$(gpu_memory_available)
              local mem_total=$(gpu_memory_total)

              if [ "$mem_total" -gt 0 ]; then
                  echo "scale=4; ($mem_total - $mem_free) / $mem_total" | bc
              else
                  echo "0.5"  # Assume 50% if can't determine
              fi
          }

          # Akash Bidder - Returns market rate for active leases OR potential market rate
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

              # If we have active leases, calculate actual revenue with workload-specific pricing
              if [ -n "$active_leases" ]; then
                  local total_bid=0
                  while IFS= read -r lease; do
                      [ -z "$lease" ] && continue

                      # Detect workload type from lease name
                      local workload=$(detect_workload_type "$lease")
                      local workload_mult=$(get_workload_multiplier "$workload")

                      # Get lease price (in uakt per block)
                      local price=$(kubectl get lease "$lease" -n "$AKASH_NAMESPACE" \
                          -o jsonpath='{.spec.price}' 2>/dev/null || echo "0")

                      # Convert to USD/hour (1 AKT ≈ $0.50, blocks ≈ 6s)
                      # uakt/block * AKT_price * (3600 / 6) / 1_000_000
                      local usd_hourly=$(echo "scale=4; $price * 0.50 * 600 / 1000000" | bc)

                      # Apply workload-specific pricing
                      local adjusted_bid=$(echo "scale=4; $usd_hourly * $workload_mult" | bc)

                      log_debug "Lease $lease ($workload): \$$usd_hourly/hr × $workload_mult x = \$$adjusted_bid/hr"

                      # Apply profit margin
                      local our_bid=$(echo "$adjusted_bid * $AKASH_MARGIN" | bc)

                      total_bid=$(echo "$total_bid + $our_bid" | bc)
                  done <<< "$active_leases"

                  echo "$total_bid"
                  return
              fi

              # No active leases - bid based on POTENTIAL market rate with DYNAMIC PRICING
              # Get current GPU utilization
              local gpu_util=$(gpu_utilization)

              # Base bid: $0.05/hr for RTX 3060 Ti
              local base_bid=0.05

              # Apply dynamic pricing adjustments
              local time_mult=$(get_time_multiplier)
              local demand_mult=$(get_demand_multiplier "$gpu_util")
              local workload_mult=1.0  # Default workload (no active lease)

              # Calculate dynamic bid with all multipliers
              local dynamic_bid=$(echo "scale=4; $base_bid * $time_mult * $demand_mult * $workload_mult" | bc)

              log_debug "Dynamic pricing: base=\$$base_bid time=$time_mult x demand=$demand_mult x → \$$dynamic_bid/hr"

              # Apply profit margin
              local our_bid=$(echo "scale=4; $dynamic_bid * $AKASH_MARGIN" | bc)

              echo "$our_bid"
          }

          # Gaming Bidder - Priority override (uses GameMode signals)
          check_gaming() {
              # Return false if gaming disabled
              if [ "$GAMING_ENABLE" != "true" ]; then
                  echo "false"
                  return
              fi

              # PRIMARY: Use GameMode signal if available (RECOMMENDED)
              if command -v gamemoded >/dev/null 2>&1; then
                  # Query GameMode status (0 = gaming, 1 = not gaming)
                  if gamemoded -s >/dev/null 2>&1; then
                      log_debug "Gaming detected via GameMode signal"
                      echo "true"
                      return
                  fi
                  echo "false"
                  return
              fi

              # FALLBACK: Use whitelist if GameMode not available
              if [ -z "$GAMING_GAMES" ]; then
                  log_debug "No GameMode and no whitelist configured - gaming disabled"
                  echo "false"
                  return
              fi

              # Check for specific game executables (whitelist approach)
              for game_pattern in $GAMING_GAMES; do
                  if pgrep -x "$game_pattern" >/dev/null 2>&1; then
                      log_debug "Gaming detected: process matching '$game_pattern'"
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
              local host=$(hostname)
              for service in $MINING_SERVICES; do
                  # Skip stopping lolminer on hosts other than nexus (no heat issues)
                  if [[ "$service" =~ lolminer ]] && [ "$host" != "nexus" ]; then
                      log_info "Skipping $service on $host (allowed to mine during gaming/builds)"
                      continue
                  fi

                  if systemctl is-active --quiet "$service"; then
                      log_info "Pausing $service (stopping)"
                      systemctl stop "$service" --runtime
                      echo "$service" >> "$STATE_DIR/paused_services"
                  fi
              done
          }

          resume_mining() {
              # Read paused services and resume them
              if [ -f "$STATE_DIR/paused_services" ]; then
                  while IFS= read -r service; do
                      [ -z "$service" ] && continue
                      log_info "Resuming $service (starting)"
                      systemctl start "$service"
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
          # MARKET INTELLIGENCE MODULE
          # ============================================================================
          # Analyze Akash market for competitive pricing
          analyze_market() {
              log_debug "Analyzing Akash market pricing..."

              # Query Akash API for recent active leases with GPU resources
              # Note: This is a simplified implementation. In production, you'd want more robust error handling.
              local api_url="https://api.akash.network/api/v1/leases"

              # Try to fetch recent lease data (with timeout)
              local market_data=$(curl -s --max-time 10 "$api_url" 2>/dev/null || echo "")

              if [ -z "$market_data" ]; then
                  log_debug "Market API unavailable, using cached data"
                  # Return cached percentiles if available
                  if [ -f "$STATE_DIR/market_p50" ]; then
                      cat "$STATE_DIR/market_p50"
                  else
                      echo "0.05"  # Fallback default
                  fi
                  return
              fi

              # Parse lease prices from API response (uakt per block)
              # Extract prices for GPU leases and convert to USD/hour
              local prices=$(echo "$market_data" | jq -r '.[] | select(.resources.gpu > 0) | .price' 2>/dev/null || echo "")

              if [ -z "$prices" ]; then
                  log_debug "No GPU lease data available"
                  echo "0.05"
                  return
              fi

              # Calculate percentiles from price data
              local price_count=$(echo "$prices" | wc -l)
              local p25=$(echo "$prices" | sort -n | awk "NR==$price_count/4" | head -1)
              local p50=$(echo "$prices" | sort -n | awk "NR==$price_count/2" | head -1)
              local p75=$(echo "$prices" | sort -n | awk "NR==$price_count*3/4" | head -1)

              # Convert uakt to USD/hour (1 AKT ≈ $0.50, 600 blocks/hour)
              # uakt/block * 0.50 * 600 / 1_000_000
              local p25_usd=$(echo "scale=4; $p25 * 0.50 * 600 / 1000000" | bc)
              local p50_usd=$(echo "scale=4; $p50 * 0.50 * 600 / 1000000" | bc)
              local p75_usd=$(echo "scale=4; $p75 * 0.50 * 600 / 1000000" | bc)

              # Store percentiles for bidding decisions
              echo "$p25_usd" > "$STATE_DIR/market_p25"
              echo "$p50_usd" > "$STATE_DIR/market_p50"
              echo "$p75_usd" > "$STATE_DIR/market_p75"

              log_info "Market analysis: P25=\$$p25_usd/hr P50=\$$p50_usd/hr P75=\$$p75_usd/hr (from $price_count leases)"

              # Return median price for reference
              echo "$p50_usd"
          }

          # Market monitoring loop (runs in background)
          start_market_monitor() {
              log_info "Starting market intelligence monitor (5-minute intervals)"

              while true; do
                  analyze_market
                  sleep 300  # 5 minutes
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

              # Start market intelligence monitor
              start_market_monitor

              # Main auction loop
              while true; do
                  run_auction
                  sleep "$AUCTION_INTERVAL"
              done
          }

          # Run main function
          main "$@"
        ''}/bin/compute-market-engine";
      };
    };

    # ============================================================================
    # PROMETHEUS SCRAPE CONFIG
    # ============================================================================
    services.prometheus.scrapeConfigs = lib.mkIf config.services.compute-market.prometheus.enable [
      {
        job_name = "compute-market";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString config.services.compute-market.prometheus.port}"];
          }
        ];
      }
    ];
  };
}
