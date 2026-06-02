{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
let
  wine-wrapped = pkgs.symlinkJoin {
    name = "wine-wrapped";
    paths = [ pkgs.wineWow64Packages.staging ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for f in wine wine64 wineserver; do
        [ -x "$out/bin/$f" ] && wrapProgram "$out/bin/$f" \
          --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib
      done
    '';
  };
in
{
  environment.systemPackages = with pkgs; [
    nh
    lsd
    wget
    fastfetch
    uutils-coreutils-noprefix
    procps
    (lib.meta.setPrio 11 toybox)
    bat
    btop
    wine-wrapped
    winetricks
    home-manager
    zenity
    appimage-run
    p7zip-rar
    qrrs
    pandoc
    inputs.nixwrap.packages.${pkgs.system}.wrap
  ];
  boot.loader.grub.configurationLimit = 3;

  nixpkgs.config = {
    allowBroken = true;
    allowUnfree = true;
  };
}
