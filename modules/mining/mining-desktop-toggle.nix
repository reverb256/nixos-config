# Desktop icon for toggling the RTX 3090 lolMiner on Zephyr
# Scales the gpu-miner-zephyr K8s deployment between 0 (paused) and 1 (running)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  toggleScript = pkgs.writeShellScriptBin "toggle-3090-miner" ''
    set -euo pipefail

    DEPLOY="gpu-miner-zephyr"
    NS="mining"
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

    CURRENT=$(${lib.getExe pkgs.kubectl} get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

    if [ "$CURRENT" = "0" ]; then
      ${lib.getExe pkgs.kubectl} scale deploy "$DEPLOY" -n "$NS" --replicas=1
      ${lib.getExe pkgs.libnotify} -i media-playback-start -u normal "⛏ Mining resumed" "RTX 3090 lolMiner started"
    else
      ${lib.getExe pkgs.kubectl} scale deploy "$DEPLOY" -n "$NS" --replicas=0
      ${lib.getExe pkgs.libnotify} -i media-playback-pause -u normal "⏸ Mining paused" "RTX 3090 lolMiner stopped"
    fi
  '';

  statusScript = pkgs.writeShellScriptBin "3090-miner-status" ''
    set -euo pipefail
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    CURRENT=$(${lib.getExe pkgs.kubectl} get deploy gpu-miner-zephyr -n mining -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [ "$CURRENT" = "0" ]; then
      echo "paused"
    else
      echo "running"
    fi
  '';

  desktopEntry = pkgs.makeDesktopItem {
    desktopName = "Toggle 3090 Miner";
    name = "toggle-3090-miner";
    comment = "Pause/resume lolMiner on RTX 3090";
    exec = "${toggleScript}/bin/toggle-3090-miner";
    icon = "video-display";
    terminal = false;
    type = "Application";
    categories = [
      "System"
      "Utility"
    ];
  };
in
{
  # Only install on zephyr (the machine with the 3090)
  config = lib.mkIf (config.networking.hostName == "zephyr") {
    environment.systemPackages = [
      toggleScript
      statusScript
      desktopEntry
    ];

    # Install desktop entry system-wide for all users
    environment.pathsToLink = [ "/share/applications" ];
  };
}
