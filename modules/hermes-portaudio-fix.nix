# hermes-portaudio-fix.nix — Add PortAudio dependency for voice mode
{ config, pkgs, lib, ... }:

{
  # Override hermes-agent package to include PortAudio for sounddevice/voice mode
  nixpkgs.overlays = [
    (final: prev: {
      hermes-agent = prev.hermes-agent.overrideAttrs (old: {
        propagatedBuildInputs = (old.propagatedBuildInputs or []) ++ (with pkgs; [portaudio]);
        # Also ensure it's available at runtime
        runtimeDependencies = (old.runtimeDependencies or []) ++ (with pkgs; [portaudio]);
      });
    })
  ];

  # Also ensure PortAudio is available system-wide as fallback
  environment.systemPackages = with pkgs; [portaudio];
}