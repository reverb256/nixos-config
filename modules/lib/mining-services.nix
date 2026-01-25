# Parameterized Mining Service Generator
{
  lib,
  pkgs,
  ...
}:
with lib; {
  # Parameterized XMRig service generator
  mkMiningService = name: config: {
    description = "XMRig CPU Mining Service (${name})";
    after = ["NetworkManager.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      User = "mining";
      Group = "mining";
      Slice = "mining.slice";
      ExecStart = "${pkgs.xmrig}/bin/xmrig -o ${config.pool} -u ${config.wallet} -t ${toString config.threads} --http-port 8081 --http-access-token ${config.httpToken} --http-restricted";
      Restart = "always";
      # Security hardening with necessary capabilities for MSR and Huge Pages
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictRealtime = true;
      LimitMEMLOCK = "4G";
      # Grant necessary capabilities for mining operations
      CapabilityBoundingSet = "CAP_SYS_ADMIN CAP_SYS_NICE";
      AmbientCapabilities = "CAP_SYS_ADMIN CAP_SYS_NICE";
    };
  };

  # Parameterized lolminer service generator
  mkLolMinerService = name: config: {
    description = "lolMiner GPU Mining Service (${name})";
    after = ["NetworkManager.service" "nvidia-persistenced.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      User = "mining";
      Group = "mining";
      Slice = "mining.slice";
      ExecStart = "${pkgs.lolminer}/bin/lolMiner --algo ${config.algorithm} --pool ${config.pool} --user ${config.user} --devices ${config.devices} --powerlimit ${toString config.powerLimit} --apiport ${toString config.apiPort} --mode b --tls 1";
      Restart = "always";
      # Path to NVIDIA drivers
      Environment = ["PATH=/run/current-system/sw/bin:$PATH" "LD_LIBRARY_PATH=/run/opengl-driver/lib:$LD_LIBRARY_PATH"];
      RestartSec = "30s";
      # Use dedicated mining user for security
    };
  };
}
