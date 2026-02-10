{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.security;
in {
  options.services.security = {
    enableKernelMitigations = mkOption {
      type = types.bool;
      default = true; # Enable by default for security
      description = "Enable kernel security mitigations (Spectre, Meltdown, etc.). Disabling improves performance but exposes to CPU vulnerabilities.";
    };
  };

  config = mkIf cfg.enableKernelMitigations {
    boot.kernelParams = filter (p:
      !builtins.elem p [
        "mitigations=off"
        "nospectre_v1"
        "nospectre_v2"
        "spectre_v2=off"
      ]) (config.boot.kernelParams or []);
  };
}
