# ida-pro — wrapper around an out-of-band IDA Pro installation.
#
# IDA is proprietary; the install lives under ~/.local/opt/ida
# (user-managed, not built by nix). NixOS has no /usr/lib, so the raw
# binaries fail with `libXext.so.6: cannot open shared object file`. This
# derivation only assembles the *library* dependencies IDA ships without
# (X11, xcb, GL, stdc++, …) and wraps `ida` / `idat` with an LD_LIBRARY_PATH
# pointing at them plus the install dir itself (IDA loads libida.so and its
# bundled Qt from its own directory — keep it LAST so its own libs win).
#
# The lib set was derived by running `ldd` over ida/idat/libida*/idapython3
# and the Qt platform plugins (plugins/platforms, xcbglintegrations,
# wayland-*) and resolving every `not found`. The xcb-util split libs are
# needed by the Qt xcb platform plugin; libdrm by the EGL integration.
#
# $HOME and IDA_USER_DIR are expanded at RUNTIME (not build time) so the
# same store path works for any user.
{
  lib,
  stdenvNoCC,
  gcc,
  libglvnd,
  libx11,
  libxext,
  libxtst,
  libxkbcommon,
  glib,
  zlib,
  freetype,
  fontconfig,
  dbus,
  wayland,
  libxcb,
  xcbutilcursor,
  xcbutilimage,
  xcbutilkeysyms,
  xcbutilwm,
  xcbutilrenderutil,
  xcbutil,
  libdrm,
  libsecret,
  ida-pro-mcp,
  idaInstallDir ? "~/.local/opt/ida",
}:

let
  # Library-bearing outputs only. Most of these packages split dev/lib
  # outputs; referencing .out/.lib directly keeps the closure slim.
  libPaths = [
    gcc.cc.lib
    libglvnd.out
    libx11.out
    libxext.out
    libxtst.out
    libxkbcommon.out
    glib.out
    zlib.out
    freetype.out
    fontconfig.lib
    dbus.lib
    wayland.out
    libxcb.out
    xcbutilcursor.out
    xcbutilimage.out
    xcbutilkeysyms.out
    xcbutilwm.out
    xcbutilrenderutil.out
    xcbutil.out
    libdrm.out
    libsecret.out # dlopened by IDA for secret storage
  ];

  libDirs = lib.concatStringsSep ":" (map (p: "${p}/lib") libPaths);
in
stdenvNoCC.mkDerivation {
  pname = "ida-pro";
  version = "9.4";

  dontUnpack = true;
  dontBuild = true;

  installPhase =
    let
      # Shared env preamble: libdirs + install dir LAST (IDA's own bundled
      # libs must win), IDADIR for idalib/py-activate-idalib consumers.
      envPreamble = ''
        export LD_LIBRARY_PATH="${libDirs}:${idaInstallDir}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        export IDADIR="$HOME/.local/opt/ida"
      '';

      wrapper = name: ''
        #!${stdenvNoCC.shell}
        # IDA resolves libida.so and bundled Qt from its own dir; that entry
        # must stay last in LD_LIBRARY_PATH. Without the libdirs NixOS has no
        # /usr/lib to fall back on and the binary dies on libXext.so.6.
        ${envPreamble}
        exec "$IDADIR/${name}" "$@"
      '';

      # ida-pro-mcp binaries (idalib-mcp dlopens libidalib.so out of IDADIR)
      # need the identical environment; wrap them pointing at the mcp package.
      mcpWrapper = name: ''
        #!${stdenvNoCC.shell}
        ${envPreamble}
        exec "${ida-pro-mcp}/bin/${name}" "$@"
      '';
    in
    ''
      runHook preInstall
      mkdir -p $out/bin
      ${lib.concatStringsSep "\n" (map (name: ''
        cat > $out/bin/${name} <<'EOF'
        ${wrapper name}
        EOF
        chmod +x $out/bin/${name}
      '') [ "ida" "idat" ])}
      ${lib.concatStringsSep "\n" (map (name: ''
        cat > $out/bin/${name} <<'EOF'
        ${mcpWrapper name}
        EOF
        chmod +x $out/bin/${name}
      '') [ "ida-pro-mcp" "idalib-mcp" ])}
      runHook postInstall
    '';

  meta = {
    description = "Wrapper for the out-of-band IDA Pro 9.4 install (fixes NixOS shared-library resolution)";
    platforms = lib.platforms.linux;
  };
}
