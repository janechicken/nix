{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

{
  imports = [
    ../../modules/desktop.nix
    ../../modules/hyprland-home.nix
    ../../modules/creative.nix
    ../../modules/git.nix
    ../../modules/spotify.nix
    ../../modules/discord.nix
    ../../modules/crypto.nix
    ../../modules/hex.nix
    ../../modules/gpg.nix
    ../../modules/u2f-keys.nix
    ../../modules/ssh.nix
    ../../modules/dolphin.nix
    ../../modules/chess.nix
    ../../modules/zed.nix
    ../../modules/pi.nix
    ../../modules/t3code.nix
    ../../modules/antigravity.nix
    ../../modules/messaging.nix
    ../../modules/syncthing.nix
    ../../modules/obsidian.nix
    ../../modules/renix.nix
    ../../secrets/home-secrets.nix
  ];

  home.username = "jane";
  home.homeDirectory = "/home/jane";

  nixpkgs.config.permittedInsecurePackages = [
    "python3.13-ecdsa-0.19.2"
    "python3.14-ecdsa-0.19.2"
  ];

  home.stateVersion = "25.05";

  # Hyprland: 14" 1920x1200@60 OLED eDP @ 125% (previous 120 DPI X11 config),
  # 60Hz panel so VRR stays off, laptop features on.
  custom.hyprland = {
    monitors = [
      {
        output = "eDP-1";
        mode = "1920x1200@60";
        position = "0x0";
        scale = 1.25;
      }
    ];
    isLaptop = true;
    batteryName = "qcom-battmgr-bat";
    # The Mahua DTB exposes the lid switch as the "gpio-keys" input device
    # (`hyprctl devices` -> Switches), not the usual "Lid Switch".
    lidSwitchName = "gpio-keys";
    vrr = 0;
  };

  home.packages = with pkgs; [
    # `git push` over ssh needs the client binary; don't rely on it coming in
    # transitively.
    openssh
  ];

  # modules/git.nix signs every commit by default, but this host has no GPG key
  # provisioned (sops.secrets."gpg_key" is still commented out in
  # secrets/sops-nix.nix), so every `git commit` would fail. jane-pc has the key
  # and keeps signing on.
  programs.git.signing.signByDefault = lib.mkForce false;

  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    setSessionVariables = false;
  };

  programs.home-manager.enable = true;
}
