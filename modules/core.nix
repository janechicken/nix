{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    nh
    lsd
    wget
    fastfetch
    uutils-coreutils-noprefix
    procps
    (lib.meta.setPrio 11 toybox)
    bat
    btop
    wineWow64Packages.yabridge
    winetricks
    home-manager
    zenity
    appimage-run
    p7zip-rar
    qrrs
  ];

  nixpkgs.config = {
    allowBroken = true;
    allowUnfree = true;
  };
}
