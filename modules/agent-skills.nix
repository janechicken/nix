{ config, pkgs, lib, inputs, ... }:

let
  inherit (lib) mkIf mapAttrsToList listToAttrs;

  # Skills enabled in the bundle that we want to expose to Hermes
  hermesSkills = [
    "ctf-ai-ml" "ctf-crypto" "ctf-forensics" "ctf-malware"
    "ctf-misc" "ctf-osint" "ctf-pwn" "ctf-reverse"
    "ctf-web" "ctf-writeup" "rust-skills" "solve-challenge"
    "superman"
  ];

  # Build home.file entries linking each skill from the bundle into Hermes
  hermesSkillLinks = hermesSkills:
    listToAttrs (map (skill: {
      name = ".hermes/skills/${skill}";
      value = {
        source = "${toString config.programs.agent-skills.bundlePath}/${skill}";
        recursive = false;
        force = true;
      };
    }) hermesSkills);
in {
  imports = [ inputs.agent-skills-nix.homeManagerModules.default ];

  programs.agent-skills = {
    enable = true;
    sources = {
      ctf-skills = {
        input = "ctf-skills";
        subdir = ".";
      };
      local = {
        path = ../skills;
        subdir = ".";
        idPrefix = "local";
        filter.maxDepth = 1;
      };
      rust-skills = {
        path = pkgs.runCommandLocal "rust-skills-clean" {} ''
          mkdir -p $out
          cp -r ${inputs.rust-skills}/. $out
          chmod -R u+w $out
          rm -f $out/AGENTS.md $out/CLAUDE.md
        '';
      };
    };
    skills = {
      enable = [
        "ctf-ai-ml" "ctf-crypto" "ctf-forensics" "ctf-malware"
        "ctf-misc" "ctf-osint" "ctf-pwn" "ctf-reverse"
        "ctf-web" "ctf-writeup" "rust-skills"
      ];
      enableAll = [ ];
      explicit = {
        solve-challenge = {
          from = "local";
        };
        superman = {
          from = "local";
        };
      };
    };
    targets = {
      opencode.enable = true;
      pi = {
        dest = "$HOME/.pi/agent/skills";
        enable = true;
      };
    };
  };

  # Link skills into Hermes Agent skills directory
  home.file = mkIf config.programs.agent-skills.enable
    (hermesSkillLinks hermesSkills);
}
