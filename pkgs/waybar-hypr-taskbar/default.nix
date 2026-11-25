{
  lib,
  stdenv,
  pkg-config,
  gtk3,
  glib,
  json_c,
}:

stdenv.mkDerivation {
  pname = "waybar-hypr-taskbar";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    gtk3
    glib
    json_c
  ];

  cflags = [
    "-O2"
    "-Wall"
    "-Wextra"
    "-Werror"
  ];

  buildPhase = ''
    runHook preBuild
    $CC ''${cflags} -shared -fPIC \
      taskbar.c -o libwaybar-hypr-taskbar.so \
      $(pkg-config --cflags --libs gtk+-3.0 gio-unix-2.0 json-c) -lm
    # Dev helper (`-DTASKBAR_CHECK_MAIN`): prints the icon each window class
    # resolves to. It takes class names as argv, so it is only smoke-tested
    # here and never installed into $out/bin.
    $CC ''${cflags} -DTASKBAR_CHECK_MAIN \
      taskbar.c -o waybar-hypr-taskbar-check \
      $(pkg-config --cflags --libs gtk+-3.0 gio-unix-2.0 json-c) -lm
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    # No argv: gtk_init_check may fail without a display, which is fine — this
    # only proves the helper links and starts.
    ./waybar-hypr-taskbar-check
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib"
    install -m 755 libwaybar-hypr-taskbar.so "$out/lib/libwaybar-hypr-taskbar.so"
    runHook postInstall
  '';

  meta = {
    description = "Waybar CFFI active-workspace taskbar for Hyprland with real per-app GTK icons";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
