{pkgs, ...}:
pkgs.dockerTools.buildLayeredImage {
  name = "xmrig-nixos";
  tag = "latest";
  contents = [
    pkgs.xmrig
    pkgs.bash
    pkgs.coreutils
  ];
  config = {
    Cmd = ["${pkgs.xmrig}/bin/xmrig"];
    Env = ["PATH=/bin"];
  };
}
