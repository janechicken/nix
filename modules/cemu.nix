 { config, inputs, pkgs, lib, ... }:
{
  home.packages = with pkgs;[cemu];
}
