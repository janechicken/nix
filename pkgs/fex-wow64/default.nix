{
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation rec {
  pname = "fex-wow64";
  version = "11.16";

  src = fetchurl {
    url = "https://github.com/AndreRH/hangover/releases/download/hangover-11.16/hangover_11.16_dlls.tar";
    hash = "sha256-ZFvN+GHbFXuQV4VMmHl87bR3oAcjQpobmWRQ37KPxtI=";
  };

  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/wine/aarch64-windows" extracted
    tar -xf "$src" -C extracted libwow64fex.dll libarm64ecfex.dll

    # Wine 11 ARM64 WoW64 loads the i386 CPU emulator as xtajit.dll (native ARM64
    # PE, i.e. FEX's wow64 build) and the AMD64 one as xtajit64.dll (ARM64EC PE).
    install -Dm755 extracted/libwow64fex.dll "$out/lib/wine/aarch64-windows/xtajit.dll"
    install -Dm755 extracted/libarm64ecfex.dll "$out/lib/wine/aarch64-windows/xtajit64.dll"

    runHook postInstall
  '';

  meta = {
    description = "FEX WoW64/ARM64EC CPU emulator DLLs for ARM64 Wine (from Hangover)";
    platforms = [ "aarch64-linux" ];
  };
}
