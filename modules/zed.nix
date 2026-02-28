{ config, inputs, pkgs, lib, ... }:
{
  home.packages = [ pkgs.zed-editor ];
  home.file = {
    ".config/zed/themes/autumn-dark.json" = {
      source = ../dotfiles/zed/autumn-dark.json; 
    };
  };
}
