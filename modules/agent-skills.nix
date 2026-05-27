{ config, pkgs, lib, inputs, ... }:
{
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
      explicit.solve-challenge = {
        from = "local";
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
}
