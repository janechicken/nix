{ inputs, pkgs, lib, ... }:

{
  programs.spotify-player = {
  enable = true;
  settings = {
    enable_notify = false;
    device = {
      volume = 90;
      name = "nixos";
      audio_cache = true;
      normalization = true;
      autoplay = false;
    };
  };
  };
}
