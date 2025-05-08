{ config, inputs, pkgs, lib, ... }: {
  home.packages = with pkgs; [ imhex hexyl ];
}
