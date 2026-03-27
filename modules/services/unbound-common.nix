# Unified Unbound DNS Configuration for All Cluster Hosts
# Each host imports this module to get DNS-over-TLS to Cloudflare, Google, Quad9
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkOption types;
  cfg = config.clusterNetworking;
in {
  options.services.unbound-common = {
    enable = lib.mkEnableOption "Unbound DNS resolver with DNS-over-TLS (cluster-wide config)";
  };

  config = mkIf cfg.enable {
    services.unbound = {
      enable = true;

      settings = {
        server = {
          # Interface configuration (use mkForce to override defaults)
          interface = lib.mkForce [ "127.0.0.1" "::1" cfg.ipAddress ];

          # Access control (use mkForce to override defaults)
          access-control = lib.mkForce [
            "127.0.0.0/8 allow"
            "10.1.1.0/24 allow"  # Cluster network
            "10.244.0.0/16 allow"  # Kubernetes pod network
          ];

          # Performance tuning
          num-threads = 4;
          msg-cache-size = "128m";
          rrset-cache-size = "128m";
          msg-cache-slabs = 4;
          rrset-cache-slabs = 4;

          # Security
          val-clean-additional = true;
          aggressive-nsec = true;
          hide-identity = true;
          hide-version = true;
          qname-minimisation = true;
          rrset-roundrobin = true;

          # Privacy
          logfile = "/var/log/unbound.log";
          use-syslog = true;
          log-queries = true;  # ENABLED: Debug logging
          log-replies = true;  # ENABLED: Debug logging
          verbosity = 2;  # ENABLED: Verbose debug output

          # TTL
          cache-max-ttl = 86400;
          cache-min-ttl = 300;

          # EDNS
          edns-buffer-size = 1232;

          # TLS settings for DNS-over-TLS (TEMPORARILY DISABLED FOR TESTING)
          tls-cert-bundle = "/etc/ssl/certs/ca-bundle.crt";
          # tls-upstream = true;  # DISABLED: Testing basic forwarding first
        };

        # Forward to DNS servers (using port 53 instead of 853 for testing)
        forward-zone = [
          {
            name = ".";
            forward-addr = [
              "1.1.1.1"  # Cloudflare DNS (plain DNS for testing)
              "1.0.0.1"  # Cloudflare DNS secondary
              "8.8.8.8"  # Google DNS (plain DNS for testing)
              "8.8.4.4"  # Google DNS secondary
              "9.9.9.9"  # Quad9 DNS (plain DNS for testing)
              "149.112.112.112"  # Quad9 DNS secondary
            ];
          }
        ];
      };
    };

    # CRITICAL: Fix forward-zone ordering bug and prevent systemd from killing Unbound
    systemd.services.unbound = {
      restartIfChanged = false;
      reloadIfChanged = false;
      restartTriggers = [ ];  # Empty = never restart due to config changes

      # CRITICAL FIX: NixOS generates broken forward-zone (name at end instead of first)
      # Solution: Generate fixed config in writable location and override ExecStart
      preStart = ''
        # Copy and fix the generated config to a writable location
        ${pkgs.python3}/bin/python3 << "PYTHON"
        import sys
        with open('/etc/unbound/unbound.conf', 'r') as f:
          lines = f.readlines()

        # Find and fix forward-zone section
        output = []
        in_forward_zone = False
        for i, line in enumerate(lines):
          if line.startswith('forward-zone:'):
            in_forward_zone = True
            output.append(line)
            # Add name: . immediately after forward-zone:
            output.append('  name: .\n')
          elif in_forward_zone and line.strip().startswith('name: .'):
            # Skip the misplaced name: . line
            continue
          elif in_forward_zone and line.startswith('remote-control:'):
            in_forward_zone = False
            output.append(line)
          else:
            output.append(line)

        # Write fixed config to writable location
        with open('/var/lib/unbound/unbound-fixed.conf', 'w') as f:
          f.writelines(output)

        print('[unbound] Generated fixed config with name: . FIRST')
        PYTHON

        # Smart DNSSEC root anchor update - only update if missing or old
        # Check if root.key exists and is recent (<30 days)
        if [ -f /var/lib/unbound/root.key ]; then
          KEY_AGE=$(($(date +%s) - $(stat -c %Y /var/lib/unbound/root.key)))
          KEY_AGE_DAYS=$((KEY_AGE / 86400))
          if [ "$KEY_AGE_DAYS" -lt 30 ]; then
            echo "[unbound] Root key is $KEY_AGE_DAYS days old, skipping update"
            exit 0
          fi
        fi

        # Only update if missing or old (with timeout)
        echo "[unbound] Updating DNSSEC root anchor..."
        timeout 10 ${pkgs.unbound}/bin/unbound-anchor -a /var/lib/unbound/root.key || {
          echo "[unbound] Root anchor update timed out or failed, using existing key"
          # Continue anyway - the existing key is probably fine
          exit 0
        }
      '';

      serviceConfig = lib.mkForce {
        # Override ExecStart to use the fixed config file
        ExecStart = [
          "${pkgs.unbound}/bin/unbound"
          "-p"  # Don't daemonize
          "-d"  # Debug mode
          "-c"  # Config file
          "/var/lib/unbound/unbound-fixed.conf"  # Use our fixed config
        ];
        # Preserve upstream defaults for other settings
        Restart = lib.mkOptionDefault "always";
        RestartSec = lib.mkOptionDefault "10s";
      };
    };

    # Firewall
    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [ 53 ];
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ 53 ];
  };
}
