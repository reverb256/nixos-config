# Cluster SSH Aliases - Quick access to all nodes from zephyr
# Provides convenience functions for cluster management
{pkgs, ...}: {
  # Add the jjust wrapper to system packages
  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "jjust" ''
      #!/bin/bash
      # Wrapper script for running just commands from any directory
      # This allows 'jjust' to work globally while preserving the original 'just' for local justfiles

      JUSTFILE="/etc/nixos/justfile"

      # Check if the justfile exists
      if [[ ! -f "$JUSTFILE" ]]; then
        echo "Error: Justfile not found at $JUSTFILE" >&2
        exit 1
      fi

      # Run just with the explicit justfile path
      exec just --justfile "$JUSTFILE" "$@"
    '')
  ];

  # Fish shell aliases for cluster access
  programs.fish.interactiveShellInit = ''
    # Cluster node aliases
    alias z='ssh zephyr'
    alias n='ssh nexus'
    alias s='ssh sentry'
    alias f='ssh forge'

    # Justfile wrapper - run just commands from any directory
    # Usage: just switch, just deploy, etc. (works from any directory)
    alias just jjust

    # Cluster management functions (cannot use alias for loops in fish)
    function cluster-ping --description "Ping all cluster nodes"
      for h in zephyr nexus sentry forge
        echo "→ $h:"
        ssh -o ConnectTimeout=2 $h "uptime" 2>/dev/null || echo "  unreachable"
        echo
      end
    end

    function cluster-update --description "Update all cluster nodes"
      for h in zephyr nexus sentry forge
        echo "→ Updating $h..."
        ssh $h "sudo nixos-rebuild switch --flake /etc/nixos#\$hostname"
        echo
      end
    end

    # Run command on all cluster nodes
    # Usage: cluster-run "command"
    function cluster-run --description "Run command on all cluster nodes"
      if test (count $argv) -eq 0
        echo "Usage: cluster-run <command>"
        return 1
      end

      for h in zephyr nexus sentry forge
        echo "→ $h:"
        ssh $h $argv
        echo
      end
    end

    # Run command on specific nodes
    # Usage: cluster-run-on nexus,sentry "command"
    function cluster-run-on --description "Run command on specific cluster nodes"
      if test (count $argv) -lt 2
        echo "Usage: cluster-run-on <host1,host2,...> <command>"
        return 1
      end

      set hosts (string split , $argv[1])
      set cmd $argv[2..]

      for h in $hosts
        echo "→ $h:"
        ssh $h $cmd
        echo
      end
    end

    # Copy file to all cluster nodes
    # Usage: cluster-scp file /path/on/remote/
    function cluster-scp --description "Copy file to all cluster nodes"
      if test (count $argv) -lt 2
        echo "Usage: cluster-scp <local-file> <remote-path>"
        return 1
      end

      set src $argv[1]
      set dest $argv[2]

      for h in zephyr nexus sentry forge
        echo "→ $h:"
        scp $src $h:$dest
        echo
      end
    end

    # Show cluster status
    function cluster-status --description "Show cluster status"
      echo "=== NixOS Cluster Status ==="
      echo
      for h in zephyr nexus sentry forge
        echo "→ $h:"
        ssh -o ConnectTimeout=2 $h "
          echo \"  Hostname: \$(hostname)\"
          echo \"  Uptime: \$(uptime -p)\"
          echo \"  Kernel: \$(uname -r)\"
          echo \"  Load: \$(uptime | awk -F'load average:' '{print \$2}')\"
        " 2>/dev/null || echo "  ❌ Unreachable"
        echo
      end
    end

    # Show cluster tools availability
    function cluster-tools --description "Show tools across cluster"
      echo "=== Development Tools Across Cluster ==="
      echo
      for tool in cargo go node python zig nvim git
        echo -n "$tool: "
        for h in zephyr nexus sentry forge
          ssh -o ConnectTimeout=2 $h "command -v $tool" >/dev/null 2>&1 && echo -n "✓" || echo -n "✗"
        end
        echo
      end
      echo "       z n s f"
    end
  '';

  # Also add bash aliases for compatibility
  programs.bash.interactiveShellInit = ''
    # Cluster node aliases
    alias z='ssh zephyr'
    alias n='ssh nexus'
    alias s='ssh sentry'
    alias f='ssh forge'

    # Justfile wrapper - run just commands from any directory
    # Usage: just switch, just deploy, etc. (works from any directory)
    alias just='jjust'

    # Run command on all cluster nodes
    cluster-run() {
      if [ $# -eq 0 ]; then
        echo "Usage: cluster-run <command>"
        return 1
      fi

      for h in zephyr nexus sentry forge; do
        echo "→ $h:"
        ssh "$h" "$@"
        echo
      done
    }

    # Show cluster status
    cluster-status() {
      echo "=== NixOS Cluster Status ==="
      echo
      for h in zephyr nexus sentry forge; do
        echo "→ $h:"
        ssh -o ConnectTimeout=2 "$h" "
          echo \"  Hostname: \$(hostname)\"
          echo \"  Uptime: \$(uptime -p)\"
        " 2>/dev/null || echo "  ❌ Unreachable"
        echo
      done
    }
  '';
}
