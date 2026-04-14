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

    bidders.gaming = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable gaming as priority override (always wins)";
      };

      processes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
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
    environment.systemPackages = with pkgs; [
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

    systemd.tmpfiles.rules = [
      "d ${config.services.compute-market.stateDirectory} 0755 root root -"
      "d ${config.services.compute-market.stateDirectory}/bidders 0755 root root -"
    ];

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

          set -euo pipefail

          STATE_DIR="''${STATE_DIR:-/run/compute-market}"
          LOG_FILE="''${LOG_FILE:-/var/log/compute-market.log}"
          AUCTION_INTERVAL=''${AUCTION_INTERVAL:-30}
          PROMETHEUS_PORT=''${PROMETHEUS_PORT:-9200}

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
          GAMING_GAMES="''${GAMING_GAMES:-}"

          list_available_gpus() {
              if command -v nvidia-smi >/dev/null 2>&1; then
                  nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null || echo "0"
              else
                  echo "0"
              fi
          }

          ============================================================================
          init_per_gpu_state() {
              local gpu_count=$(list_available_gpus | wc -l)

              for ((gpu_id=0; gpu_id<gpu_count; gpu_id++)); do
                  local gpu_state_dir="$STATE_DIR/gpu$gpu_id"
                  mkdir -p "$gpu_state_dir"

                  echo "idle" > "$gpu_state_dir/state"
                  echo "0" > "$gpu_state_dir/workload_pid"
                  echo "0.00" > "$gpu_state_dir/current_bid"
                  echo "$(date +%s)" > "$gpu_state_dir/last_auction"
              done

              log_info "Initialized per-GPU state for $gpu_count GPUs"
          }

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

          update_metrics() {
              local winner=''${1:-none}
              local winning_bid=''${2:-0}
              local mining_bid=''${3:-0}
              local k8s_bid=''${4:-0}
              local akash_bid=''${5:-0}
              local gaming_active=''${6:-false}
              local auction_count=$(cat "$STATE_DIR/auction_count" 2>/dev/null || echo 0)

              local gpu_mem_free=$(gpu_memory_available)
              local gpu_mem_total=$(gpu_memory_total)
              local gpu_mem_util=$(gpu_utilization)

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


          bid_mining() {
              if [ "$MINING_ENABLE" != "true" ]; then
                  echo 0
                  return
              fi

              for service in $MINING_SERVICES; do
                  if systemctl is-active --quiet "$service"; then
                      echo "$MINING_HOURLY"
                      return
                  fi
              done

              echo "$MINING_HOURLY"
          }

          bid_kubernetes() {
              if [ "$K8S_ENABLE" != "true" ]; then
                  echo 0
                  return
              fi

              if ! command -v kubectl >/dev/null 2>&1; then
                  log_debug "kubectl not available"
                  echo 0
                  return
              fi

              if ! kubectl get nodes >/dev/null 2>&1; then
                  log_debug "Kubernetes cluster not accessible"
                  echo 0
                  return
              fi

              local hostname=$(hostname)
              local total_bid=0

              local nvidia_pods=$(kubectl get pods --all-namespaces \
                  --field-selector=spec.nodeName="$hostname" \
                  -o jsonpath='{range .items[?(@.spec.containers[*].resources.limits.nvidia\\.com/gpu)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
                  2>/dev/null || echo "")

              local amd_pods=$(kubectl get pods --all-namespaces \
                  --field-selector=spec.nodeName="$hostname" \
                  -o jsonpath='{range .items[?(@.spec.containers[*].resources.limits.amd\\.com/gpu)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
                  2>/dev/null || echo "")

              local gpu_pods="$([ -n "$nvidia_pods" ] && echo "$nvidia_pods")$([ -n "$amd_pods" ] && echo "$amd_pods")"

              if [ -z "$gpu_pods" ]; then
                  echo 0
                  return
              fi

              while IFS= read -r pod; do
                  [ -z "$pod" ] && continue
                  local namespace=$(echo "$pod" | cut -d'/' -f1)
                  local name=$(echo "$pod" | cut -d'/' -f2)

                  if kubectl get pod "$name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; then
                      local priority_class=$(kubectl get pod "$name" -n "$namespace" \
                          -o jsonpath='{.spec.priorityClassName}' 2>/dev/null || echo "")

                      local bid=$K8S_BASE_BID

                      if [[ "$priority_class" =~ (high|urgent|critical) ]]; then
                          bid=$(echo "$bid * $K8S_URGENCY_MULT" | bc)
                      fi

                      total_bid=$(echo "$total_bid + $bid" | bc)
                  fi
              done <<< "$gpu_pods"

              echo "$total_bid"
          }

          get_time_multiplier() {
              local hour=$(date +%H)
              local multiplier=1.0

              if [ "$hour" -ge 0 ] && [ "$hour" -lt 6 ]; then
                  multiplier=0.9
              elif [ "$hour" -ge 6 ] && [ "$hour" -lt 12 ]; then
                  multiplier=1.0
              elif [ "$hour" -ge 12 ] && [ "$hour" -lt 18 ]; then
                  multiplier=1.2
              else
                  multiplier=1.1
              fi

              echo "$multiplier"
          }

          get_demand_multiplier() {
              local gpu_util=$1
              local multiplier=1.0

              if (( $(echo "$gpu_util < 0.3" | bc -l) )); then
                  multiplier=0.85
              elif (( $(echo "$gpu_util > 0.7" | bc -l) )); then
                  multiplier=1.15
              else
                  multiplier=1.0
              fi

              echo "$multiplier"
          }

          detect_workload_type() {
              local lease_name=$1

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

          get_workload_multiplier() {
              local workload=$1
              local multiplier=1.0

              case "$workload" in
                  "ai/inference")
                      multiplier=1.3
                      ;;
                  "ai/training")
                      multiplier=1.2
                      ;;
                  "video/transcoding")
                      multiplier=1.25
                      ;;
                  "rendering/gpu")
                      multiplier=1.2
                      ;;
                  "development/workspace")
                      multiplier=1.1
                      ;;
                  "cicd/runner")
                      multiplier=1.15
                      ;;
                  "database")
                      multiplier=1.0
                      ;;
                  *)
                      multiplier=1.0
                      ;;
              esac

              echo "$multiplier"
          }

          gpu_memory_available() {
              if command -v nvidia-smi >/dev/null 2>&1; then
                  nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | \
                      awk '{s+=$1} END {print s}'
              else
                  echo "24000"
              fi
          }

          gpu_memory_total() {
              if command -v nvidia-smi >/dev/null 2>&1; then
                  nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | \
                      awk '{s+=$1} END {print s}'
              else
                  echo "24000"
              fi
          }

          gpu_utilization() {
              local mem_free=$(gpu_memory_available)
              local mem_total=$(gpu_memory_total)

              if [ "$mem_total" -gt 0 ]; then
                  echo "scale=4; ($mem_total - $mem_free) / $mem_total" | bc
              else
                  echo "0.5"
              fi
          }

          bid_akash() {
              if [ "$AKASH_ENABLE" != "true" ]; then
                  echo 0
                  return
              fi

              if ! kubectl get pods -n "$AKASH_NAMESPACE" -l app=akash-provider >/dev/null 2>&1; then
                  echo 0
                  return
              fi

              local hostname=$(hostname)
              local active_leases=$(kubectl get leases -n "$AKASH_NAMESPACE" \
                  -o jsonpath='{range .items[?(@.status.currentState == "active")]}{.metadata.name}{"\n"}{end}' \
                  2>/dev/null || echo "")

              if [ -n "$active_leases" ]; then
                  local total_bid=0
                  while IFS= read -r lease; do
                      [ -z "$lease" ] && continue

                      local workload=$(detect_workload_type "$lease")
                      local workload_mult=$(get_workload_multiplier "$workload")

                      local price=$(kubectl get lease "$lease" -n "$AKASH_NAMESPACE" \
                          -o jsonpath='{.spec.price}' 2>/dev/null || echo "0")

                      local usd_hourly=$(echo "scale=4; $price * 0.50 * 600 / 1000000" | bc)

                      local adjusted_bid=$(echo "scale=4; $usd_hourly * $workload_mult" | bc)

                      log_debug "Lease $lease ($workload): \$$usd_hourly/hr × $workload_mult x = \$$adjusted_bid/hr"

                      local our_bid=$(echo "$adjusted_bid * $AKASH_MARGIN" | bc)

                      total_bid=$(echo "$total_bid + $our_bid" | bc)
                  done <<< "$active_leases"

                  echo "$total_bid"
                  return
              fi

              local gpu_util=$(gpu_utilization)

              local base_bid=0.05

              local time_mult=$(get_time_multiplier)
              local demand_mult=$(get_demand_multiplier "$gpu_util")
              local workload_mult=1.0

              local dynamic_bid=$(echo "scale=4; $base_bid * $time_mult * $demand_mult * $workload_mult" | bc)

              log_debug "Dynamic pricing: base=\$$base_bid time=$time_mult x demand=$demand_mult x → \$$dynamic_bid/hr"

              local our_bid=$(echo "scale=4; $dynamic_bid * $AKASH_MARGIN" | bc)

              echo "$our_bid"
          }

          check_gaming() {
              if [ "$GAMING_ENABLE" != "true" ]; then
                  echo "false"
                  return
              fi

              if command -v gamemoded >/dev/null 2>&1; then
                  if gamemoded -s >/dev/null 2>&1; then
                      log_debug "Gaming detected via GameMode signal"
                      echo "true"
                      return
                  fi
                  echo "false"
                  return
              fi

              if [ -z "$GAMING_GAMES" ]; then
                  log_debug "No GameMode and no whitelist configured - gaming disabled"
                  echo "false"
                  return
              fi

              for game_pattern in $GAMING_GAMES; do
                  if pgrep -x "$game_pattern" >/dev/null 2>&1; then
                      log_debug "Gaming detected: process matching '$game_pattern'"
                      echo "true"
                      return
                  fi
              done

              echo "false"
          }

          run_auction() {
              local count=$(($(cat "$STATE_DIR/auction_count" 2>/dev/null || echo 0) + 1))
              echo "$count" > "$STATE_DIR/auction_count"

              local current_winner=$(cat "$STATE_DIR/current_winner" 2>/dev/null || echo "none")
              local gaming_active=$(check_gaming)

              if [ "$gaming_active" = "true" ]; then
                  log_auction "GAMING OVERRIDE - Gaming detected, pausing all GPU workloads"
                  update_metrics "gaming" 999.99 0 0 0 "true"
                  echo "gaming" > "$STATE_DIR/current_winner"
                  apply_gaming_profile
                  return
              fi

              local mining_bid=$(bid_mining)
              local k8s_bid=$(bid_kubernetes)
              local akash_bid=$(bid_akash)

              log_auction "Auction #$count - Mining: \$$mining_bid/hr | K8s: \$$k8s_bid/hr | Akash: \$$akash_bid/hr"

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

              if [ "$winner" != "$current_winner" ]; then
                  log_auction "WINNER CHANGED: $current_winner → $winner (\$$winning_bid/hr)"
                  echo "$winner" > "$STATE_DIR/current_winner"
                  apply_winner_profile "$winner"
              else
                  log_debug "Winner unchanged: $winner (\$$winning_bid/hr)"
              fi

              update_metrics "$winner" "$winning_bid" "$mining_bid" "$k8s_bid" "$akash_bid" "false"
          }

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
              if [ -f "$STATE_DIR/paused_services" ]; then
                  while IFS= read -r service; do
                      [ -z "$service" ] && continue
                      log_info "Resuming $service (starting)"
                      systemctl start "$service"
                  done < "$STATE_DIR/paused_services"
                  rm -f "$STATE_DIR/paused_services"
              fi
          }

          start_metrics_server() {
              while true; do
                  {
                      echo "HTTP/1.1 200 OK"
                      echo "Content-Type: text/plain"
                      echo ""
                      cat "$STATE_DIR/metrics.prom" 2>/dev/null || echo "# No metrics yet"
                  } | nc -l -p "$PROMETHEUS_PORT" > /dev/null 2>&1 || true
              done &
          }

          analyze_market() {
              log_debug "Analyzing Akash market pricing..."

              local api_url="https://api.akash.network/api/v1/leases"

              local market_data=$(curl -s --max-time 10 "$api_url" 2>/dev/null || echo "")

              if [ -z "$market_data" ]; then
                  log_debug "Market API unavailable, using cached data"
                  if [ -f "$STATE_DIR/market_p50" ]; then
                      cat "$STATE_DIR/market_p50"
                  else
                      echo "0.05"
                  fi
                  return
              fi

              local prices=$(echo "$market_data" | jq -r '.[] | select(.resources.gpu > 0) | .price' 2>/dev/null || echo "")

              if [ -z "$prices" ]; then
                  log_debug "No GPU lease data available"
                  echo "0.05"
                  return
              fi

              local price_count=$(echo "$prices" | wc -l)
              local p25=$(echo "$prices" | sort -n | awk "NR==$price_count/4" | head -1)
              local p50=$(echo "$prices" | sort -n | awk "NR==$price_count/2" | head -1)
              local p75=$(echo "$prices" | sort -n | awk "NR==$price_count*3/4" | head -1)

              local p25_usd=$(echo "scale=4; $p25 * 0.50 * 600 / 1000000" | bc)
              local p50_usd=$(echo "scale=4; $p50 * 0.50 * 600 / 1000000" | bc)
              local p75_usd=$(echo "scale=4; $p75 * 0.50 * 600 / 1000000" | bc)

              echo "$p25_usd" > "$STATE_DIR/market_p25"
              echo "$p50_usd" > "$STATE_DIR/market_p50"
              echo "$p75_usd" > "$STATE_DIR/market_p75"

              log_info "Market analysis: P25=\$$p25_usd/hr P50=\$$p50_usd/hr P75=\$$p75_usd/hr (from $price_count leases)"

              echo "$p50_usd"
          }

          start_market_monitor() {
              log_info "Starting market intelligence monitor (5-minute intervals)"

              while true; do
                  analyze_market
                  sleep 300
              done &
          }

          main() {
              log_info "=== GPU Resource Marketplace Starting ==="
              log_info "State directory: $STATE_DIR"
              log_info "Auction interval: $AUCTION_INTERVAL seconds"

              echo "0" > "$STATE_DIR/auction_count"
              echo "none" > "$STATE_DIR/current_winner"
              update_metrics "none" 0 0 0 0 "false"


              start_market_monitor

              while true; do
                  run_auction
                  sleep "$AUCTION_INTERVAL"
              done
          }

          main "$@"
        ''}/bin/compute-market-engine";
      };
    };

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
