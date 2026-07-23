{ config, lib, pkgs, ... }:

let
  cfg = config.services.hermes;
  user = "j_kro";
  hermesHome = "/home/${user}/.hermes";
  inherit (lib) mkIf concatStringsSep optionalString;

  # Build activation script as a derivation
  activationScript = pkgs.writeShellScript "hermes-activation" ''
    set -euo pipefail

    # Profiles: SOUL.md per profile
    ${concatStringsSep "\n" (lib.mapAttrsToList (name: p: ''
      mkdir -p ${hermesHome}/profiles/${name}
      cat > ${hermesHome}/profiles/${name}/SOUL.md << 'SOUL_EOF'
${p.soul}
SOUL_EOF
      chown ${user}:users ${hermesHome}/profiles/${name}/SOUL.md
    '') cfg.profiles)}

    # Default profile: also write root SOUL.md
    ${optionalString (cfg.profiles ? default) ''
      mkdir -p ${hermesHome}
      cat > ${hermesHome}/SOUL.md << 'SOUL_EOF'
${cfg.profiles.default.soul}
SOUL_EOF
      chown ${user}:users ${hermesHome}/SOUL.md
    ''}

    # Skills: SKILL.md per skill
    ${concatStringsSep "\n" (lib.mapAttrsToList (name: s: ''
      mkdir -p ${hermesHome}/skills/${name}
      cat > ${hermesHome}/skills/${name}/SKILL.md << 'SKILL_EOF'
${s.content}
SKILL_EOF
      chown -R ${user}:users ${hermesHome}/skills/${name}
    '') cfg.skills)}

    # Bundles
    ${concatStringsSep "\n" (lib.mapAttrsToList (name: b: let
      skillLines = concatStringsSep "\n" (map (s: "  - " + s) b.skills);
    in ''
      mkdir -p ${hermesHome}/skill-bundles
      cat > ${hermesHome}/skill-bundles/${name}.yaml << 'BUNDLE_EOF'
name: /${name}
skills:
${skillLines}
description: ${b.description}
BUNDLE_EOF
      chown ${user}:users ${hermesHome}/skill-bundles/${name}.yaml
    '') cfg.bundles)}

    # Taps
    ${concatStringsSep "\n" (map (tap: ''
      ${pkgs.su}/bin/su - ${user} -c "hermes skills tap add ${tap}" 2>/dev/null || true
    '') cfg.taps)}

    # Profile descriptions for kanban
    ${concatStringsSep "\n" (lib.mapAttrsToList (name: p: optionalString (p.description != "") ''
      ${pkgs.su}/bin/su - ${user} -c "hermes profile describe ${name} --text '${p.description}'" 2>/dev/null || true
    '') cfg.profiles)}
  '';

in {
  system.activationScripts.hermes-spoc = {
    deps = [ "users" "groups" ];
    text = builtins.readFile activationScript;
  };
}
