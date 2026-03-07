{ config, pkgs, inputs, ... }:

{

  fonts.packages = with pkgs; [
    adwaita-fonts
    dejavu_fonts
    twemoji-color-font
    nerd-fonts.jetbrains-mono
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font" ];
      serif = [ "DejaVu Serif" ];
      sansSerif = [ "Adwaita Sans" ];
      emoji = [ "Twitter Color Emoji" ];
    };
  };
}
