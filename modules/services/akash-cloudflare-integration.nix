# Cloudflare Integration for Akash Provider
# Automates DNS, cache management, metrics, and monitoring for Akash Network deployments
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.akash-cloudflare-integration;
  inherit (lib) mkEnableOption mkOption types mkIf mkOptionDefault optional optionalString concatMapStrings concatStringsSep strings;
in {
  options.services.akash-cloudflare-integration = {
    enable = mkEnableOption "Cloudflare integration for Akash Provider (all features)";

    # Global configuration
    domain = mkOption {
      type = types.str;
      example = "reverb256.ca";
      description = "Base domain for DNS records (e.g., reverb256.ca)";
    };

    zoneId = mkOption {
      type = types.str;
      example = "abc123def456";
      description = "Cloudflare Zone ID (retrieved from API or dashboard)";
    };

    tokenFile = mkOption {
      type = types.path;
      default = "/run/agenix/cloudflare-api-token";
      description = "Path to Cloudflare API token (Dns:Edit, Zone:Read, Zone:Cache:Purge)";
    };

    providerEndpoint = mkOption {
      type = types.str;
      default = "http://10.1.1.120:30843";
      description = "Akash provider HTTP endpoint (NodePort on Nexus)";
    };

    providerGrpcEndpoint = mkOption {
      type = types.str;
      default = "10.1.1.120:30844";
      description = "Akash provider gRPC endpoint (NodePort on Nexus)";
    };

    ingressDomain = mkOption {
      type = types.str;
      default = "ingress.reverb256.ca";
      description = "Ingress domain pattern for tenant deployments";
    };

    # Feature 1: Automated Tenant DNS Setup
    dnsWatcher = {
      enable = mkEnableOption "Automated tenant DNS setup for Akash deployments";

      pollInterval = mkOption {
        type = types.int;
        default = 30;
        description = "Poll interval in seconds for checking new deployments";
      };

      dnsRecordPrefix = mkOption {
        type = types.str;
        default = "dedicated";
        description = "DNS record prefix (e.g., 'dedicated' creates *.dedicated.ingress.reverb256.ca)";
      };
    };

    # Feature 2: Smart Cache Invalidation
    cachePurge = {
      enable = mkEnableOption "Smart cache invalidation for tenant deployments";

      purgeDelay = mkOption {
        type = types.int;
        default = 5;
        description = "Delay in seconds after DNS creation before cache purge";
      };
    };

    # Feature 3: Prometheus Integration
    metricsExporter = {
      enable = mkEnableOption "Cloudflare metrics exporter for Prometheus";

      scrapeInterval = mkOption {
        type = types.int;
        default = 300;
        description = "Metrics scrape interval in seconds (default: 5 minutes)";
      };

      metricsDir = mkOption {
        type = types.str;
        default = "/var/lib/prometheus/node-exporter/textfile-collector";
        description = "Directory for Prometheus metrics files";
      };
    };

    # Feature 4: Health Monitoring Dashboard
    healthDashboard = {
      enable = mkEnableOption "Akash provider health monitoring dashboard";

      updateInterval = mkOption {
        type = types.int;
        default = 30;
        description = "Dashboard update interval in seconds";
      };

      outputDir = mkOption {
        type = types.str;
        default = "/var/www/akash-health";
        description = "Directory for dashboard HTML files";
      };
    };

    # Feature 5: DNS Cleanup Automation
    dnsCleanup = {
      enable = mkEnableOption "Periodic cleanup of stale DNS records";

      gracePeriod = mkOption {
        type = types.int;
        default = 86400;
        description = "Grace period in seconds before deleting stale records (default: 24 hours)";
      };

      cleanupTime = mkOption {
        type = types.str;
        default = "03:00:00";
        description = "Daily cleanup time (systemd calendar format)";
      };
    };

    # Feature 6: Status Page
    statusPage = {
      enable = mkEnableOption "Public Akash provider status page";

      updateInterval = mkOption {
        type = types.int;
        default = 300;
        description = "Status page update interval in seconds (default: 5 minutes)";
      };

      outputDir = mkOption {
        type = types.str;
        default = "/var/www/akash-status";
        description = "Directory for status page HTML files";
      };
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # REQUIRED PACKAGES
    # ============================================================================
    environment.systemPackages = with pkgs; [
      curl
      jq
      gnugrep
      gnused
      coreutils
      kubectl
      cacert
    ];

    # ============================================================================
    # FEATURE 1: AUTOMATED TENANT DNS SETUP
    # ============================================================================
    systemd.services.akash-cloudflare-dns-watcher = mkIf cfg.dnsWatcher.enable {
      description = "Watch Akash deployments for automated DNS setup";
      wantedBy = ["multi-user.target"];
      after = ["kubernetes.target" "agenix-rekey.service"];
      wants = ["network-online.target"];
      path = with pkgs; [curl jq kubectl coreutils gnugrep gnused];

      serviceConfig = {
        Type = "simple";
        User = "root";
        Restart = "always";
        RestartSec = "${toString cfg.dnsWatcher.pollInterval}s";
        StandardOutput = "journal";
        StandardError = "journal";

        # Security hardening (from cloudflared.nix)
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = ["/var/lib/akash-cloudflare" "/var/log"];

        ExecStart = pkgs.writeShellScript "akash-dns-watcher" ''
          #!/bin/sh
          set -euo pipefail

          # Configuration
          CLOUDFLARE_TOKEN_FILE="${cfg.tokenFile}"
          CLOUDFLARE_ZONE_ID="${cfg.zoneId}"
          DOMAIN="${cfg.domain}"
          INGRESS_DOMAIN="${cfg.ingressDomain}"
          DNS_PREFIX="${cfg.dnsWatcher.dnsRecordPrefix}"
          PROVIDER_ENDPOINT="${cfg.providerEndpoint}"
          STATE_DIR="/var/lib/akash-cloudflare"
          PROCESSED_FILE="$STATE_DIR/processed-deployments.txt"

          # Ensure state directory exists
          mkdir -p "$STATE_DIR"
          touch "$PROCESSED_FILE"

          # Helper: Log with timestamp
          log() {
            echo "[$(date -Iseconds)] $*" >&2
          }

          # Helper: Get Cloudflare token
          get_token() {
            if [ ! -f "$CLOUDFLARE_TOKEN_FILE" ]; then
              log "ERROR: Cloudflare token not found at $CLOUDFLARE_TOKEN_FILE"
              exit 1
            fi
            cat "$CLOUDFLARE_TOKEN_FILE"
          }

          # Helper: Get Zone ID from API (fallback if not configured)
          get_zone_id() {
            if [ -n "$CLOUDFLARE_ZONE_ID" ] && [ "$CLOUDFLARE_ZONE_ID" != "abc123def456" ]; then
              echo "$CLOUDFLARE_ZONE_ID"
              return
            fi

            # Fetch Zone ID from domain name
            TOKEN=$(get_token)
            curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
              -H "Authorization: Bearer $TOKEN" \
              -H "Content-Type: application/json" | jq -r '.result[0].id'
          }

          # Helper: Get ingress IP from provider
          get_ingress_ip() {
            # Try provider status endpoint
            INGRESS_IP=$(curl -s "$PROVIDER_ENDPOINT" | jq -r '.ingress_ip // .ip // empty' || echo "")

            if [ -n "$INGRESS_IP" ] && [ "$INGRESS_IP" != "null" ]; then
              echo "$INGRESS_IP"
              return
            fi

            # Fallback: Get first worker node IP
            kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "10.1.1.120"
          }

          # Helper: Create DNS record
          create_dns_record() {
            local tenant_name="$1"
            local ingress_ip="$2"
            local dns_name="$tenant_name.$DNS_PREFIX.$INGRESS_DOMAIN"
            local token=$(get_token)
            local zone_id=$(get_zone_id)

            log "Creating DNS record: $dns_name -> $ingress_ip"

            # Check if record already exists
            existing=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$dns_name&type=A" \
              -H "Authorization: Bearer $token" \
              -H "Content-Type: application/json")

            record_id=$(echo "$existing" | jq -r '.result[0].id // empty')

            if [ -n "$record_id" ] && [ "$record_id" != "null" ]; then
              log "DNS record already exists (ID: $record_id), updating IP"
              curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"A\",\"name\":\"$dns_name\",\"content\":\"$ingress_ip\",\"ttl\":120,\"proxied\":false}" | jq -r '.success'
            else
              # Create new record
              result=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"A\",\"name\":\"$dns_name\",\"content\":\"$ingress_ip\",\"ttl\":120,\"proxied\":false}")

              success=$(echo "$result" | jq -r '.success')
              if [ "$success" = "true" ]; then
                log "DNS record created successfully"
                echo "$tenant_name" >> "$PROCESSED_FILE"
              else
                log "ERROR: Failed to create DNS record: $(echo "$result" | jq -r '.errors[0].message')"
              fi
            fi
          }

          # Helper: Extract tenant name from deployment
          extract_tenant_name() {
            local deployment="$1"

            # Try akash.network/owner label
            owner=$(echo "$deployment" | jq -r '.metadata.labels."akash.network/owner" // empty')
            if [ -n "$owner" ]; then
              echo "$owner" | sed 's/^[a-z]*1//' | head -c 12
              return
            fi

            # Try deployment name
            name=$(echo "$deployment" | jq -r '.metadata.name // empty')
            if [ -n "$name" ]; then
              echo "$name" | sed 's/-deployment//' | head -c 20
              return
            fi

            # Fallback: generate from UID
            uid=$(echo "$deployment" | jq -r '.metadata.uid // empty')
            echo "$uid" | head -c 12
          }

          # Main watch loop
          log "Starting DNS watcher for Akash deployments"

          while true; do
            # Get all Akash deployments
            deployments=$(kubectl get deployments -n akash-services -l "akash.network=true" -o json 2>/dev/null || echo "null")

            if [ "$deployments" != "null" ]; then
              deployment_count=$(echo "$deployments" | jq '.items | length')
              log "Found $deployment_count Akash deployments"

              # Process each deployment
              echo "$deployments" | jq -c '.items[]' | while read -r deployment; do
                deployment_name=$(echo "$deployment" | jq -r '.metadata.name')
                deployment_uid=$(echo "$deployment" | jq -r '.metadata.uid')

                # Check if already processed
                if grep -q "^$deployment_uid$" "$PROCESSED_FILE" 2>/dev/null; then
                  continue
                fi

                log "Processing new deployment: $deployment_name"

                # Extract tenant name
                tenant_name=$(extract_tenant_name "$deployment")
                if [ -z "$tenant_name" ]; then
                  log "WARNING: Could not extract tenant name from deployment $deployment_name"
                  continue
                fi

                # Get ingress IP
                ingress_ip=$(get_ingress_ip)
                log "Ingress IP: $ingress_ip"

                # Create DNS record
                if create_dns_record "$tenant_name" "$ingress_ip"; then
                  # Mark as processed
                  echo "$deployment_uid" >> "$PROCESSED_FILE"

                  ${lib.optionalString cfg.cachePurge.enable ''
                  # Trigger cache purge
                  log "Triggering cache purge for $tenant_name"
                  systemctl start akash-cloudflare-cache-purge@"$tenant_name"
                  ''}
                fi
              done
            fi

            sleep ${toString cfg.dnsWatcher.pollInterval}
          done
        '';
      };
    };

    # ============================================================================
    # FEATURE 2: SMART CACHE INVALIDATION
    # ============================================================================
    systemd.services.akash-cloudflare-cache-purge = mkIf cfg.cachePurge.enable {
      description = "Purge Cloudflare cache for tenant deployment";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        path = with pkgs; [curl jq coreutils];

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;

        ExecStart = pkgs.writeShellScript "akash-cache-purge" ''
          #!/bin/sh
          set -euo pipefail

          # Configuration
          CLOUDFLARE_TOKEN_FILE="${cfg.tokenFile}"
          CLOUDFLARE_ZONE_ID="${cfg.zoneId}"
          DOMAIN="${cfg.domain}"
          DNS_PREFIX="${cfg.dnsWatcher.dnsRecordPrefix}"
          INGRESS_DOMAIN="${cfg.ingressDomain}"

          # Get tenant name from systemd instance (passed via @)
          TENANT_NAME="%i"

          # Helper: Get Cloudflare token
          get_token() {
            if [ ! -f "$CLOUDFLARE_TOKEN_FILE" ]; then
              echo "ERROR: Cloudflare token not found at $CLOUDFLARE_TOKEN_FILE" >&2
              exit 1
            fi
            cat "$CLOUDFLARE_TOKEN_FILE"
          }

          # Helper: Get Zone ID from API (fallback if not configured)
          get_zone_id() {
            if [ -n "$CLOUDFLARE_ZONE_ID" ] && [ "$CLOUDFLARE_ZONE_ID" != "abc123def456" ]; then
              echo "$CLOUDFLARE_ZONE_ID"
              return
            fi

            # Fetch Zone ID from domain name
            TOKEN=$(get_token)
            curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
              -H "Authorization: Bearer $TOKEN" \
              -H "Content-Type: application/json" | jq -r '.result[0].id'
          }

          # Build tenant URL
          tenant_url="https://$TENANT_NAME.$DNS_PREFIX.$INGRESS_DOMAIN/*"

          # Get token and zone ID
          token=$(get_token)
          zone_id=$(get_zone_id)

          echo "[$(date -Iseconds)] Purging Cloudflare cache for: $tenant_url"

          # Purge cache using files parameter (targeted purge)
          result=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/purge_cache" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            --data "{\"files\":[\"$tenant_url\"]}")

          success=$(echo "$result" | jq -r '.success')
          if [ "$success" = "true" ]; then
            echo "[$(date -Iseconds)] Cache purged successfully for $TENANT_NAME"
          else
            echo "[$(date -Iseconds)] ERROR: Failed to purge cache: $(echo "$result" | jq -r '.errors[0].message')" >&2
            exit 1
          fi
        '';
      };
    };

    # ============================================================================
    # FEATURE 3: PROMETHEUS INTEGRATION
    # ============================================================================
    systemd.services.akash-cloudflare-metrics = mkIf cfg.metricsExporter.enable {
      description = "Export Cloudflare metrics to Prometheus";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "agenix-rekey.service"];
      path = with pkgs; [curl jq coreutils gnused];

      serviceConfig = {
        Type = "oneshot";
        User = "node-exporter";
        Environment = "METRICS_DIR=${cfg.metricsExporter.metricsDir}";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [cfg.metricsExporter.metricsDir];

        ExecStart = pkgs.writeShellScript "cloudflare-metrics-exporter" ''
          #!/bin/sh
          set -euo pipefail

          # Configuration
          CLOUDFLARE_TOKEN_FILE="${cfg.tokenFile}"
          CLOUDFLARE_ZONE_ID="${cfg.zoneId}"
          DOMAIN="${cfg.domain}"
          OUTPUT_FILE="$METRICS_DIR/cloudflare.prom"
          TEMP_FILE="$OUTPUT_FILE.tmp"

          # Helper: Get Cloudflare token
          get_token() {
            if [ ! -f "$CLOUDFLARE_TOKEN_FILE" ]; then
              echo "ERROR: Cloudflare token not found" >&2
              exit 1
            fi
            cat "$CLOUDFLARE_TOKEN_FILE"
          }

          # Helper: Get Zone ID from API (fallback if not configured)
          get_zone_id() {
            if [ -n "$CLOUDFLARE_ZONE_ID" ] && [ "$CLOUDFLARE_ZONE_ID" != "abc123def456" ]; then
              echo "$CLOUDFLARE_ZONE_ID"
              return
            fi

            # Fetch Zone ID from domain name
            TOKEN=$(get_token)
            curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
              -H "Authorization: Bearer $TOKEN" \
              -H "Content-Type: application/json" | jq -r '.result[0].id'
          }

          # Initialize metrics file
          init_metrics() {
            echo "# HELP cloudflare_requests_total Total requests to Cloudflare zone" > "$TEMP_FILE"
            echo "# TYPE cloudflare_requests_total counter" >> "$TEMP_FILE"
            echo "# HELP cloudflare_bandwidth_bytes_total Total bandwidth served" >> "$TEMP_FILE"
            echo "# TYPE cloudflare_bandwidth_bytes_total counter" >> "$TEMP_FILE"
            echo "# HELP cloudflare_cache_hit_rate Cache hit percentage" >> "$TEMP_FILE"
            echo "# TYPE cloudflare_cache_hit_rate gauge" >> "$TEMP_FILE"
            echo "# HELP cloudflare_threats_total Total threats blocked" >> "$TEMP_FILE"
            echo "# TYPE cloudflare_threats_total counter" >> "$TEMP_FILE"
            echo "# HELP cloudflare_http_errors_total Total HTTP 4xx/5xx errors" >> "$TEMP_FILE"
            echo "# TYPE cloudflare_http_errors_total counter" >> "$TEMP_FILE"
            echo "# HELP cloudflare_dns_records_total Total DNS records" >> "$TEMP_FILE"
            echo "# TYPE cloudflare_dns_records_total gauge" >> "$TEMP_FILE"
          }

          # Fetch analytics from Cloudflare API
          fetch_metrics() {
            local token=$(get_token)
            local zone_id=$(get_zone_id)

            # Get zone analytics (last 24 hours)
            analytics=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/analytics/dashboard?since=-1440" \
              -H "Authorization: Bearer $token" \
              -H "Content-Type: application/json" || echo "null")

            if [ "$analytics" != "null" ]; then
              # Extract metrics (with fallback to 0 if missing)
              requests=$(echo "$analytics" | jq -r '.result.total.requests // .result.requests // 0')
              bandwidth=$(echo "$analytics" | jq -r '.result.total.bandwidth // .result.bandwidth // 0')
              cache_hit_rate=$(echo "$analytics" | jq -r '.result.requests_cache.cache_hit_rate // .result.cache.hit_rate // 0')
              threats=$(echo "$analytics" | jq -r '.total.threats // .result.threats // 0')
              http_errors=$(echo "$analytics" | jq -r '.result.total.http_errors // .result.errors // 0')

              echo "cloudflare_requests_total $requests" >> "$TEMP_FILE"
              echo "cloudflare_bandwidth_bytes_total $bandwidth" >> "$TEMP_FILE"
              echo "cloudflare_cache_hit_rate $cache_hit_rate" >> "$TEMP_FILE"
              echo "cloudflare_threats_total $threats" >> "$TEMP_FILE"
              echo "cloudflare_http_errors_total $http_errors" >> "$TEMP_FILE"
            fi

            # Get DNS record count
            dns_records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
              -H "Authorization: Bearer $token" \
              -H "Content-Type: application/json" | jq '.result_info.total_count // 0')

            echo "cloudflare_dns_records_total $dns_records" >> "$TEMP_FILE"

            # Add scrape timestamp
            echo "cloudflare_scrape_timestamp $(date +%s)" >> "$TEMP_FILE"
          }

          # Main execution
          init_metrics
          fetch_metrics

          # Atomic move to final location
          mv "$TEMP_FILE" "$OUTPUT_FILE"
        '';
      };
    };

    systemd.timers.akash-cloudflare-metrics = mkIf cfg.metricsExporter.enable {
      description = "Cloudflare metrics exporter timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "${toString cfg.metricsExporter.scrapeInterval}s";
      };
    };

    # ============================================================================
    # FEATURE 4: HEALTH MONITORING DASHBOARD
    # ============================================================================
    systemd.services.akash-health-dashboard = mkIf cfg.healthDashboard.enable {
      description = "Generate Akash provider health dashboard";
      wantedBy = ["multi-user.target"];
      after = ["kubernetes.target"];
      path = with pkgs; [curl jq kubectl coreutils];

      serviceConfig = {
        Type = "oneshot";
        User = "nginx";
        Group = "nginx";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [cfg.healthDashboard.outputDir];

        ExecStart = pkgs.writeShellScript "akash-health-dashboard" ''
          #!/bin/sh
          set -euo pipefail

          # Configuration
          PROVIDER_ENDPOINT="${cfg.providerEndpoint}"
          OUTPUT_DIR="${cfg.healthDashboard.outputDir}"
          OUTPUT_FILE="$OUTPUT_DIR/index.html"
          TEMP_FILE="$OUTPUT_FILE.tmp"

          # Ensure output directory exists
          mkdir -p "$OUTPUT_DIR"

          # Fetch provider status
          provider_status=$(curl -s "$PROVIDER_ENDPOINT" 2>/dev/null || echo '{"status":"error"}')

          # Get cluster stats
          deployment_count=$(kubectl get deployments -n akash-services -l "akash.network=true" --no-headers 2>/dev/null | wc -l || echo "0")
          pod_count=$(kubectl get pods -n akash-services --no-headers 2>/dev/null | wc -l || echo "0")
          node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")

          # Extract provider info
          provider_status_text=$(echo "$provider_status" | jq -r '.status // "Unknown"')
          active_leases=$(echo "$provider_status" | jq -r '.active_leases // 0')
          available_capacity=$(echo "$provider_status" | jq -r '.available_capacity // 0')

          # Get timestamp
          timestamp=$(date -Iseconds)

          # Generate HTML dashboard
          cat > "$TEMP_FILE" <<'EOF'
          <!DOCTYPE html>
          <html lang="en">
          <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>Akash Provider Health Dashboard</title>
              <style>
                  * { margin: 0; padding: 0; box-sizing: border-box; }
                  body {
                      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                      background: linear-gradient(135deg, #1e3a8a 0%, #3b82f6 100%);
                      color: #f8fafc;
                      padding: 20px;
                      min-height: 100vh;
                  }
                  .container {
                      max-width: 1200px;
                      margin: 0 auto;
                  }
                  .header {
                      text-align: center;
                      margin-bottom: 30px;
                  }
                  .header h1 {
                      font-size: 2.5rem;
                      margin-bottom: 10px;
                      text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
                  }
                  .header .status {
                      display: inline-block;
                      padding: 8px 20px;
                      background: rgba(34, 197, 94, 0.2);
                      border: 2px solid #22c55e;
                      border-radius: 25px;
                      font-weight: 600;
                  }
                  .grid {
                      display: grid;
                      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
                      gap: 20px;
                      margin-bottom: 30px;
                  }
                  .card {
                      background: rgba(255, 255, 255, 0.1);
                      backdrop-filter: blur(10px);
                      border: 1px solid rgba(255, 255, 255, 0.2);
                      border-radius: 12px;
                      padding: 24px;
                      transition: transform 0.2s, box-shadow 0.2s;
                  }
                  .card:hover {
                      transform: translateY(-5px);
                      box-shadow: 0 10px 30px rgba(0,0,0,0.3);
                  }
                  .card h3 {
                      font-size: 0.9rem;
                      color: #94a3b8;
                      margin-bottom: 12px;
                      text-transform: uppercase;
                      letter-spacing: 1px;
                  }
                  .card .value {
                      font-size: 3rem;
                      font-weight: 700;
                      margin-bottom: 8px;
                  }
                  .card .label {
                      font-size: 0.85rem;
                      color: #cbd5e1;
                  }
                  .last-update {
                      text-align: center;
                      color: #94a3b8;
                      font-size: 0.9rem;
                  }
                  @keyframes pulse {
                      0%, 100% { opacity: 1; }
                      50% { opacity: 0.5; }
                  }
                  .loading {
                      animation: pulse 2s ease-in-out infinite;
                  }
              </style>
          </head>
          <body>
              <div class="container">
                  <div class="header">
                      <h1>🚀 Akash Provider Health</h1>
                      <div class="status">● $provider_status_text</div>
                  </div>
                  <div class="grid">
                      <div class="card">
                          <h3>Active Deployments</h3>
                          <div class="value">$deployment_count</div>
                          <div class="label">Akash services</div>
                      </div>
                      <div class="card">
                          <h3>Running Pods</h3>
                          <div class="value">$pod_count</div>
                          <div class="label">Total pods</div>
                      </div>
                      <div class="card">
                          <h3>Cluster Nodes</h3>
                          <div class="value">$node_count</div>
                          <div class="label">Available nodes</div>
                      </div>
                      <div class="card">
                          <h3>Active Leases</h3>
                          <div class="value">$active_leases</div>
                          <div class="label">Tenant deployments</div>
                      </div>
                      <div class="card">
                          <h3>Available Capacity</h3>
                          <div class="value">$available_capacity%</div>
                          <div class="label">Resources available</div>
                      </div>
                  </div>
                  <div class="last-update">
                      Last updated: $timestamp | Auto-refresh every 30 seconds
                  </div>
              </div>
          </body>
          </html>
          EOF

          # Atomic move to final location
          mv "$TEMP_FILE" "$OUTPUT_FILE"

          echo "[$(date -Iseconds)] Health dashboard generated"
        '';
      };
    };

    systemd.timers.akash-health-dashboard = mkIf cfg.healthDashboard.enable {
      description = "Akash health dashboard timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "10s";
        OnUnitActiveSec = "${toString cfg.healthDashboard.updateInterval}s";
      };
    };

    # Ensure nginx user and directory exist
    users.users.nginx = mkIf cfg.healthDashboard.enable {
      isSystemUser = true;
      group = "nginx";
    };
    users.groups.nginx = mkIf cfg.healthDashboard.enable {};

    # ============================================================================
    # TMPFILES RULES (merged for all features)
    # ============================================================================
    # Merge all tmpfiles rules from different features
    systemd.tmpfiles.rules = lib.mkAfter (
      lib.optional cfg.metricsExporter.enable "d ${cfg.metricsExporter.metricsDir} 0775 node-exporter node-exporter -"
      ++ lib.optional cfg.healthDashboard.enable "d ${cfg.healthDashboard.outputDir} 0755 nginx nginx -"
      ++ lib.optional cfg.statusPage.enable "d ${cfg.statusPage.outputDir} 0755 nginx nginx -"
    );

    # ============================================================================
    # FEATURE 5: DNS CLEANUP AUTOMATION
    # ============================================================================
    systemd.services.akash-cloudflare-dns-cleanup = mkIf cfg.dnsCleanup.enable {
      description = "Periodic cleanup of stale DNS records";
      path = with pkgs; [curl jq kubectl coreutils gnugrep gnused];

      serviceConfig = {
        Type = "oneshot";
        User = "root";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = ["/var/lib/akash-cloudflare"];

        ExecStart = pkgs.writeShellScript "akash-dns-cleanup" ''
          #!/bin/sh
          set -euo pipefail

          # Configuration
          CLOUDFLARE_TOKEN_FILE="${cfg.tokenFile}"
          CLOUDFLARE_ZONE_ID="${cfg.zoneId}"
          DOMAIN="${cfg.domain}"
          INGRESS_DOMAIN="${cfg.ingressDomain}"
          DNS_PREFIX="${cfg.dnsWatcher.dnsRecordPrefix}"
          GRACE_PERIOD_SECONDS=${toString cfg.dnsCleanup.gracePeriod}
          STATE_DIR="/var/lib/akash-cloudflare"

          # Helper: Get Cloudflare token
          get_token() {
            if [ ! -f "$CLOUDFLARE_TOKEN_FILE" ]; then
              echo "ERROR: Cloudflare token not found" >&2
              exit 1
            fi
            cat "$CLOUDFLARE_TOKEN_FILE"
          }

          # Helper: Get Zone ID from API (fallback if not configured)
          get_zone_id() {
            if [ -n "$CLOUDFLARE_ZONE_ID" ] && [ "$CLOUDFLARE_ZONE_ID" != "abc123def456" ]; then
              echo "$CLOUDFLARE_ZONE_ID"
              return
            fi

            # Fetch Zone ID from domain name
            TOKEN=$(get_token)
            curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
              -H "Authorization: Bearer $TOKEN" \
              -H "Content-Type: application/json" | jq -r '.result[0].id'
          }

          # Get all DNS records for the ingress pattern
          echo "[$(date -Iseconds)] Starting DNS cleanup"

          token=$(get_token)
          zone_id=$(get_zone_id)

          # Get all DNS records matching the pattern
          dns_records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=*.$DNS_PREFIX.$INGRESS_DOMAIN" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json")

          # Get active leases from provider
          active_leases=$(kubectl get deployments -n akash-services -l "akash.network=true" -o jsonpath='{.items[*].metadata.uid}' 2>/dev/null || echo "")

          # Process each DNS record
          echo "$dns_records" | jq -c '.result[]' | while read -r record; do
            record_name=$(echo "$record" | jq -r '.name')
            record_id=$(echo "$record" | jq -r '.id')
            created_time=$(echo "$record" | jq -r '.created_on // .modified_on // "now"')
            tenant_name=$(echo "$record_name" | sed "s/\\.$DNS_PREFIX\\.$INGRESS_DOMAIN//" | sed "s/\\.$DOMAIN//")

            # Check if tenant has an active deployment
            deployment_uid=$(kubectl get deployments -n akash-services -l "akash.network=true" -o json | jq -r ".items[] | select(.metadata.name | contains(\"$tenant_name\")).metadata.uid" || echo "")

            if [ -z "$deployment_uid" ]; then
              # No active deployment, check grace period
              record_timestamp=$(date -d "$created_time" +%s 2>/dev/null || echo "0")
              current_timestamp=$(date +%s)
              age_seconds=$((current_timestamp - record_timestamp))

              if [ $age_seconds -gt $GRACE_PERIOD_SECONDS ]; then
                echo "[$(date -Iseconds)] Deleting stale DNS record: $record_name (age: $age_seconds seconds)"

                # Delete the record
                curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
                  -H "Authorization: Bearer $token" | jq -r '.success'
              else
                echo "[$(date -Iseconds)] Record $record_name is $age_seconds old (grace period: $GRACE_PERIOD_SECONDS)"
              fi
            fi
          done

          echo "[$(date -Iseconds)] DNS cleanup completed"
        '';
      };
    };

    systemd.timers.akash-cloudflare-dns-cleanup = mkIf cfg.dnsCleanup.enable {
      description = "Akash DNS cleanup timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.dnsCleanup.cleanupTime;
        Persistent = true;
      };
    };

    # ============================================================================
    # FEATURE 6: STATUS PAGE
    # ============================================================================
    systemd.services.akash-status-page = mkIf cfg.statusPage.enable {
      description = "Generate public Akash provider status page";
      wantedBy = ["multi-user.target"];
      path = with pkgs; [curl jq kubectl coreutils];

      serviceConfig = {
        Type = "oneshot";
        User = "nginx";
        Group = "nginx";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [cfg.statusPage.outputDir];

        ExecStart = pkgs.writeShellScript "akash-status-page" ''
          #!/bin/sh
          set -euo pipefail

          # Configuration
          PROVIDER_ENDPOINT="${cfg.providerEndpoint}"
          OUTPUT_DIR="${cfg.statusPage.outputDir}"
          OUTPUT_FILE="$OUTPUT_DIR/index.html"
          TEMP_FILE="$OUTPUT_FILE.tmp"

          # Ensure output directory exists
          mkdir -p "$OUTPUT_DIR"

          # Fetch provider status
          provider_status=$(curl -s "$PROVIDER_ENDPOINT" 2>/dev/null || echo '{"status":"error"}')

          # Get cluster resources
          node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
          gpu_count=$(kubectl get nodes -o jsonpath='{.items[*].status.capacity.nvidia\.com/gpu}' 2>/dev/null | tr ' ' '\n' | grep -v '^$' | wc -l || echo "0")

          # Extract provider info
          provider_address=$(echo "$provider_status" | jq -r '.provider_address // "Unknown"')
          active_leases=$(echo "$provider_status" | jq -r '.active_leases // 0')
          uptime=$(echo "$provider_status" | jq -r '.uptime // "Unknown"')

          # Get timestamp
          timestamp=$(date -Iseconds)

          # Generate public status page
          cat > "$TEMP_FILE" <<'EOF'
          <!DOCTYPE html>
          <html lang="en">
          <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>Akash Provider Status</title>
              <style>
                  * { margin: 0; padding: 0; box-sizing: border-box; }
                  body {
                      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                      background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
                      color: #f1f5f9;
                      padding: 40px 20px;
                      min-height: 100vh;
                  }
                  .container {
                      max-width: 900px;
                      margin: 0 auto;
                  }
                  .hero {
                      text-align: center;
                      margin-bottom: 50px;
                  }
                  .hero h1 {
                      font-size: 3rem;
                      margin-bottom: 15px;
                      background: linear-gradient(135deg, #3b82f6, #8b5cf6);
                      -webkit-background-clip: text;
                      -webkit-text-fill-color: transparent;
                      background-clip: text;
                  }
                  .hero p {
                      font-size: 1.2rem;
                      color: #94a3b8;
                  }
                  .card {
                      background: rgba(255, 255, 255, 0.05);
                      backdrop-filter: blur(10px);
                      border: 1px solid rgba(255, 255, 255, 0.1);
                      border-radius: 16px;
                      padding: 30px;
                      margin-bottom: 20px;
                  }
                  .card h2 {
                      font-size: 1.5rem;
                      margin-bottom: 20px;
                      color: #60a5fa;
                  }
                  .stat-grid {
                      display: grid;
                      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                      gap: 20px;
                  }
                  .stat {
                      background: rgba(59, 130, 246, 0.1);
                      border: 1px solid rgba(59, 130, 246, 0.3);
                      border-radius: 12px;
                      padding: 20px;
                  }
                  .stat-label {
                      font-size: 0.85rem;
                      color: #94a3b8;
                      margin-bottom: 8px;
                      text-transform: uppercase;
                      letter-spacing: 1px;
                  }
                  .stat-value {
                      font-size: 2rem;
                      font-weight: 700;
                      color: #60a5fa;
                  }
                  .info-list {
                      list-style: none;
                  }
                  .info-list li {
                      padding: 12px 0;
                      border-bottom: 1px solid rgba(255, 255, 255, 0.1);
                      display: flex;
                      justify-content: space-between;
                  }
                  .info-list li:last-child {
                      border-bottom: none;
                  }
                  .info-label {
                      color: #94a3b8;
                  }
                  .info-value {
                      font-weight: 600;
                      color: #f1f5f9;
                  }
                  .footer {
                      text-align: center;
                      margin-top: 40px;
                      color: #64748b;
                      font-size: 0.9rem;
                  }
                  .status-badge {
                      display: inline-block;
                      padding: 6px 16px;
                      background: rgba(34, 197, 94, 0.2);
                      border: 1px solid #22c55e;
                      border-radius: 20px;
                      font-size: 0.9rem;
                      font-weight: 600;
                      color: #22c55e;
                  }
              </style>
          </head>
          <body>
              <div class="container">
                  <div class="hero">
                      <h1>⚡ Akash Network Provider</h1>
                      <p>Decentralized Compute Marketplace</p>
                      <div style="margin-top: 20px;">
                          <span class="status-badge">● Operational</span>
                      </div>
                  </div>
                  <div class="card">
                      <h2>Provider Information</h2>
                      <ul class="info-list">
                          <li><span class="info-label">Provider Address</span><span class="info-value">$provider_address</span></li>
                          <li><span class="info-label">Domain</span><span class="info-value">${cfg.domain}</span></li>
                          <li><span class="info-label">Uptime</span><span class="info-value">$uptime</span></li>
                      </ul>
                  </div>
                  <div class="card">
                      <h2>Cluster Resources</h2>
                      <div class="stat-grid">
                          <div class="stat">
                              <div class="stat-label">Nodes</div>
                              <div class="stat-value">$node_count</div>
                          </div>
                          <div class="stat">
                              <div class="stat-label">GPUs</div>
                              <div class="stat-value">$gpu_count</div>
                          </div>
                          <div class="stat">
                              <div class="stat-label">Active Leases</div>
                              <div class="stat-value">$active_leases</div>
                          </div>
                      </div>
                  </div>
                  <div class="card">
                      <h2>Supported GPU Models</h2>
                      <ul class="info-list">
                          <li><span class="info-label">NVIDIA RTX 3090</span><span class="info-value">24GB VRAM</span></li>
                          <li><span class="info-label">NVIDIA RTX 4060</span><span class="info-value">8GB VRAM</span></li>
                          <li><span class="info-label">NVIDIA RTX 3060 Ti</span><span class="info-value">8GB VRAM</span></li>
                      </ul>
                  </div>
                  <div class="footer">
                      <p>Last updated: $timestamp</p>
                      <p style="margin-top: 10px;">Powered by Akash Network • NixOS Cluster</p>
                  </div>
              </div>
          </body>
          </html>
          EOF

          # Atomic move to final location
          mv "$TEMP_FILE" "$OUTPUT_FILE"

          echo "[$(date -Iseconds)] Status page generated"
        '';
      };
    };

    systemd.timers.akash-status-page = mkIf cfg.statusPage.enable {
      description = "Akash status page timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "10s";
        OnUnitActiveSec = "${toString cfg.statusPage.updateInterval}s";
      };
    };

    # ============================================================================
    # SECURITY: FIREWALL (No additional ports needed)
    # ============================================================================
    # All features use existing Cloudflare tunnel (no new firewall rules)
    # Health dashboard and status page served via cloudflared.nix tunnel routes
  };
}
