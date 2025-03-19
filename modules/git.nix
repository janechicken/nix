{ config, inputs, pkgs, lib, ... }:

{
  programs.git = {
  enable = true;
  userName = "jane chicken";
  userEmail = "jane@janechicken.com";
  };
  home.packages = with pkgs; [
    lazygit
  ];
}
