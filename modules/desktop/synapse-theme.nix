{
  config,
  lib,
  ...
}: let
  # Only generate Synapse theme if Stylix is enabled
  hasStylix = config.stylix.enable or false;
  colors =
    if hasStylix
    then config.stylix.base16Scheme
    else {};
  base24 = config.base24 or {};
in {
  # Generate Synapse theme config at build time
  environment.etc."synapse/theme.json".text = lib.mkIf hasStylix (builtins.toJSON {
    name = "Synapse Theme";
    variant = "dark";
    colors = {
      # Base16 colors
      base00 = colors.base00 or "#171D23";
      base01 = colors.base01 or "#1D252C";
      base02 = colors.base02 or "#28323A";
      base03 = colors.base03 or "#526270";
      base04 = colors.base04 or "#B7C5D3";
      base05 = colors.base05 or "#D8E2EC";
      base06 = colors.base06 or "#F6F6F8";
      base07 = colors.base07 or "#FBFBFD";
      base08 = colors.base08 or "#D95468";
      base09 = colors.base09 or "#FF9E64";
      base0A = colors.base0A or "#EBBF83";
      base0B = colors.base0B or "#8BD49C";
      base0C = colors.base0C or "#70E1E8";
      base0D = colors.base0D or "#539AFC";
      base0E = colors.base0E or "#B62D65";
      base0F = colors.base0F or "#DD9D82";
      # Base24 bright colors
      base10 = base24.base10 or "#D95468";
      base11 = base24.base11 or "#8BD49C";
      base12 = base24.base12 or "#EBBF83";
      base13 = base24.base13 or "#539AFC";
      base14 = base24.base14 or "#B62D65";
      base15 = base24.base15 or "#70E1E8";
      base16 = base24.base16 or "#526270";
      base17 = base24.base17 or "#D8E2EC";
    };
  });
}
