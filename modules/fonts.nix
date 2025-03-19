{ config, pkgs, inputs, ... }:

{
  nixpkgs.overlays = [
    (final: prev: {
    sf-mono-liga-bin = prev.stdenvNoCC.mkDerivation rec {
      pname = "sf-mono-liga-bin";
      version = "dev";
      src = inputs.sf-mono-liga-src;
      dontConfigure = true;
      installPhase = ''
        mkdir -p $out/share/fonts/opentype
        cp -R $src/*.otf $out/share/fonts/opentype/
      '';
    };
  }) 
  ];

  fonts.packages = with pkgs; [
    sf-mono-liga-bin
    noto-fonts
    noto-fonts-cjk-sans
    twemoji-color-font
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = [ "Liga SFMono Nerd Font" ];
      serif = [ "Noto Serif" ];
      sansSerif = [ "Noto Sans" ];
      emoji = [ "Twitter Color Emoji" ];
    };
  };
}
