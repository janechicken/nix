{ pkgs, ... }:

{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      glib
      gtk3
      python3
      python3Packages.pygobject3
      gobject-introspection
    ];
  };
}
