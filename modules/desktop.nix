{ config, inputs, pkgs, lib, system, ... }:

{
  # this assumes xorg and awesome are both already enabled in configuration.nix, this just copies the xinitrc and awesome config
  imports = [ ./librewolf.nix ./zsh.nix ./helix.nix ];

  nixpkgs.config = {
    allowBroken = true;
    allowUnfree = true;
  };

  home.packages = [
    pkgs.bibata-cursors
    pkgs.kitty
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
    pkgs.brave
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

  programs.kitty = {
    enable = true;
    shellIntegration.enableZshIntegration = true;
    settings = {
      connfirm_os_window_close = 0;
      enable_audio_bell = false;
      # Colors for the terminal
      color0  = "#111111";  # Normal black
      color8  = "#444444";  # Bright black (greyish)

      color1  = "#F05E48";  # Normal red
      color9  = "#F57A69";  # Bright red

      color2  = "#99be70";  # Normal green
      color10 = "#B8D88D";  # Bright green

      color3  = "#FAD566";  # Normal yellow
      color11 = "#FDE18A";  # Bright yellow

      color4  = "#1f78d1";  # Normal blue
      color12 = "#61A8D9";  # Bright blue

      color5  = "#c75c97";  # Normal magenta
      color13 = "#D78BB3";  # Bright magenta

      color6  = "#86c1b9";  # Normal cyan
      color14 = "#A4D6C9";  # Bright cyan

      color7  = "#e8e8e8";  # Normal white (light grey)
      color15 = "#ffffff";  # Bright white (pure white)

      # Background, Foreground, and Cursor
      background            = "#111111";  # Background color
      foreground            = "#F3F2CC";  # Foreground (text) color
      cursor                = "#F3F2CC";  # Cursor color
      selection_background  = "#F3F2CC";  # Selection background
      selection_foreground  = "#111111";  # Selection text color
    };
  };

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
