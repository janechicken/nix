{ pkgs, ... }:

{
  home.packages = with pkgs; [
    mumble
    gajim
  ];
}
