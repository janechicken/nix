{ configs, inputs, pkgs, lib, ... }:
{
  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;
    plugins = with pkgs.obs-studio-plugins; [
      obs-vkcapture
      obs-pipewire-audio-capture
      obs-multi-rtmp
    ];
  };
}
