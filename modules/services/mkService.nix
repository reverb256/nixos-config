{
  lib,
  config,
  ...
}: let
  inherit (lib) mkEnableOption mkOption types mkIf;

  options.services.mkService = {
    description = "Helper for declaring services that auto-generate DNS, Caddy routes, and TLS SANs";
    default = {};
  };

  config.services.mkService = lib.mkIf (config.services.mkService.enable or false) ('
    # Import shared port refs
    ports = import ../modules/common/port-refs.nix;

    # Build Caddy route
    caddyRoute = serviceName + ''.lan {
      ${tls}
      encode zstd gzip
      handle /* {
        reverse_proxy $''${''} + ''backend' + ''} {
          ${proxyHeader}
        }
      }
    }'';

    # Build auth route (if needed)
    caddyAuthRoute = serviceName + ''.lan {
      ${tls}
      encode zstd gzip
      handle /* {
        basicauth admin admin
        reverse_proxy $''${''} + ''backend' + ''} {
          ${proxyHeader}
        }
      }
    }'';

    # Build rawBlock for cluster-services.nix pattern
    caddyRawBlock = serviceName + '' = {
      domain = "serviceName.lan";
      backend = $''${''} + ''ports.serviceName' + ''}' + '';
    }' + '''
      rawBlock = '''
      https://serviceName.lan {
        tls /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key
        encode zstd gzip
        handle /* {
          reverse_proxy $''${''} + ''ports.serviceName' + ''}' + '''
        }
      }
    }'';
  ''');

in {
  inherit (config) lib;
}
