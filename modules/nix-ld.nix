{ pkgs, ... }:

{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      glib
      gtk3
      libGL
      python3
      python3Packages.pygobject3
      gobject-introspection
      xorg.libX11
    ];
  };
}
