{pkgs, ...}: {
  imports = [
    ./modules/ai-agent-smart-fish.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.openssh.enable = true;
  services.openssh.permitRootLogin = "yes";

  users.users.vmuser = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.fish;
    initialPassword = "test123";
  };

  networking.hostName = "ai-fish-test";
  networking.firewall.enable = false;

  environment.systemPackages = with pkgs; [
    opencode
    git
    curl
    wget
  ];

  programs.fish.enable = true;
}
