{ pkgs, ... }:

{
  home.packages = with pkgs; [
    sops
    rage
    ssh-ssh-to-age
  ];
}
