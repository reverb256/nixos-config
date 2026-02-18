{
  config,
  lib,
  ...
}: let
  cfg = config.services.opencode;
in {
  options.services.opencode = {
    enable = lib.mkEnableOption "Enable OpenCode configuration";

    # Main models
    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "zai-coding-plan/glm-4.7";
      description = "Default model for OpenCode agents (GLM-4.7)";
    };

    quickModel = lib.mkOption {
      type = lib.types.str;
      default = "zai-coding-plan/glm-4.5-air";
      description = "Model for quick/light tasks (GLM-4.5-Air)";
    };

    visionModel = lib.mkOption {
      type = lib.types.str;
      default = "zai-coding-plan/glm-4.6v";
      description = "Model for vision/multimodal tasks (GLM-4.6V)";
    };

    # Agent model mappings (extensible)
    agents = lib.mkOption {
      type = lib.types.attrs;
      default = {
        sisyphus = cfg.defaultModel;
        librarian = cfg.defaultModel;
        explore = cfg.quickModel;
        oracle = cfg.defaultModel;
        "frontend-ui-ux-engineer" = cfg.defaultModel;
        "document-writer" = cfg.defaultModel;
        "multimodal-looker" = cfg.visionModel;
      };
      description = "Agent-specific model mappings (extensible)";
    };

    # Category model mappings (extensible)
    categories = lib.mkOption {
      type = lib.types.attrs;
      default = {
        quick = {
          model = cfg.quickModel;
          description = "Light, fast tasks using GLM-4.5-Air";
        };
        "visual-engineering" = {
          model = cfg.visionModel;
          description = "Frontend, UI/UX, design, styling, animation - uses vision model GLM-4.6V";
        };
        writing = {
          model = cfg.defaultModel;
          description = "Documentation, prose, technical writing";
        };
        ultrabrain = {
          model = cfg.defaultModel;
          description = "Deep logical reasoning, complex architecture decisions requiring extensive analysis";
        };
        "unspecified-high" = {
          model = cfg.defaultModel;
          description = "Tasks that don't fit other categories, high effort required";
        };
        "unspecified-low" = {
          model = cfg.defaultModel;
          description = "Tasks that don't fit other categories, low effort required";
        };
        artistry = {
          model = cfg.defaultModel;
          description = "Highly creative/artistic tasks, novel ideas";
        };
      };
      description = "Category-specific model mappings (extensible)";
    };

    # LSP server configurations (extensible)
    lsp = lib.mkOption {
      type = lib.types.attrs;
      default = {
        typescript = {
          command = ["typescript-language-server" "--stdio"];
          extensions = [".ts" ".tsx" ".js" ".jsx" ".mjs" ".cjs"];
        };
        basedpyright = {
          command = ["basedpyright-langserver" "--stdio"];
          extensions = [".py" ".pyw" ".pyi"];
        };
        gopls = {
          command = ["gopls"];
          extensions = [".go"];
        };
        "ruby-lsp" = {
          command = ["ruby-lsp"];
          extensions = [".rb" ".erb"];
        };
        vue = {
          command = ["vue-language-server" "--stdio"];
          extensions = [".vue"];
        };
        biome = {
          command = ["biome" "lsp-proxy"];
          extensions = [".js" ".ts" ".jsx" ".tsx" ".json"];
        };
      };
      description = "LSP server configurations (extensible)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Environment variables for OpenCode (system-wide)
    environment.sessionVariables = {
      OPENCODE_MCP_SCHEMA_FIX = "1";
      OPENCODE_TOOL_STRUCTURED_OUTPUT = "1";
      OPENCODE_PATH_FIX = "1";
    };

    # Ensure config directories exist and set up config files
    systemd.tmpfiles.rules = [
      # Create config directories for j_kro
      "d /home/j_kro/.config 0755 j_kro users -"
      "d /home/j_kro/.config/opencode 0755 j_kro users -"
      # Create config directories for root
      "d /root/.config 0755 root root -"
      "d /root/.config/opencode 0755 root root -"
    ];

    # Write opencode.json configuration using systemd activation
    system.activationScripts.opencodeConfig = ''
      # Ensure directories exist
      mkdir -p /home/j_kro/.config/opencode
      mkdir -p /root/.config/opencode

      # Generate opencode.json
      cat > /home/j_kro/.config/opencode/opencode.json <<EOF
      ${builtins.toJSON {
        plugin = ["oh-my-opencode"];
        model = cfg.defaultModel;
        provider = {};
        agent = lib.mapAttrs (_: model: {inherit model;}) cfg.agents;
      }}
      EOF

      # Generate oh-my-opencode.json
      cat > /home/j_kro/.config/opencode/oh-my-opencode.json <<EOF
      ${builtins.toJSON {
        agents = lib.mapAttrs (_: model: {inherit model;}) cfg.agents;
        categories =
          lib.mapAttrs (_: cat: {
            inherit (cat) model;
            inherit (cat) description;
          })
          cfg.categories;
        inherit (cfg) lsp;
      }}
      EOF

      # Copy to root user
      cp /home/j_kro/.config/opencode/opencode.json /root/.config/opencode/opencode.json
      cp /home/j_kro/.config/opencode/oh-my-opencode.json /root/.config/opencode/oh-my-opencode.json

      # Set proper ownership and permissions
      chown -R j_kro:users /home/j_kro/.config/opencode
      chmod 755 /home/j_kro/.config
      chmod 755 /home/j_kro/.config/opencode
      chmod 644 /home/j_kro/.config/opencode/*.json

      chown -R root:root /root/.config/opencode
      chmod 755 /root/.config
      chmod 755 /root/.config/opencode
      chmod 644 /root/.config/opencode/*.json
    '';

    # Sync configuration to other cluster nodes
    system.activationScripts.opencodeSync = lib.mkAfter ''
      # Only run on zephyr (main node)
      if [ "$(hostname)" = "zephyr" ]; then
        echo "Syncing opencode configuration to cluster nodes..."

        # Sync to forge
        if ssh -o ConnectTimeout=5 j_kro@forge "test -d /home/j_kro/.config"; then
          scp -o ConnectTimeout=5 -q /home/j_kro/.config/opencode/*.json j_kro@forge:/home/j_kro/.config/opencode/
          ssh -o ConnectTimeout=5 j_kro@forge "sudo cp /home/j_kro/.config/opencode/*.json /root/.config/opencode/"
          echo "  ✓ forge synced"
        fi

        # Sync to nexus
        if ssh -o ConnectTimeout=5 j_kro@nexus "test -d /home/j_kro/.config"; then
          scp -o ConnectTimeout=5 -q /home/j_kro/.config/opencode/*.json j_kro@nexus:/home/j_kro/.config/opencode/
          ssh -o ConnectTimeout=5 j_kro@nexus "sudo cp /home/j_kro/.config/opencode/*.json /root/.config/opencode/"
          echo "  ✓ nexus synced"
        fi

        # Sync to sentry
        if ssh -o ConnectTimeout=5 j_kro@sentry "test -d /home/j_kro/.config"; then
          scp -o ConnectTimeout=5 -q /home/j_kro/.config/opencode/*.json j_kro@sentry:/home/j_kro/.config/opencode/
          ssh -o ConnectTimeout=5 j_kro@sentry "sudo cp /home/j_kro/.config/opencode/*.json /root/.config/opencode/"
          echo "  ✓ sentry synced"
        fi

        echo "  ✓ opencode configuration synced to all nodes"
      fi
    '';
  };
}
