{ config, pkgs, ... }:
{
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
}