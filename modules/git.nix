{ config, inputs, pkgs, lib, ... }:

{
  programs.git = {
  enable = true;
  settings.user.name = "jane chicken";
  settings.user.email = "janechicken@purelymail.com";
  signing = {
    key = "78704CDE27D95D3E17065F23ACC77E2F16E02769";
    signByDefault = true;
  };
  };
  home.packages = with pkgs; [
    lazygit
  ];
}
