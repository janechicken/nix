{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:

{
  # Shared desktop bits for both hosts (Hyprland/Wayland). The AwesomeWM and
  # picom configs in dotfiles/ are kept for reference/X11 sessions only; the
  # live session is configured by modules/hyprland-home.nix.
  imports = [
    ./browsers.nix
    ./terminal.nix
    ./zsh.nix
    ./helix.nix
  ];

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
    pkgs.mpv-unwrapped
    pkgs.feh
    pkgs.xclip
    pkgs.copyq
    pkgs.easyeffects
    pkgs.pavucontrol
    inputs.nix-alien.packages.${pkgs.system}.nix-alien
    pkgs.yt-dlp-light
    pkgs.xbacklight
  ];

  # Screenshots live in modules/hyprland-home.nix (grim + slurp + satty, with
  # the satty config.toml and the Print/CTRL+Print/SHIFT+Print binds).
  home.file = {
    ".config/awesome" = {
      recursive = true;
      source = ../dotfiles/awesome;
    };
    ".config/rofi" = {
      recursive = true;
      source = ../dotfiles/rofi;
    };
    ".config/picom" = {
      recursive = true;
      source = ../dotfiles/picom;
    };
  };

  home.sessionVariables = {
    NH_FLAKE = "${config.home.homeDirectory}/nix";
  };

  # `$(nproc)` has to be evaluated by the shell at login, so it belongs in shell
  # init rather than in a plain session variable.
  home.sessionVariablesExtra = ''
    export MAKEFLAGS="-j$(nproc)"
  '';

  programs.rofi = {
    enable = true;
    plugins = [ pkgs.rofi-emoji ];
  };

  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
    };
  };

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita";
    };
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
