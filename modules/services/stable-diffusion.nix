{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.services.stable-diffusion;
  sdPort = toString cfg.port;
  sdUser = "stable-diffusion";
  sdGroup = "stable-diffusion";
in {
  options.services.stable-diffusion = {
    enable = lib.mkEnableOption "Stable Diffusion WebUI service";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.stable-diffusion-stability-ai;
      defaultText = lib.literalExample "pkgs.stable-diffusion-stability-ai";
      description = "Stable Diffusion package to use.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7860;
      description = "Port on which Stable Diffusion WebUI will listen.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host on which Stable Diffusion WebUI will listen.";
    };

    modelsDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/stable-diffusion/models";
      description = "Directory for Stable Diffusion models.";
    };

    cmdOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["--xformers" "--opt-split-attention" "--medvram"];
      description = "Additional command-line options for Stable Diffusion WebUI.";
    };

    enableApi = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable API access to Stable Diffusion WebUI.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall for Stable Diffusion WebUI port.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-start the Stable Diffusion WebUI service.";
    };

    gpuType = lib.mkOption {
      type = lib.types.enum ["cuda" "rocm" "cpu"];
      default = "cuda";
      description = "Type of GPU to use for acceleration.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create stable-diffusion user and group
    users.users = lib.optionalAttrs (!lib.hasAttr "stable-diffusion" config.users.users) {
      ${sdUser} = {
        description = "Stable Diffusion WebUI user";
        isSystemUser = true;
        group = sdGroup;
        extraGroups = ["video" "render"];
      };
    };

    users.groups = lib.optionalAttrs (!lib.hasAttr "stable-diffusion" config.users.groups) {
      ${sdGroup} = {};
    };

    # Firewall configuration
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port];
    };

    # Stable Diffusion WebUI service
    systemd.services.stable-diffusion = {
      description = "Stable Diffusion WebUI service";
      after = ["network.target"];
      wantedBy = lib.optionals cfg.autoStart ["multi-user.target"];

      preStart = lib.mkBefore ''
        # Create models directory if it doesn't exist
        mkdir -p ${cfg.modelsDir}
        chown ${sdUser}:${sdGroup} ${cfg.modelsDir}
        
        # Create cache directory if it doesn't exist
        mkdir -p /var/lib/stable-diffusion/cache
        chown ${sdUser}:${sdGroup} /var/lib/stable-diffusion/cache
      '';

      serviceConfig = {
        Type = "simple";
        User = sdUser;
        Group = sdGroup;
        ExecStart = lib.concatStringsSep " " ([
            "${cfg.package}/bin/python"
            "${cfg.package}/share/stable-diffusion-stability-ai/webui.py"
            "--port ${sdPort}"
            "--listen"
            "--disable-safe-unpickle"
            "--no-half-vae"
            "--xformers"
          ]
          ++ lib.optional cfg.enableApi "--api"
          ++ cfg.cmdOptions);
        Restart = "always";
        RestartSec = 10;
        Environment = [
          "PYTHONPATH=${cfg.package}/share/stable-diffusion-stability-ai"
          "CUDA_VISIBLE_DEVICES=0"  # Use first GPU
          "HF_HOME=/var/lib/stable-diffusion/cache"
          "TRANSFORMERS_CACHE=/var/lib/stable-diffusion/cache/transformers"
          "TORCH_HOME=/var/lib/stable-diffusion/cache/torch"
        ];
        WorkingDirectory = "/var/lib/stable-diffusion";
        StateDirectory = "stable-diffusion";
        LogsDirectory = "stable-diffusion";
        GPUDevicePolicy = "auto";  # Allow access to GPU devices
      };
    };

    environment.systemPackages = [cfg.package];
  };
}