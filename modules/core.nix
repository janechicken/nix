{ config, inputs, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    nh
    unzip
    lsd
    wget
    fastfetch
    rage
  ];
  nixpkgs.config = { allowBroken = true; allowUnfree = true; };
}
