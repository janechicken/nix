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
    pkgs.flameshot
    inputs.nix-alien.packages.${pkgs.system}.nix-alien
    pkgs.yt-dlp-light
    pkgs.xbacklight
  ];

  # Flameshot 15 on Hyprland/Wayland. Verified against the installed 15.0.0
  # (src/utils/confighandler.cpp): capture goes through the xdg-desktop-portal
  # `org.freedesktop.portal.Screenshot` API, provided by
  # xdg-desktop-portal-hyprland (modules/hyprland.nix). Notes:
  #   - useX11LegacyScreenshot is X11-only (ignored on Wayland) and the old
  #     `useGrimAdapter` / `disabledGrimWarning` keys no longer exist at all:
  #     Flameshot 15 has no grim backend (its nixpkgs wrapper still ships grim).
  #   - captureActiveMonitor must stay false: on Wayland Flameshot refuses it
  #     ("Capture Active Monitor is not supported on Wayland due to Wayland
  #     security model") and the capture fails outright on multi-monitor hosts.
  #     Single-monitor hosts short-circuit before that check, so this is a
  #     no-op there.
  xdg.configFile."flameshot/flameshot.ini".text = ''
    [General]
    captureActiveMonitor=false
    contrastOpacity=188
    drawColor=#ff0000
    saveAfterCopy=true
    savePath=${config.home.homeDirectory}/Pictures/Screenshots
    showSelectionGeometryHideTime=3000
    undoLimit=100
  '';

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
