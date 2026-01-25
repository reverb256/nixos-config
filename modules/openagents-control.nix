# OpenAgents Control Module
# AI agent framework for plan-first development workflows with approval-based execution
{
  config,
  lib,
  pkgs,
  ...
}: {
  options = {
    services.openagents-control = {
      enable = lib.mkEnableOption "Enable OpenAgents Control installation and management";

      installProfile = lib.mkOption {
        type = lib.types.enum ["essential" "developer" "business" "full" "advanced"];
        default = "developer";
        description = ''
          Installation profile to use:
          - essential: Minimal setup with core agents (9 components)
          - developer: Complete software development environment (30 components)
          - business: Business process automation (15 components)
          - full: Everything included (36 components)
          - advanced: Full installation with System Builder (43 components)
        '';
      };

      installDir = lib.mkOption {
        type = lib.types.str;
        default = "/home/j_kro/.config/opencode";
        example = "~/.config/opencode";
        description = ''
          Installation directory for OpenAgents Control components.
          Defaults to ~/.config/opencode (global installation).
        '';
      };

      autoUpdate = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable automatic updates of OpenAgents Control components";
      };
    };
  };

  config = lib.mkIf config.services.openagents-control.enable {
    # Ensure required dependencies are installed
    environment.systemPackages = with pkgs; [
      # Required for installer
      bash
      curl
      jq
    ];

    # Set environment variables for MCP and tool fixes
    environment.sessionVariables = {
      # Fix MCP schema errors
      OPENCODE_MCP_SCHEMA_FIX = "1";
      # Fix tool output formatting
      OPENCODE_TOOL_STRUCTURED_OUTPUT = "1";
      # Set proper PATH for OpenCode tools
      OPENCODE_PATH_FIX = "1";
    };

    # Create wrapper scripts for OpenAgents Control management
    environment.etc."opencode-installer.sh".text = ''
      #!/usr/bin/env bash
      set -e

      INSTALL_DIR="/home/j_kro/.config/opencode"

      # Check if OpenAgents Control is already installed
      if [ -d "$INSTALL_DIR" ]; then
        echo "OpenAgents Control is already installed at $INSTALL_DIR"
        echo "To update, run: sudo opencode-update"
        echo ""
        echo "To manage components manually:"
        echo "  opencode --agent openagent"
        echo ""
        exit 0
      fi

      echo "Installing OpenAgents Control with profile: ''${config.services.openagents-control.installProfile}"
      echo "Installation directory: $INSTALL_DIR"
      echo ""

      # Download and run installer
      if ! curl -fsSL https://raw.githubusercontent.com/darrenhinde/OpenAgentsControl/main/install.sh -o /tmp/openagents-install.sh; then
        echo "Error: Failed to download installer"
        exit 1
      fi

      chmod +x /tmp/openagents-install.sh

      # Run installer with selected profile
      bash /tmp/openagents-install.sh ''${config.services.openagents-control.installProfile} --install-dir "$INSTALL_DIR"

      echo ""
      echo "OpenAgents Control installation complete!"
      echo "Installation directory: $INSTALL_DIR"
      echo ""
      echo "Next steps:"
      echo "  1. Review installed components: ls $INSTALL_DIR"
      echo "  2. Start using OpenCode agents: opencode --agent openagent"
      echo ""
    '';

    environment.etc."opencode-update.sh".text = ''
      #!/usr/bin/env bash
      set -e

      INSTALL_DIR="/home/j_kro/.config/opencode"

      if [ ! -d "$INSTALL_DIR" ]; then
        echo "Error: OpenAgents Control not installed at $INSTALL_DIR"
        echo "Run 'sudo opencode-install' to install first"
        exit 1
      fi

      echo "Updating OpenAgents Control components..."
      echo "Installation directory: $INSTALL_DIR"
      echo ""

      # Download and run installer to update
      if ! curl -fsSL https://raw.githubusercontent.com/darrenhinde/OpenAgentsControl/main/install.sh -o /tmp/openagents-install.sh; then
        echo "Error: Failed to download installer"
        exit 1
      fi

      chmod +x /tmp/openagents-install.sh

      # Run installer with current profile to update
      bash /tmp/openagents-install.sh ''${config.services.openagents-control.installProfile} --install-dir "$INSTALL_DIR"

      echo ""
      echo "OpenAgents Control update complete!"
      echo "Installation directory: $INSTALL_DIR"
    '';

    environment.etc."openable-enable.sh".text = ''
      #!/usr/bin/env bash
      set -e

      INSTALL_DIR="/home/j_kro/.config/opencode"

      if [ ! -d "$INSTALL_DIR" ]; then
        echo "Error: OpenAgents Control not installed at $INSTALL_DIR"
        echo "Run 'sudo opencode-install' to install first"
        exit 1
      fi

      # Create opencode wrapper that points to installation directory
      cat > /usr/local/bin/opencode-wrapper << 'EOF'
      #!/usr/bin/env bash
      export OPENCODE_INSTALL_DIR="$INSTALL_DIR"

      # Fix MCP schema errors
      export OPENCODE_MCP_SCHEMA_FIX="1"
      export OPENCODE_TOOL_STRUCTURED_OUTPUT="1"

      # If opencode is not in PATH, show helpful message
      if ! command -v opencode &> /dev/null; then
        echo "OpenCode CLI not found in PATH"
        echo ""
        echo "OpenAgents Control is installed at: $INSTALL_DIR"
        echo "To use it, add the following to your shell config:"
        echo ""
        echo "  export OPENCODE_INSTALL_DIR=\"\\$INSTALL_DIR\""
        echo "  export PATH=\"\\$PATH:\\$OPENCODE_INSTALL_DIR/commands:\\$OPENCODE_INSTALL_DIR/tools\""
        echo ""
        echo "Or install OpenCode CLI from: https://opencode.ai/docs"
        exit 1
      fi

      exec opencode "\\$@"
      'EOF'

      chmod +x /usr/local/bin/opencode-wrapper

      echo "OpenAgents Control enabled at: $INSTALL_DIR"
      echo "Wrapper script created: /usr/local/bin/opencode-wrapper"
      echo ""
      echo "To use OpenCode agents with OpenAgents Control:"
      echo "  opencode-wrapper --agent openagent"
      echo "  opencode-wrapper --agent opencoder"
      echo ""
    '';

    # Create systemd service for auto-update (if enabled)
    systemd.services = lib.mkIf config.services.openagents-control.autoUpdate {
      openagents-control-update = {
        description = "OpenAgents Control Auto-Update Service";
        after = ["network-online.target"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = "/etc/opencode-update.sh";
          User = "root";
        };

        # Run update once per day
        timer = {
          description = "Daily OpenAgents Control Update";
          OnCalendar = "daily";
          Persistent = true;
          Unit = "openagents-control-update.service";
        };
      };
    };
  };
}
