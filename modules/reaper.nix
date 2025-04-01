{ config, inputs, pkgs, lib, ... }:
let
     mypkgs = import (builtins.fetchTree {
      type = "github";
      owner = "nixos";
      repo = "nixpkgs";
      rev = "c792c60b8a97daa7efe41a6e4954497ae410e0c1";

     }) { inherit (pkgs) system; };

    myPkg = mypkgs.wineWowPackages.unstable;
  in
 {
  environment.systemPackages = with pkgs; [
    reaper
    (yabridge.override { wine = myPkg; })
    (yabridgectl.override { wine = myPkg; })
    lsp-plugins
  ];
}
