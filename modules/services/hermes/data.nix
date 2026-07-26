# Hermes Declarative Data — profiles, skills, bundles
# Generated from ~/.hermes/ state on 2026-07-23.
# EDIT THE NIX SOURCE, not the runtime ~/.hermes/ files.
# Then `colmena deploy` overwrites ~/.hermes/ to match.
{
  lib,
  pkgs,
  ...
}: let
  readSkill = name: builtins.readFile ./skills/${name}.skill.md;
  readSoul = name: builtins.readFile ./profiles/${name}.soul.md;
in {
  services.hermes = {
    enable = true;

    taps = [
      "mattpocock/skills"
      "reverb256/hermes-infra-skills"
    ];

    profiles = {
      ops = {
        soul = readSoul "ops";
        skills = [
          "nixos-cluster-ops"
          "nixos-declarative-only"
          "gpu-mining-operations"
          "homelab-ssh-probing"
          "deployment-debugger"
          "miner-audit"
          "oom-defense"
          "drift-cleanup"
          "gha-runner-unstick"
          "zram-sizing"
          "nexus-gha-token"
        ];
        description = "Infrastructure operations — OOM, drift, runners, mining, secrets, NixOS cluster fixes";
      };
      researcher = {
        soul = readSoul "researcher";
        skills = [
          "firecrawl-deep-research"
          "research"
          "domain-modeling"
          "handoff"
          "nixos-ssh"
        ];
        description = "Deep research and synthesis — literature, domain modeling, reports, cited findings";
      };
      analyst = {
        soul = readSoul "analyst";
        skills = [
          "research"
          "domain-modeling"
          "firecrawl-deep-research"
          "humanizer"
          "xlsx"
          "ocr-and-documents"
          "handoff"
        ];
        description = "Data and systems analysis — log/metric analysis, config comparison, pattern identification";
      };
      backend-eng = {
        soul = readSoul "backend-eng";
        skills = [
          "tdd"
          "test-driven-development"
          "code-review"
          "codebase-design"
          "systematic-debugging"
          "prototype"
          "nixos-ssh"
          "pino-structured-logging"
          "integration-audit"
        ];
        description = "Backend API development — TypeScript, Python, Rust services, databases, MCP servers";
      };
      frontend-eng = {
        soul = readSoul "frontend-eng";
        skills = [
          "tdd"
          "code-review"
          "codebase-design"
          "web-framework-migration"
          "prototype"
          "bilingual-i18n"
          "design-cohesion-audit"
          "web-structural-audit"
          "webmcp-implementation"
          "animation-vocabulary"
        ];
        description = "Frontend and portal development — Astro, design systems, bilingual UI, WebMCP";
      };
      writer = {
        soul = readSoul "writer";
        skills = [
          "humanizer"
          "handoff"
          "writing-great-skills"
          "docx"
          "xlsx"
          "pdf"
          "powerpoint"
          "ocr-and-documents"
          "obsidian"
          "youtube-content"
        ];
        description = "Technical writing — docs, runbooks, specs, ADRs, slide decks, humanized content";
      };
    };

    default = {
      soul = readSoul "default";
      skills = [
        "nixos-cluster-ops"
        "nixos-declarative-only"
        "deployment-debugger"
        "user-interaction-patterns"
      ];
      description = "General infrastructure and MapleSpike operations";
    };

    bundles = {
      planning = {
        skills = ["grill-me" "to-spec" "to-tickets"];
        description = "Requirement alignment -> spec -> tickets";
      };
      infra-ops = {
        skills = ["nixos-cluster-ops" "nixos-declarative-only" "miner-audit" "homelab-ssh-probing"];
        description = "Infrastructure operations — OOM, drift, runners";
      };
      maplespike-dev = {
        skills = ["bilingual-i18n" "spec-driven-development" "maplespike-deployment-audit"];
        description = "MapleSpike development workflow";
      };
    };

    gateway = {
      multiplexProfiles = true;
      profileRoutes = {
        ops-channel = {
          platform = "telegram";
          chatId = "1384182343";
          profile = "ops";
        };
      };
    };

    skills = {
      oom-defense = {
        content = readSkill "oom-defense";
        category = "infrastructure";
      };
      drift-cleanup = {
        content = readSkill "drift-cleanup";
        category = "infrastructure";
      };
      gha-runner-unstick = {
        content = readSkill "gha-runner-unstick";
        category = "infrastructure";
      };
      nexus-gha-token = {
        content = readSkill "nexus-gha-token";
        category = "infrastructure";
      };
      zram-sizing = {
        content = readSkill "zram-sizing";
        category = "infrastructure";
      };
      secretspec-checkpoint = {
        content = readSkill "secretspec-checkpoint";
        category = "infrastructure";
      };
      daily-oom-audit = {
        content = readSkill "daily-oom-audit";
        category = "infrastructure";
      };
      weekly-drift-scan = {
        content = readSkill "weekly-drift-scan";
        category = "infrastructure";
      };
      user-interaction-patterns = {
        content = readSkill "user-interaction-patterns";
        category = "communication";
      };
    };
  };
}
