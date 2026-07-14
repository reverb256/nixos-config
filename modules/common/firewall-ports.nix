{lib, ...}: {
  options.networking.ports = {
    monitoring = lib.mkOption {
      type = with lib.types; listOf port;
      default = [9100 9101 9102 9103 9104];
      description = "Prometheus monitoring stack ports";
    };

    mining = lib.mkOption {
      type = with lib.types; listOf port;
      default = [3333 14444];
      description = "Mining operation ports (XMRig, peakminer)";
    };

    ai = lib.mkOption {
      type = with lib.types; listOf port;
      default = [8080 11434];
      description = "AI inference gateway ports";
    };

    web = lib.mkOption {
      type = with lib.types; listOf port;
      default = [80 443];
      description = "Standard web ports (HTTP/HTTPS)";
    };

    fileSharing = lib.mkOption {
      type = with lib.types; listOf port;
      default = [22000 8384];
      description = "Syncthing file sharing ports";
    };
  };
}
