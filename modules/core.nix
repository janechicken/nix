{ config, inputs, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    nh
    unzip
    lsd
    wget
    fastfetch
    rage
    uutils-coreutils-noprefix
    bat
    btop
    killall
    wine
    wine-staging
    winetricks
  ];
  nixpkgs.config = { allowBroken = true; allowUnfree = true; };
}
