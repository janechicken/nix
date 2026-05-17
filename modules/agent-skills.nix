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
      cybersec = {
        input = "cybersec-skills";
        subdir = "skills";
      };
    };
    skills = {
      enable = [
        "ctf-ai-ml" "ctf-crypto" "ctf-forensics" "ctf-malware"
        "ctf-misc" "ctf-osint" "ctf-pwn" "ctf-reverse"
        "ctf-web" "ctf-writeup"
      ];
      enableAll = [ "cybersec" ];
      explicit.solve-challenge = {
        from = "local";
      };
    };
    targets.opencode.enable = true;
  };
}
