{ config, lib, pkgs, ... }:

let
  cfg = config.services.hermes;
  user = "j_kro";
  hermesHome = "/home/${user}/.hermes";

  # Build activation script as a derivation
  activationScript = pkgs.writeShellScript "hermes-activation" ''
    set -euo pipefail

    # ── Profiles: SOUL.md per profile ──────────────────────
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: p: ''
      mkdir -p ${hermesHome}/profiles/${name}
      cat > ${hermesHome}/profiles/${name}/SOUL.md << 'SOUL_EOF'
${p.soul}
SOUL_EOF
      chown ${user}:users ${hermesHome}/profiles/${name}/SOUL.md
    '') cfg.profiles)}

    # ── Skills: SKILL.md per skill ─────────────────────────
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: s: ''
      mkdir -p ${hermesHome}/skills/${name}
      cat > ${hermesHome}/skills/${name}/SKILL.md << 'SKILL_EOF'
${s.content}
SKILL_EOF
      chown -R ${user}:users ${hermesHome}/skills/${name}
    '') cfg.skills)}

    # ── Bundles ────────────────────────────────────────────
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: b: ''
      mkdir -p ${hermesHome}/skill-bundles
      cat > ${hermesHome}/skill-bundles/${name}.yaml << 'BUNDLE_EOF'
name: /${name}
skills:
${lib.concatStringsSep "\n" (map (s: "  - " + s) b.skills)}
description: ${b.description}
BUNDLE_EOF
      chown ${user}:users ${hermesHome}/skill-bundles/${name}.yaml
    '') cfg.bundles)}

    # ── Taps ───────────────────────────────────────────────
    ${lib.concatStringsSep "\n" (map (tap: ''
      ${pkgs.su}/bin/su - ${user} -c "hermes skills tap add ${tap}" 2>/dev/null || true
    '') cfg.taps)}

    # ── Profile descriptions for kanban ────────────────────
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: p: lib.optionalString (p.description != "") ''
      ${pkgs.su}/bin/su - ${user} -c "hermes profile describe ${name} --text '${p.description}'" 2>/dev/null || true
    '') cfg.profiles)}
  '';

in {
  system.activationScripts.hermes-spoc = {
    deps = [ "users" "groups" ];
    text = builtins.readFile activationScript;
  };
}
