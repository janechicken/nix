{
  config,
  pkgs,
  inputs,
  ...
}:

{

  fonts.packages = with pkgs; [
    adwaita-fonts
    dejavu_fonts
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font" ];
      serif = [ "DejaVu Serif" ];
      sansSerif = [ "Adwaita Sans" ];
      emoji = [ "Noto Color Emoji" ];
    };

    # Color emoji must come from a CBDT/CBLC (or COLR) font: Chromium/Skia — and
    # therefore Discord, Vesktop and every Electron app — does not render
    # SVG-in-OpenType color tables and silently falls back to the font's
    # monochrome `glyf` outlines. That is why twemoji-color-font (SVGinOT, `SVG `
    # table only) showed 🥒🐚🍰 as outline glyphs while Noto Color Emoji
    # (CBDT/CBLC) renders in color, so twemoji is no longer installed.
    #
    # The rule below appends Noto Color Emoji as a *weak, last* fallback family to
    # every pattern, which keeps it ahead of Unifont Upper for emoji code points
    # (Unifont also covers plane 1, but only with monochrome bitmaps) without
    # displacing any family a client actually asks for: Latin text keeps Adwaita
    # Sans / DejaVu Serif / JetBrainsMono Nerd Font, and Nerd Font PUA glyphs
    # (U+E000–U+F8FF, U+F0000+) are untouched because Noto Color Emoji does not
    # cover the private use area.
    localConf = ''
      <?xml version="1.0"?>
      <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
      <fontconfig>
        <match target="pattern">
          <edit name="family" mode="append_last" binding="weak">
            <string>Noto Color Emoji</string>
          </edit>
        </match>
      </fontconfig>
    '';
  };
}
