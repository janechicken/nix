{ config, inputs, pkgs, lib, ... }:
{
  programs.i3lock = {
    enable = true;
    u2fSupport = true;
  };
}
