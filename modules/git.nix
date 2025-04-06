{ config, inputs, pkgs, lib, ... }:

{
  programs.git = {
  enable = true;
  userName = "jane chicken";
  userEmail = "janechicken@purelymail.com";
  };
  home.packages = with pkgs; [
    lazygit
  ];
}
