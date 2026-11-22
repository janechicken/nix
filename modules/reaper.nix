{ config, inputs, pkgs, lib, ... }:
{
  environment.systemPackages =
    (with pkgs; [
      reaper
      lsp-plugins
      qpwgraph
      qjackctl
    ])
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 (with pkgs; [
      yabridge
      yabridgectl
    ]);
}
