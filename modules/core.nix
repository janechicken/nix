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
    # wineWow64Packages.yabridge
    wineWow64Packages.staging
    winetricks
    home-manager
    zenity
    appimage-run
    p7zip-rar
    qrrs
  ];
  boot.loader.grub.configurationLimit = 3;

  nixpkgs.config = {
    allowBroken = true;
    allowUnfree = true;
  };
}
