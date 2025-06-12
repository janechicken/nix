{ config, inputs, pkgs, lib, ... }:
{
  home.packages = with pkgs;[
    (prismlauncher.override {
      jdks = [
        jdk23
        jdk
      ];
    })
  ];
}
