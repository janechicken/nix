{ config, inputs, pkgs, lib, ... }:
 {
  environment.systemPackages = with pkgs; [
    reaper
    yabridge
    yabridgectl
    lsp-plugins
    qpwgraph
    qjackctl
  ];
}
