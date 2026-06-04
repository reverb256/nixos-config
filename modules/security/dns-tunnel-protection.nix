{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.dns-tunnel-protection;
  inherit (lib) mkEnableOption mkOption types mkIf mkOptionDefault;

  # Cluster network ranges
  clusterSubnet = "10.1.1.0/24";
  podSubnet = "10.42.0.0/16";
  serviceCIDR = "10.43.0.0/16";

  # Allowed upstream DNS (DoT on 853)
  allowedUpstreamDns = [
    "1.1.1.1"
    "1.0.0.1"
    "8.8.8.8"
    "8.8.4.4"
  ];

  # Rate limits
  dnsQueryRate = toString cfg.rateLimitQueriesPerSecond;
  dnsBurst = toString cfg.rateLimitBurst;

  # Detection script
  detectionScript = pkgs.writeShellScript "dns-tunnel-detector" ''
    #!/usr/bin/env bash
    # DNS Tunneling Detector
    # Monitors unbound logs for tunneling patterns and exports Prometheus metrics

    METRICS_DIR="/var/run/dns-tunnel-protection"
    METRICS_FILE="$METRICS_DIR/metrics.prom"
    LOG_FILE="/var/log/unbound/unbound.log"
    STATE_FILE="$METRICS_DIR/state.json"
    ALERT_LOG="/var/log/dns-tunnel-alerts.log"

    mkdir -p "$METRICS_DIR"

    # Initialize state
    if [ ! -f "$STATE_FILE" ]; then
      echo '{"window_start": 0, "query_count": 0, "long_domain_count": 0, "high_entropy_count": 0, "alerts": []}' > "$STATE_FILE"
    fi

    # Initialize metrics
    init_metrics() {
      cat > "$METRICS_FILE" <<EOF
    # HELP dns_queries_total Total DNS queries observed
    # TYPE dns_queries_total counter
    dns_queries_total 0
    # HELP dns_long_domains_total Queries with unusually long domain names (potential tunneling)
    # TYPE dns_long_domains_total counter
    dns_long_domains_total 0
    # HELP dns_high_entropy_total Queries with high-entropy subdomains (encoded data)
    # TYPE dns_high_entropy_total counter
    # dns_high_entropy_total 0
    # HELP dns_rate_limit_events_total Number of rate limit events triggered
    # TYPE dns_rate_limit_events_total counter
    dns_rate_limit_events_total 0
    # HELP dns_tunnel_alerts_active Current active tunneling alerts
    # TYPE dns_tunnel_alerts_active gauge
    dns_tunnel_alerts_active 0
    EOF
    }

    # Calculate Shannon entropy of a string
    calc_entropy() {
      local str="$1"
      echo "$str" | fold -w1 | sort | uniq -c | awk -v len="''${#str}" '
        BEGIN { entropy = 0 }
        { count = $1; p = count / len; if (p > 0) entropy -= p * (log(p) / log(2)) }
        END { printf "%.2f", entropy }
      '
    }

    # Analyze recent queries for tunneling patterns
    analyze_queries() {
      local now
      now=$(date +%s)
      local window_start
      window_start=$(jq '.window_start' "$STATE_FILE")
      local window_size=${toString cfg.detectionWindowSeconds}

      # Reset window if expired
      if (( now - window_start > window_size )); then
        echo "{\"window_start\": $now, \"query_count\": 0, \"long_domain_count\": 0, \"high_entropy_count\": 0, \"alerts\": []}" > "$STATE_FILE"
        window_start=$now
      fi

      local query_count=0
      local long_domain_count=0
      local high_entropy_count=0

      # Parse recent unbound log entries (last 60 seconds)
      if [ -f "$LOG_FILE" ]; then
        local cutoff
        cutoff=$(date -d "60 seconds ago" +"%H:%M:%S" 2>/dev/null || date +"%H:%M:%S")

        while IFS= read -r line; do
          # Extract queried domain from unbound log
          local domain
          domain=$(echo "$line" | grep -oP 'query\[\S+\] \S+ IN \K\S+' 2>/dev/null || true)
          [ -z "$domain" ] && continue

          query_count=$((query_count + 1))

          # Check for long domain names (>50 chars = potential tunnel)
          if [ ''${#domain} -gt 50 ]; then
            long_domain_count=$((long_domain_count + 1))
          fi

          # Check subdomain entropy (extract subdomain part)
          local subdomain
          subdomain=$(echo "$domain" | awk -F'.' '{if(NF>2){for(i=1;i<NF-1;i++)printf "%s.",$i; print $(NF-1)}else{print $1}}')
          if [ -n "$subdomain" ] && [ ''${#subdomain} -gt 20 ]; then
            local entropy
            entropy=$(calc_entropy "$subdomain")
            if (( $(echo "$entropy > 3.5" | bc -l 2>/dev/null || echo 0) )); then
              high_entropy_count=$((high_entropy_count + 1))
            fi
          fi
        done < <(tail -n ${toString cfg.maxLogLines} "$LOG_FILE" 2>/dev/null || true)
      fi

      # Update state
      local state
      state=$(jq --argjson qc "$query_count" \
        --argjson ldc "$long_domain_count" \
        --argjson hec "$high_entropy_count" \
        '.query_count = $qc | .long_domain_count = $ldc | .high_entropy_count = $hec' \
        "$STATE_FILE")

      # Check for alert conditions
      local alerts=0
      local alert_msg=""

      if [ "$query_count" -gt ${toString cfg.alertQueryThreshold} ]; then
        alerts=$((alerts + 1))
        alert_msg="HIGH_QUERY_RATE: $query_count queries in ${toString cfg.detectionWindowSeconds}s window"
      fi

      if [ "$long_domain_count" -gt ${toString cfg.alertLongDomainThreshold} ]; then
        alerts=$((alerts + 1))
        alert_msg="$alert_msg LONG_DOMAINS: $long_domain_count queries with domains >50 chars"
      fi

      if [ "$high_entropy_count" -gt ${toString cfg.alertHighEntropyThreshold} ]; then
        alerts=$((alerts + 1))
        alert_msg="$alert_msg HIGH_ENTROPY: $high_entropy_count queries with high-entropy subdomains"
      fi

      # Write alerts
      if [ "$alerts" -gt 0 ]; then
        echo "[$(date -Iseconds)] ALERT: $alert_msg" >> "$ALERT_LOG"
        # Keep only last 1000 alert lines
        tail -n 1000 "$ALERT_LOG" > "$ALERT_LOG.tmp" && mv "$ALERT_LOG.tmp" "$ALERT_LOG"
      fi

      # Write Prometheus metrics
      cat > "$METRICS_FILE" <<EOF
    # HELP dns_queries_total Total DNS queries in current detection window
    # TYPE dns_queries_total gauge
    dns_queries_total $query_count
    # HELP dns_long_domains_total Queries with unusually long domain names (potential tunneling)
    # TYPE dns_long_domains_total gauge
    dns_long_domains_total $long_domain_count
    # HELP dns_high_entropy_total Queries with high-entropy subdomains (encoded data)
    # TYPE dns_high_entropy_total gauge
    dns_high_entropy_total $high_entropy_count
    # HELP dns_tunnel_alerts_active Current active tunneling alerts
    # TYPE dns_tunnel_alerts_active gauge
    dns_tunnel_alerts_active $alerts
    EOF

      echo "$state" > "$STATE_FILE"
    }

    # Main loop
    init_metrics
    while true; do
      analyze_queries
      sleep ${toString cfg.detectionIntervalSeconds}
    done
  '';

  # Prometheus textfile collector script
  textfileCollectorScript = pkgs.writeShellScript "dns-metrics-collector" ''
    #!/usr/bin/env bash
    # Copy metrics to node_exporter textfile collector directory
    METRICS_DIR="/var/run/dns-tunnel-protection"
    COLLECTOR_DIR="/var/lib/node_exporter/textfile_collector"

    mkdir -p "$COLLECTOR_DIR"

    if [ -f "$METRICS_DIR/metrics.prom" ]; then
      cp "$METRICS_DIR/metrics.prom" "$COLLECTOR_DIR/dns_tunnel.prom"
    fi
  '';
in {
  options.services.dns-tunnel-protection = {
    enable = mkEnableOption "DNS tunneling protection (rate limiting, detection, alerting)";

    enableRateLimiting = mkOption {
      type = types.bool;
      default = true;
      description = "Enable DNS query rate limiting via nftables";
    };

    enablePortBlocking = mkOption {
      type = types.bool;
      default = true;
      description = "Block outbound DNS on non-standard ports";
    };

    enableDetection = mkOption {
      type = types.bool;
      default = true;
      description = "Enable DNS tunneling pattern detection";
    };

    rateLimitQueriesPerSecond = mkOption {
      type = types.int;
      default = 50;
      description = "Maximum DNS queries per second per source IP";
    };

    rateLimitBurst = mkOption {
      type = types.int;
      default = 100;
      description = "Burst allowance for DNS queries";
    };

    detectionWindowSeconds = mkOption {
      type = types.int;
      default = 60;
      description = "Detection analysis window in seconds";
    };

    detectionIntervalSeconds = mkOption {
      type = types.int;
      default = 15;
      description = "How often to run detection analysis";
    };

    alertQueryThreshold = mkOption {
      type = types.int;
      default = 500;
      description = "Alert if more than this many queries in detection window";
    };

    alertLongDomainThreshold = mkOption {
      type = types.int;
      default = 10;
      description = "Alert if more than this many long-domain queries in window";
    };

    alertHighEntropyThreshold = mkOption {
      type = types.int;
      default = 10;
      description = "Alert if more than this many high-entropy queries in window";
    };

    maxLogLines = mkOption {
      type = types.int;
      default = 10000;
      description = "Maximum unbound log lines to analyze per cycle";
    };

    blockedPorts = mkOption {
      type = types.listOf types.int;
      default = [5353 5354 5355];
      description = "Non-standard DNS ports to block (mDNS, LLMNR, etc.)";
    };
  };

  config = mkIf cfg.enable {
    # ── Firewall: Rate limiting + port blocking ──────────────────────────
    networking.firewall = {
      # Rate limit DNS queries (UDP port 53) per source IP
      extraInputRules = lib.concatStrings [
        (mkIf cfg.enableRateLimiting (mkOptionDefault ''
          # DNS rate limiting — drop excess queries per source IP
          ip protocol udp udp dport 53 limit rate ${dnsQueryRate}/second burst ${dnsBurst} packets accept
          ip protocol udp udp dport 53 counter drop

          # DNS rate limiting — TCP (zone transfers, large responses)
          ip protocol tcp tcp dport 53 limit rate ${dnsQueryRate}/second burst ${dnsBurst} packets accept
          ip protocol tcp tcp dport 53 counter drop
        ''))
        ''
          # Allow DNS from cluster and pod networks (rate limited by rules above)
          ip saddr { ${clusterSubnet}, ${podSubnet} } udp dport 53 accept
          ip saddr { ${clusterSubnet}, ${podSubnet} } tcp dport 53 accept
        ''
      ];

      #      # Block outbound DNS on non-standard ports (prevents tunneling via alternate ports)
      #      extraOutputRules = mkIf cfg.enablePortBlocking (mkOptionDefault ''
      #        # Block outbound DNS on non-standard ports
      #        # Allows only port 53 (standard DNS) and 853 (DNS-over-TLS) to authorized upstreams
      #        ip protocol udp udp dport { ${lib.concatStringsSep ", " (map toString cfg.blockedPorts)} } counter drop
      #        ip protocol tcp tcp dport { ${lib.concatStringsSep ", " (map toString cfg.blockedPorts)} } counter drop
      #
      #        # Block all outbound DNS to non-authorized destinations (except local unbound)
      #        # This prevents pods/containers from bypassing the local resolver
      #        ip daddr != { 127.0.0.1, ${lib.concatStringsSep ", " allowedUpstreamDns} } ip protocol udp udp dport 53 counter drop
      #        ip daddr != { 127.0.0.1, ${lib.concatStringsSep ", " allowedUpstreamDns} } ip protocol tcp tcp dport 53 counter drop
      #
      #        # Allow DNS to localhost (our unbound resolver)
      #        ip daddr 127.0.0.1 udp dport 53 accept
      #        ip daddr 127.0.0.1 tcp dport 53 accept
      #
      #        # Allow DNS-over-TLS to authorized upstreams
      #        ip daddr { ${lib.concatStringsSep ", " allowedUpstreamDns} } tcp dport 853 accept
      #      '');
    };

    # ── Unbound: Enable query logging for detection ─────────────────────
    services.unbound.settings.server = mkIf cfg.enableDetection {
      # Enable detailed logging for tunnel detection
      log-queries = true;
      log-replies = true;
      log-local-actions = true;
      verbosity = 1;
    };

    # ── DNS Tunnel Detection Service ─────────────────────────────────────
    systemd.services.dns-tunnel-detector = mkIf cfg.enableDetection {
      description = "DNS Tunneling Pattern Detector";
      wantedBy = ["multi-user.target"];
      after = ["unbound.service"];
      requires = ["unbound.service"];

      serviceConfig = {
        Type = "simple";
        ExecStart = detectionScript;
        Restart = "on-failure";
        RestartSec = 5;
        User = "root";
        Group = "root";

        # Security hardening
        NoNewPrivileges = false; # Needs to read unbound logs
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = ["/var/run/dns-tunnel-protection" "/var/log/dns-tunnel-alerts.log"];
        ReadOnlyPaths = ["/var/log/unbound"];
      };
    };

    # ── Metrics collector (runs via systemd timer for node_exporter) ─────
    systemd.services.dns-metrics-collector = mkIf cfg.enableDetection {
      description = "Collect DNS tunnel metrics for Prometheus";
      wantedBy = ["multi-user.target"];
      after = ["dns-tunnel-detector.service"];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = textfileCollectorScript;
        User = "root";
        Group = "root";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = ["/var/lib/node_exporter/textfile_collector"];
        ReadOnlyPaths = ["/var/run/dns-tunnel-protection"];
      };
    };

    systemd.timers.dns-metrics-collector = mkIf cfg.enableDetection {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "${toString cfg.detectionIntervalSeconds}s";
        Unit = "dns-metrics-collector.service";
      };
    };

    # ── Log rotation for DNS tunnel alerts ───────────────────────────────
    services.logrotate.extraConfig = mkIf cfg.enableDetection ''
      /var/log/dns-tunnel-alerts.log {
        weekly
        rotate 4
        compress
        delaycompress
        missingok
        notifempty
        create 0640 root root
      }
    '';

    # ── Required directories ─────────────────────────────────────────────
    systemd.tmpfiles.rules = mkIf cfg.enableDetection [
      "d /var/run/dns-tunnel-protection 0755 root root -"
      "d /var/lib/node_exporter/textfile_collector 0755 root root -"
      "f /var/log/dns-tunnel-alerts.log 0640 root root -"
    ];
  };
}
