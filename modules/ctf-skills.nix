{ config, pkgs, inputs, lib, ... }:

let
  skillDirs = [
    "ctf-ai-ml" "ctf-crypto" "ctf-forensics" "ctf-malware"
    "ctf-misc" "ctf-osint" "ctf-pwn" "ctf-reverse"
    "ctf-web" "ctf-writeup" "solve-challenge"
  ];
in {
  home.file = builtins.listToAttrs (map (name: {
    name = ".config/opencode/skills/${name}";
    value.source = "${inputs.ctf-skills}/${name}";
  }) skillDirs);
}
