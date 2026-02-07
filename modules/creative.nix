{ config, inputs, pkgs, lib, ...}:
{
  home.packages = [ pkgs.kdePackages.kdenlive pkgs.inkscape ];
}

