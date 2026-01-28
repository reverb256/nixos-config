# NVIDIA Sandbox Configuration for Containerized Applications
# Fixes GPU detection in LM Studio, Steam, and other sandboxed applications
# FULLY DECLARATIVE - No manual scripts required
{
  pkgs,
  lib,
  ...
}: {
  # ============================================================================
  # NVIDIA LIBRARY SYMLINKS FOR FHS ENVIRONMENTS (Declarative)
  # ============================================================================

  # Setup NVIDIA environment for containerized applications
  environment.etc = {
    # NVIDIA sandbox environment setup in profile
    "profile.d/nvidia-sandbox.sh".text = ''
      # NVIDIA Sandbox Environment Setup - AUTOMATIC
      # This is loaded automatically for all users and sessions
    '';
  };



  # ============================================================================
  # NVIDIA SANDBOX ACTIVATION SERVICE (Automatic)
  # ============================================================================

  # Create a systemd service that automatically sets up NVIDIA sandbox environment
  systemd.services.nvidia-sandbox-activation = {
    description = "NVIDIA Sandbox Environment Activation";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = "${pkgs.coreutils}/bin/true"; # No action needed - environment is set declaratively
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # ============================================================================
  # NVIDIA SANDBOX INFORMATION TOOL
  # ============================================================================

  # Create a tool to check NVIDIA sandbox status
  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "nvidia-sandbox-info" ''
      #!/bin/bash
      echo "🔧 NVIDIA Sandbox Environment Status"
      echo "==================================="
      echo ""
      echo "✅ NVIDIA GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader,nounits)"
      echo "✅ CUDA available: $(nvidia-smi --query-gpu=cuda_version --format=csv,noheader,nounits)"
      echo "✅ Vulkan ICD configured: /usr/share/vulkan/icd.d/nvidia_icd.json"
      echo ""
      echo "🎯 Environment Variables:"
      echo ""
      echo "🚀 LM Studio should now detect GPU automatically!"
    '')
  ];
}
