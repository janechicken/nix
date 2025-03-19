{ config, pkgs, inputs, ... }:

{

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    twemoji-color-font
    nerd-fonts.jetbrains-mono
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font" ];
      serif = [ "Noto Serif" ];
      sansSerif = [ "Noto Sans" ];
      emoji = [ "Twitter Color Emoji" ];
    };
  };
}
