{ inputs, pkgs, lib, ... }:

{
  programs.git = {
  enable = true;
  userName = "jane chicken";
  userEmail = "jane@janechicken.com";
  };
}
