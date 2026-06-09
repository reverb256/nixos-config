{
  dockerTools,
  buildEnv,
  bash,
  coreutils,
  fish,
  git,
  opencode,
}:
# Fixed opencode image for kelos - recognizes nvidia and meta providers
dockerTools.buildImage {
  name = "opencode";
  tag = "v1.14.46-fixed";

  copyToRoot = buildEnv {
    name = "opencode-root";
    paths = [opencode bash coreutils fish git];
    pathsToLink = ["/bin" "/etc" "/lib" "/home/j_kro/.nix-profile"];
  };

  config = {
    Cmd = ["${bash}/bin/bash" "-c" "mkdir -p /home/j_kro/.opencode && tail -f /dev/null"];
    WorkingDir = "/home/j_kro";
    Env = [
      "HOME=/home/j_kro"
      "USER=j_kro"
      "PATH=/home/j_kro/.nix-profile/bin:/bin"
      "OPENCODE_CONFIG_DIR=/home/j_kro/.opencode"
      "SHELL=/bin/fish"
    ];
    Labels = {
      "org.opencontainers.image.title" = "OpenCode";
      "org.opencontainers.image.description" = "OpenCode AI coding assistant (Fixed for NVIDIA NIM)";
    };
  };

  # Override entrypoint to recognize nvidia and meta providers
  # This is the kelos_entrypoint.sh that gets mounted
  config.Entrypoint = ["/kelos_entrypoint.sh"];
}
