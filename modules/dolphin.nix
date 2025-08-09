{ configs, inputs, pkgs, lib, ...}:
{
  home.packages = with pkgs; [ dolphin-emu ];
}
