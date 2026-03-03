{ pkgs, ... }:

{
  home.packages = with pkgs; [
    sops
    rage
    ssh-to-age
  ];
}
