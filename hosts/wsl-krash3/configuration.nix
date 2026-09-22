{ config, lib, pkgs, ... }:

{
  imports = [
    # nixos-wsl module is provided by the flake input (see flake.nix)
  ];

  wsl.enable = true;
  wsl.defaultUser = "j_kro";

  # Use Lix (drop-in Nix replacement) and enable flakes + nix-command
  nix.package = pkgs.lix;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Make NixOS authoritative over /etc/shadow so hashedPassword is enforced
  users.mutableUsers = false;

  # CLI tools: git + GitHub CLI (mirrors the Windows-host setup)
  environment.systemPackages = with pkgs; [
    git
    gh
  ];

  # j_kro user: same key as Windows host, password + key auth
  users.users.j_kro = {
    isNormalUser = true;
    description = "j_kro";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvekxGk1YR/eF8llVmNk3C59BtgB+9DNvxLy2WjPEyb j_kro@zephyr"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHZOSZbZdeSAJ7MB67hlzOq1MpDt3hiyqbOBG+9OYwYW krash@krash3"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJo8yKBnF95ImOUhhUFDJyJ9IpCS9U4CqUiEiQ/RW7rH j_kro@krash3-windows"
    ];
    hashedPassword = "$6$dubRSF4lW07y3V45$93ar8gboKj/f6wBWEb5B4IKet5UOb/5tOwHcA2cvGsnR02J/.CQqqMfhzKCFvXeEUb/GhaJRa4I7TVtOUswBj/";
  };

  # Passwordless sudo for wheel (matches NixOS-WSL default)
  security.sudo.wheelNeedsPassword = false;

  # SSH server on port 2222, key + password
  services.openssh = {
    enable = true;
    settings = {
      Port = 2222;
      PermitRootLogin = "no";
      PasswordAuthentication = true;
      PubkeyAuthentication = true;
      KbdInteractiveAuthentication = false;
    };
  };
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 2222 ];
  };

  system.stateVersion = "26.11";

  # k3s agent — krash3 node in the homelab cluster (added 2026-09-19).
  # Keeper part 1/2: this unit starts whenever the distro boots; the Windows
  # login task "NixOS-WSL-k3s-autostart" (part 2/2) boots the distro at logon.
  systemd.services.k3s-agent = {
    description = "k3s agent (krash3 WSL2 node)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "notify";
      ExecStart = "/home/j_kro/.local/bin/k3s agent --server https://10.1.1.120:6443 --token-file /root/k3s-token --node-name krash3 --node-ip 10.1.1.150";
      Restart = "always";
      RestartSec = "5s";
      KillMode = "process";
      Delegate = true;
      LimitNOFILE = 1048576;
      LimitNPROC = "infinity";
      LimitCORE = "infinity";
      TasksMax = "infinity";
      TimeoutStartSec = "0";
    };
  };
  # --- Tailscale subnet router (added 2026-09-22) ---
  # Why: WSL2 mirrored networking drops HOST-originated traffic to pod IPs. Measured 2026-09-22:
  # pods reach each other in 2 ms and a krash3 pod reaches the internet fine, but a curl from
  # nexus/sentry/forge/zephyr to a krash3 pod times out (8.00 s) and tcpdump INSIDE the pod
  # captured nothing - the packet dies in the Windows/WSL layer before the VM. Calico
  # encapsulation cannot help (it only wraps pod-originated traffic), so this node advertises its
  # own Calico block instead: WireGuard crosses the WSL boundary fine, and the last hop happens
  # inside the VM where pod routing already works.
  services.tailscale = {
    enable = true;
    extraUpFlags = [
      "--advertise-routes=192.168.21.0/26"
      "--accept-dns=false"
      "--hostname=krash3"
    ];
  };
  # Kernel TUN mode is REQUIRED: userspace networking cannot act as a subnet router.
  # /dev/net/tun exists in this WSL kernel; ip_forward is already 1, pinned here for intent.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  # IPv6 forwarding: Tailscale warns "Subnet routes and exit nodes may not work correctly"
  # without it. Our advertised route is IPv4, but pin it so the warning is gone and IPv6
  # subnet routing stays possible.
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;
  # UDP GRO: tailscaled itself reports "UDP GRO forwarding is suboptimally configured on eth0".
  # This is its documented tune; throughput-only, but it is free and silences the warning.
  systemd.services.tailscale-udp-gro = {
    description = "Tune eth0 UDP GRO for Tailscale forwarding";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      ${pkgs.ethtool}/bin/ethtool -K eth0 rx-udp-gro-forwarding on rx-gro-list off || true
    '';
  };
}
