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
    ../../modules/creative.nix
    ../../modules/git.nix
    ../../modules/spotify.nix
    ../../modules/discord.nix
    ../../modules/crypto.nix
    ../../modules/hex.nix
    ../../modules/gpg.nix
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

  # Match Windows 125% display scaling (120 DPI on 14" 1920x1200 OLED)
  xresources.properties = {
    "Xft.dpi" = 120;
  };

  home.sessionVariables = {
    # Keeps Qt apps matched to 125% scaling on X11
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
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

  home.file = {
    ".xinitrc".text = ''
      #!/bin/bash
      export XDG_CURRENT_DESKTOP=Awesome
      export XDG_SESSION_DESKTOP=Awesome
      export XDG_SESSION_TYPE=x11

      # Apply 120 DPI (125% scaling) for Xft/Rofi/Kitty/Awesome
      [ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

      # kill startup apps
      killall picom 2>/dev/null || true
      picom &

      # Feed X env into systemd --user so portals/dbus activation see it.
      systemctl --user import-environment DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
      dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE

      # Pull up graphical-session.target (RefuseManualStart) for gnome portal.
      trap 'systemctl --user stop awesome-graphical-session.service' EXIT
      systemctl --user start awesome-graphical-session.service

      exec awesome
    '';
  };

  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    setSessionVariables = false;
  };

  programs.home-manager.enable = true;
}
