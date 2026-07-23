{ config, lib, pkgs, ... }:

let
  cfg = config.services.hermes;
  user = "j_kro";
  hermesHome = "/home/${user}/.hermes";
  inherit (lib) mkIf concatStringsSep;
in mkIf cfg.enable {

  # ── Profile files: SOUL.md per profile ────────────────────────
  system.activationScripts.hermes-profiles = lib.stringAfter ["users" "groups"] (
    let
      writeProfile = name: p: ''
        mkdir -p ${hermesHome}/profiles/${name}
        cat > ${hermesHome}/profiles/${name}/SOUL.md << 'SOUL_EOF'
${p.soul}
SOUL_EOF
        chown ${user}:users ${hermesHome}/profiles/${name}/SOUL.md
      '';
    in concatStringsSep "\n" (lib.mapAttrsToList writeProfile cfg.profiles)
  );

  # ── Skills: SKILL.md per skill ────────────────────────────────
  system.activationScripts.hermes-skills = lib.stringAfter ["hermes-profiles"] (
    let
      writeSkill = name: s: ''
        mkdir -p ${hermesHome}/skills/${name}
        cat > ${hermesHome}/skills/${name}/SKILL.md << 'SKILL_EOF'
${s.content}
SKILL_EOF
        chown -R ${user}:users ${hermesHome}/skills/${name}
      '';
    in concatStringsSep "\n" (lib.mapAttrsToList writeSkill cfg.skills)
  );

  # ── Bundles: YAML files in skill-bundles/ ─────────────────────
  system.activationScripts.hermes-bundles = lib.stringAfter ["hermes-skills"] (
    let
      writeBundle = name: b: ''
        mkdir -p ${hermesHome}/skill-bundles
        cat > ${hermesHome}/skill-bundles/${name}.yaml << 'BUNDLE_EOF'
name: ${name}
skills:
${concatStringsSep "\n" (map (s: "  - " + s) b.skills)}
description: ${b.description}
BUNDLE_EOF
        chown ${user}:users ${hermesHome}/skill-bundles/${name}.yaml
      '';
    in concatStringsSep "\n" (lib.mapAttrsToList writeBundle cfg.bundles)
  );

  # ── Gateway: write config.yaml multiplex + routes ─────────────
  system.activationScripts.hermes-gateway = lib.stringAfter ["hermes-bundles"] (
    let
      routeLines = lib.mapAttrsToList (name: r:
        "    - name: ${name}\n"
        + "      platform: ${r.platform}\n"
        + lib.optionalString (r.chatId != null) "      chat_id: \"${r.chatId}\"\n"
        + lib.optionalString (r.guildId != null) "      guild_id: \"${r.guildId}\"\n"
        + "      profile: ${r.profile}"
      ) cfg.gateway.profileRoutes;
    in ''
      if [ -f ${hermesHome}/config.yaml ]; then
        # Check if multiplex_profiles is already set
        if ! grep -q "multiplex_profiles: true" ${hermesHome}/config.yaml; then
          # Insert after "gateway:" line
          sed -i '/^gateway:/a\  multiplex_profiles: ${lib.boolToString cfg.gateway.multiplexProfiles}' ${hermesHome}/config.yaml
        fi
        # Insert profile_routes if not present
        if ! grep -q "profile_routes:" ${hermesHome}/config.yaml; then
          echo "" >> ${hermesHome}/config.yaml
          echo "  profile_routes:" >> ${hermesHome}/config.yaml
${lib.concatStringsSep "\n" routeLines}
        fi
        chown ${user}:users ${hermesHome}/config.yaml
      fi
    ''
  );

  # ── Taps: register skill sources ──────────────────────────────
  system.activationScripts.hermes-taps = lib.stringAfter ["hermes-gateway"] (
    let
      addTap = tap: ''
        ${pkgs.su}/bin/su - ${user} -c "hermes skills tap add ${tap} 2>/dev/null || true"
      '';
    in concatStringsSep "\n" (map addTap cfg.taps)
  );

  # ── Cron: register via hermes cron create ─────────────────────
  system.activationScripts.hermes-cron = lib.stringAfter ["hermes-taps"] (
    let
      addCron = name: c: ''
        ${pkgs.su}/bin/su - ${user} -c "hermes cron create '${c.schedule}' --name ${name} ${lib.optionalString (c.skill != null) "--skill " + c.skill} --deliver ${c.deliver} 2>/dev/null || true"
      '';
    in concatStringsSep "\n" (lib.mapAttrsToList addCron cfg.cron)
  );

  # ── Profile descriptions for kanban ──────────────────────────
  system.activationScripts.hermes-descriptions = lib.stringAfter ["hermes-cron"] (
    let
      setDesc = name: p: lib.optionalString (p.description != "") ''
        ${pkgs.su}/bin/su - ${user} -c "hermes profile describe ${name} --text '${p.description}' 2>/dev/null || true"
      '';
    in concatStringsSep "\n" (lib.mapAttrsToList setDesc cfg.profiles)
  );

  # Ensure activation scripts run in order
  system.activationScripts.hermes-all = lib.stringAfter [
    "hermes-profiles" "hermes-skills" "hermes-bundles"
    "hermes-gateway" "hermes-taps" "hermes-cron" "hermes-descriptions"
  ] "";
};
