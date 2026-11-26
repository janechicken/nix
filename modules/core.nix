{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
let
  isArm = pkgs.stdenv.hostPlatform.isAarch64;

  # Wine's ARM64 WoW64 needs a CPU emulator DLL to run i386 PE binaries. nixpkgs'
  # Wine builds xtajit64.dll (ARM64EC) but not the native ARM64 xtajit.dll, so
  # 32-bit x86 .exes fail with "cannot find xtajit.dll". Ship FEX's Hangover
  # DLLs and expose them through WINEDLLPATH, from which Wine picks up
  # <dllpath>/aarch64-windows/{xtajit,xtajit64}.dll for new prefixes (and for
  # existing ones after `wine wineboot -u`).
  fexDlls = pkgs.callPackage ../pkgs/fex-wow64 { };

  wine-wrapped = pkgs.symlinkJoin {
    name = "wine-wrapped";
    paths = [ pkgs.wineWow64Packages.staging ] ++ lib.optionals isArm [ fexDlls ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for f in wine wine64 wineserver; do
        [ -x "$out/bin/$f" ] && wrapProgram "$out/bin/$f" \
          --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib \
          ${lib.optionalString isArm "--prefix WINEDLLPATH : $out/lib/wine"}
      done
    '';
  };
in
{
  programs.nh = {
    enable = true;
    flake = "${config.users.users.jane.home}/nix";
  };

  environment.systemPackages = (
    with pkgs;
    [
      lsd
      jq
      openssl
      wget
      fastfetch
      uutils-coreutils-noprefix
      procps
      (lib.meta.setPrio 11 toybox)
      bat
      btop
      home-manager
      zenity
      appimage-run
      p7zip-rar
      qrrs
      tmux
      pandoc
      python3Packages.weasyprint
      inputs.nixwrap.packages.${pkgs.system}.wrap
      wine-wrapped
      pkgs.winetricks
    ]
  );
  boot.loader.grub.configurationLimit = 3;

  nixpkgs.config = {
    allowBroken = true;
    allowUnfree = true;
  };
}
