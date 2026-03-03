{ config, inputs, pkgs, lib, system, ... }:

{
  # this assumes xorg and awesome are both already enabled in configuration.nix, this just copies the xinitrc and awesome config
  imports = [ ./browsers.nix ./terminal.nix ./zsh.nix ./helix.nix ];

  nixpkgs.config = {
    allowBroken = true;
    allowUnfree = true;
  };

  home.packages = [
    pkgs.bibata-cursors
    pkgs.gnome-tweaks
    pkgs.lxappearance
    pkgs.keepassxc
    pkgs.nemo
    pkgs.playerctl
    pkgs.mpv
    pkgs.feh
    pkgs.xclip
    pkgs.copyq
    pkgs.easyeffects
    pkgs.pavucontrol
    pkgs.flameshot
    inputs.nix-alien.packages."x86_64-linux".nix-alien
    pkgs.yt-dlp
  ];

  home.file = {
    ".config/awesome" = {
      recursive = true;
      source = ../dotfiles/awesome;
    };
    ".config/rofi" = {
      recursive = true;
      source = ../dotfiles/rofi;
    };
    ".xinitrc" = { source = ../dotfiles/.xinitrc; };
    ".config/picom" = {
      recursive = true;
      source = ../dotfiles/picom;
    };
  };

  home.sessionVariables = { MAKEFLAGS = "-j$(nproc)"; };

  programs.rofi = {
    enable = true;
    plugins = [ pkgs.rofi-emoji ];
  };

  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = { color-scheme = "prefer-dark"; };
    };
  };

  gtk = {
    enable = true;
    theme = { name = "Adwaita"; };
    cursorTheme = {
      name = "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
    };
    iconTheme = {
      name = "Papirus";
      package = pkgs.papirus-icon-theme;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk";
    style.name = "adwaita-dark";
  };

  home.pointerCursor = {
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    x11.enable = true;
    size = 20;
  };

  services.easyeffects.enable = true;
}
