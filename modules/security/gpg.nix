{ config, lib, pkgs, ... }:
let
  cfg = config.security.gpg;
  inherit (lib) mkEnableOption mkIf;
in {
  options.security.gpg = {
    enable = mkEnableOption "GPG with git commit signing";
  };

  config = mkIf cfg.enable {
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = false;
      pinentryPackage = pkgs.pinentry-qt;
    };

    environment.systemPackages = with pkgs; [
      gnupg
      paperkey
      pgp-tools
    ];

    # Harden GPG config
    environment.etc."gnupg/gpg.conf" = {
      text = ''
        keyserver hkps://keys.openpgp.org
        personal-cipher-preferences AES256 AES192 AES
        personal-digest-preferences SHA512 SHA384 SHA256
        personal-compress-preferences ZLIB BZIP2 ZIP Uncompressed
        default-preference-list SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed
        cert-digest-algo SHA512
        s2k-digest-algo SHA512
        s2k-cipher-algo AES256
        charset utf-8
        fixed-list-mode
        no-comments
        no-emit-version
        keyid-format 0xlong
        list-options show-uid-validity
        verify-options show-uid-validity
        with-fingerprint
        require-compliance
      '';
      mode = "0444";
    };
  };
}
