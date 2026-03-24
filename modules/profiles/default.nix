# modules/profiles/default.nix --- Profile system entry point
#
# Provides hardware, role, and network profiles for host composition
# Inspired by hlissner/dotfiles modules/profiles/default.nix
{...}: {
  imports = [
    ./hardware
    ./role
    ./network
    ./monitoring.nix
  ];

  # Note: Profile options are defined by their respective submodules:
  # - hardware/default.nix defines hardware.profiles.*
  # - role/default.nix defines profiles.role.*
  # - network/default.nix defines profiles.network.*
  # - monitoring.nix defines profiles.monitoring.*
}
