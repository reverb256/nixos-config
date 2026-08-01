{
  dockerTools,
  buildEnv,
  bash,
  coreutils,
  fish,
  git,
  opencode,
  # #309: parameterize the container-internal home so the image does not
  # hardcode /home/j_kro. Default preserves the current image layout.
  homeDir ? "/home/j_kro",
}:
dockerTools.buildImage {
  name = "opencode";
  tag = "nixos";
  copyToRoot = buildEnv {
    name = "opencode-root";
    paths = [
      opencode
      bash
      coreutils
      fish
      git
    ];
    pathsToLink = [
      "/bin"
      "/etc"
      "/lib"
      "${homeDir}/.nix-profile"
    ];
  };
  config = {
    Cmd = [
      "${bash}/bin/bash"
      "-c"
      "mkdir -p ${homeDir}/.opencode && tail -f /dev/null"
    ];
    WorkingDir = homeDir;
    Env = [
      "HOME=${homeDir}"
      "USER=j_kro"
      "PATH=${homeDir}/.nix-profile/bin:/bin"
      "OPENCODE_CONFIG_DIR=${homeDir}/.opencode"
      "SHELL=/bin/fish"
    ];
    Labels = {
      "org.opencontainers.image.title" = "OpenCode";
      "org.opencontainers.image.description" = "OpenCode AI coding assistant";
    };
  };
}
