{
  lib,
  stdenv,
  fetchurl,
  patchelf,
  glibc,
}:

let
  version = "17.3.4";
  # GitHub release assets are per-arch: omp-linux-x64 / omp-linux-arm64.
  asset = if stdenv.hostPlatform.isAarch64 then "arm64" else "x64";
  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-linux-${asset}";
    hash =
      if stdenv.hostPlatform.isAarch64 then
        "sha256-jifnv+SfwPM/bLC1ASirhf5UAzMNHftbs0zx90Is3Og="
      else
        "sha256-P85LJWKAZLDNe/vGJF7NraMxdQ7Us0Gspr0pukR4qrU=";
  };
  # NixOS's glibc loader differs between architectures.
  loader = if stdenv.hostPlatform.isAarch64 then "ld-linux-aarch64.so.1" else "ld-linux-x86-64.so.2";
in
stdenv.mkDerivation {
  pname = "omp";
  inherit version src;

  dontUnpack = true;
  # Nix's default fixupPhase strips the binary. Stripping removes the embedded
  # Bun runtime's section/note data and the binary degrades to bare `bun --help`.
  dontStrip = true;

  nativeBuildInputs = [ patchelf ];
  buildInputs = [ glibc ];

  # The GitHub release asset is a Bun-compiled bundle that embeds its own
  # runtime image in the ELF. autoPatchelfHook rewrites more than the dynamic
  # linker pointer (it mangles the embedded runtime and the binary degrades to
  # a bare `bun --help`). Only the `.interp` needs to change so the process
  # loads through NixOS's glibc loader.
  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/omp
    patchelf --set-interpreter ${glibc}/lib/${loader} $out/bin/omp
    runHook postInstall
  '';

  meta = {
    description = "oh-my-pi: coding agent with the IDE wired in (fork of pi)";
    homepage = "https://omp.sh";
    license = lib.licenses.asl20;
    mainProgram = "omp";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
