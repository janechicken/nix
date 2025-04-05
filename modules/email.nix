{ config, input, pkgs, lib, ... }: {
  home.packages = with pkgs; [ mailspring ];
}
