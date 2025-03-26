{ config, inputs, pkgs, lib, ... }:
{
  programs.helix = {
    enable = true;
    settings = {
      theme = "autumn_night";
      editor = {
        mouse = false;
        insert = "bar";
        normal = "block";
        select = "underline";
      };
    };
  };
}
